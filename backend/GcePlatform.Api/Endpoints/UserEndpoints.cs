using System.Security.Claims;
using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Models;
using GcePlatform.Api.Services;

namespace GcePlatform.Api.Endpoints;

public static class UserEndpoints
{
    public static WebApplication MapUserEndpoints(this WebApplication app)
    {
        // GET /users
        app.MapGet("/users", async (DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var items = await conn.QueryAsync<UserDto>(@"
                SELECT
                    UserId,
                    UPN,
                    DisplayName,
                    IsActive,
                    RoleCount,
                    RoleList,
                    SiteCount,
                    AccountCount,
                    PackageCount,
                    ReportCount,
                    GapStatus
                FROM App.vUsers
                ORDER BY DisplayName");

            var list = items.ToList();
            return Results.Ok(new ApiList<UserDto>(list, list.Count));
        }).RequireAuthorization();

        // POST /users
        app.MapPost("/users", async (ClaimsPrincipal user, CreateUserRequest request, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.UsersManage))
                return Results.Forbid();

            var p = new DynamicParameters();
            p.Add("@UPN", request.Upn.Trim().ToLowerInvariant());
            p.Add("@DisplayName", request.DisplayName);
            p.Add("@UserId", dbType: System.Data.DbType.Int32,
                  direction: System.Data.ParameterDirection.Output);

            await conn.ExecuteAsync("App.UpsertUser", p,
                commandType: System.Data.CommandType.StoredProcedure);

            var newId = p.Get<int>("@UserId");

            var created = await conn.QuerySingleAsync<UserDto>(@"
                SELECT UserId, UPN, DisplayName, IsActive,
                       RoleCount, RoleList, SiteCount, AccountCount, PackageCount, ReportCount, GapStatus
                FROM App.vUsers
                WHERE UserId = @Id",
                new { Id = newId });

            return Results.Created($"/users/{newId}", created);
        }).RequireAuthorization();

        // GET /users/{id}
        app.MapGet("/users/{id:int}", async (int id, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var item = await conn.QuerySingleOrDefaultAsync<UserDto>(@"
                SELECT UserId, UPN, DisplayName, IsActive,
                       RoleCount, RoleList, SiteCount, AccountCount, PackageCount, ReportCount, GapStatus
                FROM App.vUsers
                WHERE UserId = @Id",
                new { Id = id });

            return item is null
                ? Results.NotFound(new ApiError("USER_NOT_FOUND", $"User {id} not found."))
                : Results.Ok(item);
        }).RequireAuthorization();

