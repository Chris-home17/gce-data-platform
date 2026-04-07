using System.Security.Claims;
using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Models;
using GcePlatform.Api.Services;

namespace GcePlatform.Api.Endpoints;

public static class AccountEndpoints
{
    private static async Task<int?> GetCurrentUserIdAsync(ClaimsPrincipal user, DbConnectionFactory db)
    {
        using var conn = db.CreateConnection();
        var upn = PlatformAuthService.GetUpn(user);
        if (string.IsNullOrWhiteSpace(upn))
            return null;

        return await conn.ExecuteScalarAsync<int?>(
            "SELECT UserId FROM App.vUsers WHERE UPN = @Upn AND IsActive = 1",
            new { Upn = upn });
    }

    public static WebApplication MapAccountEndpoints(this WebApplication app)
    {
        // GET /accounts
        app.MapGet("/accounts", async (ClaimsPrincipal user, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            IEnumerable<AccountDto> items;
            if (await platformAuth.HasPermissionAsync(user, conn, Permissions.SuperAdmin))
            {
                items = await conn.QueryAsync<AccountDto>(@"
                    SELECT
                        AccountId,
                        AccountCode,
                        AccountName,
                        IsActive,
                        SiteCount,
                        UserCount
                    FROM App.vAccounts
                    ORDER BY AccountName");
            }
            else
            {
                var currentUserId = await GetCurrentUserIdAsync(user, db);
                if (currentUserId is null)
                    return Results.Ok(new ApiList<AccountDto>(new List<AccountDto>(), 0));

                items = await conn.QueryAsync<AccountDto>(@"
                    WITH UserGrants AS
                    (
                        SELECT
                            eff.AccessType,
                            eff.AccountId,
                            eff.ScopeType,
                            eff.OrgUnitId
                        FROM Sec.vUserGrantPrincipals AS gp
                        JOIN Sec.vPrincipalEffectiveAccess AS eff
                            ON eff.PrincipalId = gp.GrantPrincipalId
                        WHERE gp.UserPrincipalId = @UserId
                    ),
                    AccessibleAccounts AS
                    (
                        SELECT DISTINCT a.AccountId
                        FROM UserGrants AS g
                        JOIN Dim.Account AS a
                            ON g.ScopeType = 'NONE'
                           AND (
                                g.AccessType = 'ALL'
                                OR (g.AccessType = 'ACCOUNT' AND a.AccountId = g.AccountId)
                           )

                        UNION

                        SELECT DISTINCT site.AccountId
                        FROM UserGrants AS g
                        JOIN Dim.OrgUnit AS base
                            ON g.ScopeType = 'ORGUNIT'
                           AND g.OrgUnitId = base.OrgUnitId
                        JOIN Dim.OrgUnit AS site
                            ON site.Path LIKE base.Path + '%'
                        WHERE site.AccountId IS NOT NULL
                          AND (
                                g.AccessType = 'ALL'
                                OR (g.AccessType = 'ACCOUNT' AND site.AccountId = g.AccountId)
                          )
                    )
                    SELECT
                        a.AccountId,
                        a.AccountCode,
                        a.AccountName,
                        a.IsActive,
                        a.SiteCount,
                        a.UserCount
                    FROM App.vAccounts AS a
                    JOIN AccessibleAccounts AS access
                        ON access.AccountId = a.AccountId
                    ORDER BY a.AccountName",
                    new { UserId = currentUserId.Value });
            }

            var list = items.ToList();
            return Results.Ok(new ApiList<AccountDto>(list, list.Count));
        }).RequireAuthorization();

        // GET /accounts/{id}
        app.MapGet("/accounts/{id:int}", async (int id, ClaimsPrincipal user, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            AccountDto? item;
            if (await platformAuth.HasPermissionAsync(user, conn, Permissions.SuperAdmin))
            {
                item = await conn.QuerySingleOrDefaultAsync<AccountDto>(@"
                    SELECT
                        AccountId,
                        AccountCode,
                        AccountName,
                        IsActive,
                        SiteCount,
                        UserCount
                    FROM App.vAccounts
                    WHERE AccountId = @Id",
                    new { Id = id });
            }
            else
            {
                var currentUserId = await GetCurrentUserIdAsync(user, db);
                if (currentUserId is null)
                    return Results.NotFound(new ApiError("ACCOUNT_NOT_FOUND", $"Account {id} not found."));

                item = await conn.QuerySingleOrDefaultAsync<AccountDto>(@"
                    WITH UserGrants AS
                    (
                        SELECT
                            eff.AccessType,
                            eff.AccountId,
                            eff.ScopeType,
                            eff.OrgUnitId
                        FROM Sec.vUserGrantPrincipals AS gp
                        JOIN Sec.vPrincipalEffectiveAccess AS eff
                            ON eff.PrincipalId = gp.GrantPrincipalId
                        WHERE gp.UserPrincipalId = @UserId
                    ),
                    AccessibleAccounts AS
                    (
                        SELECT DISTINCT a.AccountId
                        FROM UserGrants AS g
                        JOIN Dim.Account AS a
                            ON g.ScopeType = 'NONE'
                           AND (
                                g.AccessType = 'ALL'
                                OR (g.AccessType = 'ACCOUNT' AND a.AccountId = g.AccountId)
                           )

                        UNION

                        SELECT DISTINCT site.AccountId
                        FROM UserGrants AS g
                        JOIN Dim.OrgUnit AS base
                            ON g.ScopeType = 'ORGUNIT'
                           AND g.OrgUnitId = base.OrgUnitId
                        JOIN Dim.OrgUnit AS site
                            ON site.Path LIKE base.Path + '%'
                        WHERE site.AccountId IS NOT NULL
                          AND (
                                g.AccessType = 'ALL'
                                OR (g.AccessType = 'ACCOUNT' AND site.AccountId = g.AccountId)
                          )
                    )
                    SELECT
                        a.AccountId,
                        a.AccountCode,
                        a.AccountName,
                        a.IsActive,
                        a.SiteCount,
                        a.UserCount
                    FROM App.vAccounts AS a
                    JOIN AccessibleAccounts AS access
                        ON access.AccountId = a.AccountId
                    WHERE a.AccountId = @Id",
                    new { Id = id, UserId = currentUserId.Value });
            }

            return item is null
                ? Results.NotFound(new ApiError("ACCOUNT_NOT_FOUND", $"Account {id} not found."))
                : Results.Ok(item);
        }).RequireAuthorization();

        // GET /accounts/{id}/users
        app.MapGet("/accounts/{id:int}/users", async (int id, ClaimsPrincipal user, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.SuperAdmin))
            {
                var currentUserId = await GetCurrentUserIdAsync(user, db);
                if (currentUserId is null)
                    return Results.NotFound(new ApiError("ACCOUNT_NOT_FOUND", $"Account {id} not found."));

                var canAccess = await conn.ExecuteScalarAsync<bool>(@"
                    WITH UserGrants AS
                    (
                        SELECT
                            eff.AccessType,
                            eff.AccountId,
                            eff.ScopeType,
                            eff.OrgUnitId
                        FROM Sec.vUserGrantPrincipals AS gp
                        JOIN Sec.vPrincipalEffectiveAccess AS eff
                            ON eff.PrincipalId = gp.GrantPrincipalId
                        WHERE gp.UserPrincipalId = @UserId
                    )
                    SELECT CAST(
                        CASE WHEN EXISTS
                        (
                            SELECT 1
                            FROM UserGrants AS g
                            WHERE
                                (g.ScopeType = 'NONE' AND (g.AccessType = 'ALL' OR (g.AccessType = 'ACCOUNT' AND g.AccountId = @AccountId)))
                                OR
                                (g.ScopeType = 'ORGUNIT' AND EXISTS
                                (
                                    SELECT 1
                                    FROM Dim.OrgUnit AS base
                                    JOIN Dim.OrgUnit AS site
                                        ON site.Path LIKE base.Path + '%'
                                    WHERE base.OrgUnitId = g.OrgUnitId
                                      AND site.AccountId = @AccountId
                                      AND (
                                            g.AccessType = 'ALL'
                                            OR (g.AccessType = 'ACCOUNT' AND g.AccountId = @AccountId)
                                          )
                                ))
                        )
                        THEN 1 ELSE 0 END AS bit)",
                    new { UserId = currentUserId.Value, AccountId = id });

                if (!canAccess)
                    return Results.NotFound(new ApiError("ACCOUNT_NOT_FOUND", $"Account {id} not found."));
            }

            var accountExists = await conn.ExecuteScalarAsync<int>(@"
                SELECT COUNT(1)
                FROM App.vAccounts
                WHERE AccountId = @Id",
                new { Id = id });

            if (accountExists == 0)
                return Results.NotFound(new ApiError("ACCOUNT_NOT_FOUND", $"Account {id} not found."));

            var items = await conn.QueryAsync<UserDto>(@"
                SELECT
                    u.UserId,
                    u.UPN,
                    u.DisplayName,
                    u.IsActive,
                    u.RoleCount,
                    u.RoleList,
                    scope.SiteCount,
                    1 AS AccountCount,
                    u.PackageCount,
                    u.ReportCount,
                    u.GapStatus
                FROM App.vUsers AS u
                JOIN
                (
                    SELECT
                        auth.UserPrincipalId,
                        COUNT(DISTINCT auth.SiteOrgUnitId) AS SiteCount
                    FROM Sec.vAuthorizedSitesDynamic AS auth
                    WHERE auth.AccountId = @Id
                    GROUP BY auth.UserPrincipalId
                ) AS scope
                    ON scope.UserPrincipalId = u.UserId
                ORDER BY u.DisplayName",
                new { Id = id });

            var list = items.ToList();
            return Results.Ok(new ApiList<UserDto>(list, list.Count));
        }).RequireAuthorization();

