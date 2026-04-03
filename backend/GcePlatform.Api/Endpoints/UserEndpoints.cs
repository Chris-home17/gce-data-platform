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
            var affected = await conn.ExecuteAsync(
                @"
                UPDATE Sec.Principal
                SET IsActive = @IsActive,
                    ModifiedOnUtc = SYSUTCDATETIME()
                WHERE PrincipalId = @Id;

                UPDATE Sec.[User]
                SET IsActive = @IsActive,
                    ModifiedOnUtc = SYSUTCDATETIME()
                WHERE UserId = @Id;
                ",
                new { IsActive = req.IsActive, Id = id });

            return affected == 0
                ? Results.NotFound(new ApiError("USER_NOT_FOUND", $"User {id} not found."))
                : Results.NoContent();
        }).RequireAuthorization();

        // GET /users/{id}/roles — roles the user belongs to (with IDs for removal)
        app.MapGet("/users/{id:int}/roles", async (int id, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var items = await conn.QueryAsync<RoleDto>(@"
                SELECT r.RoleId, r.RoleCode, r.RoleName, r.Description, r.IsActive,
                       r.MemberCount, r.AccessGrantCount, r.PackageGrantCount
                FROM App.vRoles AS r
                JOIN Sec.RoleMembership AS rm ON rm.RoleId = r.RoleId
                WHERE rm.MemberPrincipalId = @Id
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

        return app;
    }
}