        // PATCH /users/{id}/status
        app.MapMethods("/users/{id:int}/status", new[] { "PATCH" },
            async (ClaimsPrincipal currentUser, int id, SetActiveRequest req, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(currentUser, conn, Permissions.UsersManage))
                return Results.Forbid();

            var user = await conn.QuerySingleOrDefaultAsync<UserDto>(@"
                SELECT UserId, UPN, DisplayName, IsActive,
                       RoleCount, RoleList, SiteCount, AccountCount, PackageCount, ReportCount, GapStatus
                FROM App.vUsers
                WHERE UserId = @Id",
                new { Id = id });

            if (user is null)
                return Results.NotFound(new ApiError("USER_NOT_FOUND", $"User {id} not found."));

            await conn.ExecuteAsync("App.usp_SetUserActive",
                new { UserId = id, req.IsActive },
                commandType: System.Data.CommandType.StoredProcedure);

            return Results.NoContent();
        }).RequireAuthorization();

        // GET /users/{id}/roles — roles the user belongs to (with IDs for removal)
        app.MapGet("/users/{id:int}/roles", async (int id, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var items = await conn.QueryAsync<RoleDto>(@"
                SELECT
                    r.RoleId,
                    r.RoleCode,
                    r.RoleName,
                    r.Description,
                    r.IsActive,
                    r.AccountId,
                    r.AccountCode,
                    r.AccountName,
                    r.MemberCount,
                    r.AccessGrantCount,
                    r.PackageGrantCount
                FROM App.vUserRoles AS ur
                JOIN App.vRoles AS r
                    ON r.RoleId = ur.RoleId
                WHERE ur.UserId = @Id
                ORDER BY r.RoleCode",
                new { Id = id });

            var list = items.ToList();
            return Results.Ok(new ApiList<RoleDto>(list, list.Count));
        }).RequireAuthorization();

        // GET /users/{id}/grants
        app.MapGet("/users/{id:int}/grants", async (int id, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var items = await conn.QueryAsync<GrantDto>(@"
                SELECT PrincipalAccessGrantId, PrincipalId, PrincipalType, PrincipalName,
                       AccessType, ScopeType, AccountCode, AccountName,
                       OrgUnitType, OrgUnitCode, OrgUnitName, GrantedOnUtc
                FROM App.vGrants
                WHERE PrincipalId = @Id
                ORDER BY AccountCode, OrgUnitCode",
                new { Id = id });

            var list = items.ToList();
            return Results.Ok(new ApiList<GrantDto>(list, list.Count));
        }).RequireAuthorization();

        // GET /users/{id}/package-grants
        app.MapGet("/users/{id:int}/package-grants", async (int id, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var items = await conn.QueryAsync<PackageGrantDto>(@"
                -- Direct package grants on the user's own principal
                SELECT
                    ppg.PrincipalPackageGrantId,
                    u.UserId                       AS PrincipalId,
                    'User'                         AS PrincipalType,
                    up.PrincipalName               AS PrincipalName,
                    'DIRECT'                       AS GrantSource,
                    CAST(NULL AS NVARCHAR(100))    AS SourceCode,
                    CAST(NULL AS NVARCHAR(200))    AS SourceName,
                    ppg.GrantScope,
                    pkg.PackageCode,
                    pkg.PackageName,
                    ppg.GrantedOnUtc
                FROM Sec.[User] AS u
                JOIN Sec.Principal AS up
                    ON up.PrincipalId = u.UserId
                JOIN Sec.PrincipalPackageGrant AS ppg
                    ON ppg.PrincipalId = u.UserId
                    AND ppg.RevokedAt IS NULL
                    AND (ppg.ExpiresAt IS NULL OR ppg.ExpiresAt > SYSUTCDATETIME())
                LEFT JOIN Dim.Package AS pkg
                    ON pkg.PackageId = ppg.PackageId
                WHERE u.UserId = @Id

                UNION ALL

                -- Package grants via role membership
                SELECT
                    ppg.PrincipalPackageGrantId,
                    u.UserId                       AS PrincipalId,
                    'User'                         AS PrincipalType,
                    up.PrincipalName               AS PrincipalName,
                    'ROLE'                         AS GrantSource,
                    r.RoleCode                     AS SourceCode,
                    r.RoleName                     AS SourceName,
                    ppg.GrantScope,
                    pkg.PackageCode,
                    pkg.PackageName,
                    ppg.GrantedOnUtc
                FROM Sec.[User] AS u
                JOIN Sec.Principal AS up
                    ON up.PrincipalId = u.UserId
                JOIN Sec.RoleMembership AS rm
                    ON rm.MemberPrincipalId = u.UserId
                JOIN Sec.Role AS r
                    ON r.RoleId = rm.RoleId
                JOIN Sec.Principal AS rp
                    ON rp.PrincipalId = r.RoleId
                    AND rp.IsActive = 1
                JOIN Sec.PrincipalPackageGrant AS ppg
                    ON ppg.PrincipalId = r.RoleId
                    AND ppg.RevokedAt IS NULL
                    AND (ppg.ExpiresAt IS NULL OR ppg.ExpiresAt > SYSUTCDATETIME())
                LEFT JOIN Dim.Package AS pkg
                    ON pkg.PackageId = ppg.PackageId
                WHERE u.UserId = @Id

                ORDER BY GrantSource, PackageCode, SourceCode",
                new { Id = id });

            var list = items.ToList();
            return Results.Ok(new ApiList<PackageGrantDto>(list, list.Count));
        }).RequireAuthorization();

        // GET /users/{id}/effective-access — all access reasons (direct, role, delegation)
        app.MapGet("/users/{id:int}/effective-access", async (int id, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var items = await conn.QueryAsync<EffectiveAccessEntryDto>(@"
                -- Direct grants on the user's own principal
                SELECT
                    'DIRECT'            AS GrantSource,
                    NULL                AS SourceCode,
                    NULL                AS SourceName,
                    pag.AccessType,
                    pag.ScopeType,
                    a.AccountCode,
                    a.AccountName,
                    ou.OrgUnitCode      AS ScopeOrgUnitCode,
                    ou.OrgUnitName      AS ScopeOrgUnitName,
                    ou.OrgUnitType      AS ScopeOrgUnitType
                FROM Sec.[User] AS u
                JOIN Sec.PrincipalAccessGrant AS pag
                    ON pag.PrincipalId = u.UserId
                    AND pag.RevokedAt IS NULL
                    AND (pag.ExpiresAt IS NULL OR pag.ExpiresAt > SYSUTCDATETIME())
                LEFT JOIN Dim.Account   AS a  ON a.AccountId  = pag.AccountId
                LEFT JOIN Dim.OrgUnit   AS ou ON ou.OrgUnitId = pag.OrgUnitId
                WHERE u.UserId = @Id

                UNION ALL

                -- Grants via role membership
                SELECT
                    'ROLE'              AS GrantSource,
                    r.RoleCode          AS SourceCode,
                    r.RoleName          AS SourceName,
                    pag.AccessType,
                    pag.ScopeType,
                    a.AccountCode,
                    a.AccountName,
                    ou.OrgUnitCode      AS ScopeOrgUnitCode,
                    ou.OrgUnitName      AS ScopeOrgUnitName,
                    ou.OrgUnitType      AS ScopeOrgUnitType
                FROM Sec.[User] AS u
                JOIN Sec.RoleMembership AS rm
                    ON rm.MemberPrincipalId = u.UserId
                JOIN Sec.Role AS r
                    ON r.RoleId = rm.RoleId
                JOIN Sec.Principal AS rp
                    ON rp.PrincipalId = rm.RoleId AND rp.IsActive = 1
                JOIN Sec.PrincipalAccessGrant AS pag
                    ON pag.PrincipalId = r.RoleId
                    AND pag.RevokedAt IS NULL
                    AND (pag.ExpiresAt IS NULL OR pag.ExpiresAt > SYSUTCDATETIME())
                LEFT JOIN Dim.Account   AS a  ON a.AccountId  = pag.AccountId
                LEFT JOIN Dim.OrgUnit   AS ou ON ou.OrgUnitId = pag.OrgUnitId
                WHERE u.UserId = @Id

                UNION ALL

                -- Active delegations to this user
                SELECT
                    'DELEGATION'                AS GrantSource,
                    delegator.PrincipalName     AS SourceCode,
                    delegatorU.DisplayName      AS SourceName,
                    del.AccessType,
                    del.ScopeType,
                    a.AccountCode,
                    a.AccountName,
                    ou.OrgUnitCode              AS ScopeOrgUnitCode,
                    ou.OrgUnitName              AS ScopeOrgUnitName,
                    ou.OrgUnitType              AS ScopeOrgUnitType
                FROM Sec.[User] AS u
                JOIN Sec.PrincipalDelegation AS del
                    ON del.DelegatePrincipalId = u.UserId
                    AND del.IsActive = 1
                    AND (del.ValidFromDate IS NULL OR del.ValidFromDate <= CAST(SYSUTCDATETIME() AS DATE))
                    AND (del.ValidToDate   IS NULL OR del.ValidToDate   >= CAST(SYSUTCDATETIME() AS DATE))
                JOIN Sec.Principal AS delegator ON delegator.PrincipalId = del.DelegatorPrincipalId
                LEFT JOIN Sec.[User] AS delegatorU ON delegatorU.UserId  = del.DelegatorPrincipalId
                LEFT JOIN Dim.Account   AS a  ON a.AccountId  = del.AccountId
                LEFT JOIN Dim.OrgUnit   AS ou ON ou.OrgUnitId = del.OrgUnitId
                WHERE u.UserId = @Id

                ORDER BY GrantSource, AccountCode, ScopeOrgUnitCode",
                new { Id = id });

            var list = items.ToList();
            return Results.Ok(new ApiList<EffectiveAccessEntryDto>(list, list.Count));
        }).RequireAuthorization();

        // GET /users/{id}/resolved-access — actual sites + reports via App.GetUserEffectiveAccess SP
        app.MapGet("/users/{id:int}/resolved-access", async (int id, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var upn = await conn.QuerySingleOrDefaultAsync<string>(
                "SELECT u.UPN FROM Sec.[User] AS u WHERE u.UserId = @Id", new { Id = id });
            if (upn is null) return Results.NotFound();

            using var multi = await conn.QueryMultipleAsync(
                "EXEC App.GetUserEffectiveAccess @UserUPN", new { UserUPN = upn });

            var sites   = (await multi.ReadAsync<EffectiveSiteDto>()).ToList();
            var reports = (await multi.ReadAsync<EffectiveReportDto>()).ToList();

            return Results.Ok(new ResolvedAccessDto(sites, reports));
        }).RequireAuthorization();

        // GET /users/{id}/delegations
        app.MapGet("/users/{id:int}/delegations", async (int id, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var items = await conn.QueryAsync<DelegationDto>(@"
                SELECT
                    PrincipalDelegationId,
                    DelegatorPrincipalId,
                    DelegatePrincipalId,
                    DelegatorName,
                    DelegatorType,
                    DelegateName,
                    DelegateType,
                    AccessType,
                    ScopeType,
                    AccountCode,
                    AccountName,
                    OrgUnitType,
                    OrgUnitCode,
                    OrgUnitName,
                    ValidFromDate,
                    ValidToDate,
                    IsActive,
                    CreatedOnUtc
                FROM App.vDelegations
                WHERE DelegatePrincipalId = @Id
                ORDER BY DelegatorName, AccountCode, OrgUnitCode",
                new { Id = id });

            var list = items.ToList();
            return Results.Ok(new ApiList<DelegationDto>(list, list.Count));
        }).RequireAuthorization();

        return app;
    }
}
