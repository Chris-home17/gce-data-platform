using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Models;

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
                    GapStatus
                FROM App.vUsers
                ORDER BY DisplayName");

            var list = items.ToList();
            return Results.Ok(new ApiList<UserDto>(list, list.Count));
        }).RequireAuthorization();

        // POST /users
        app.MapPost("/users", async (CreateUserRequest request, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();

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
                       RoleCount, RoleList, SiteCount, AccountCount, GapStatus
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
                       RoleCount, RoleList, SiteCount, AccountCount, GapStatus
                FROM App.vUsers
                WHERE UserId = @Id",
                new { Id = id });

            return item is null
                ? Results.NotFound(new ApiError("USER_NOT_FOUND", $"User {id} not found."))
                : Results.Ok(item);
        }).RequireAuthorization();

        // PATCH /users/{id}/status
        app.MapMethods("/users/{id:int}/status", new[] { "PATCH" },
            async (int id, SetActiveRequest req, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var user = await conn.QuerySingleOrDefaultAsync<UserDto>(@"
                SELECT UserId, UPN, DisplayName, IsActive,
                       RoleCount, RoleList, SiteCount, AccountCount, GapStatus
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
                SELECT PrincipalPackageGrantId, PrincipalId, PrincipalType, PrincipalName,
                       GrantScope, PackageCode, PackageName, GrantedOnUtc
                FROM App.vPackageGrants
                WHERE PrincipalId = @Id
                ORDER BY PackageCode",
                new { Id = id });

            var list = items.ToList();
            return Results.Ok(new ApiList<PackageGrantDto>(list, list.Count));
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