        // POST /accounts
        app.MapPost("/accounts", async (ClaimsPrincipal user, CreateAccountRequest request, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.AccountsManage))
                return Results.Forbid();

            var p = new DynamicParameters();
            p.Add("@AccountCode", request.AccountCode.ToUpperInvariant());
            p.Add("@AccountName", request.AccountName);
            p.Add("@IsActive", true);
            p.Add("@ApplyPolicies", true);
            p.Add("@AccountId", dbType: System.Data.DbType.Int32,
                  direction: System.Data.ParameterDirection.Output);

            await conn.ExecuteAsync("App.UpsertAccount", p,
                commandType: System.Data.CommandType.StoredProcedure);

            var newId = p.Get<int>("@AccountId");

            var created = await conn.QuerySingleAsync<AccountDto>(@"
                SELECT AccountId, AccountCode, AccountName,
                       IsActive, SiteCount, UserCount
                FROM App.vAccounts
                WHERE AccountId = @Id",
                new { Id = newId });

            return Results.Created($"/accounts/{newId}", created);
        }).RequireAuthorization();

        // PATCH /accounts/{id}/status
        app.MapMethods("/accounts/{id:int}/status", new[] { "PATCH" },
            async (ClaimsPrincipal user, int id, SetActiveRequest req, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.AccountsManage))
                return Results.Forbid();
            var item = await conn.QuerySingleOrDefaultAsync<AccountDto>(
                "SELECT AccountId, AccountCode, AccountName, CAST(IsActive AS bit) AS IsActive, SiteCount, UserCount FROM App.vAccounts WHERE AccountId = @Id",
                new { Id = id });

            if (item is null)
                return Results.NotFound(new ApiError("ACCOUNT_NOT_FOUND", $"Account {id} not found."));

            var p = new DynamicParameters();
            p.Add("@AccountCode",   item.AccountCode);
            p.Add("@AccountName",   item.AccountName);
            p.Add("@IsActive",      req.IsActive ? 1 : 0);
            p.Add("@ApplyPolicies", 0);
            p.Add("@AccountId",     dbType: System.Data.DbType.Int32,
                                    direction: System.Data.ParameterDirection.Output);

            await conn.ExecuteAsync("App.UpsertAccount", p,
                commandType: System.Data.CommandType.StoredProcedure);

            return Results.NoContent();
        }).RequireAuthorization();

        return app;
    }
}
