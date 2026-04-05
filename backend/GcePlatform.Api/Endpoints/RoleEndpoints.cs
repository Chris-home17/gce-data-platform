using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Models;

namespace GcePlatform.Api.Endpoints;

public static class RoleEndpoints
{
    public static WebApplication MapRoleEndpoints(this WebApplication app)
    {
        // GET /roles
        app.MapGet("/roles", async (DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var items = await conn.QueryAsync<RoleDto>(@"
                SELECT
                    RoleId,
                    RoleCode,
                    RoleName,
                    Description,
                    IsActive,
                    MemberCount,
                    AccessGrantCount,
                    PackageGrantCount
                FROM App.vRoles
                ORDER BY RoleCode");

            var list = items.ToList();
            return Results.Ok(new ApiList<RoleDto>(list, list.Count));
        }).RequireAuthorization();

        // POST /roles
        app.MapPost("/roles", async (CreateRoleRequest request, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();

            var p = new DynamicParameters();
            p.Add("@RoleCode", request.RoleCode.Trim().ToUpperInvariant());
            p.Add("@RoleName", request.RoleName.Trim());
            p.Add("@Description", request.Description);
            p.Add("@RoleId", dbType: System.Data.DbType.Int32,
                  direction: System.Data.ParameterDirection.Output);

            await conn.ExecuteAsync("App.UpsertRole", p,
                commandType: System.Data.CommandType.StoredProcedure);

            var newId = p.Get<int>("@RoleId");

            var created = await conn.QuerySingleAsync<RoleDto>(@"
                SELECT RoleId, RoleCode, RoleName, Description, IsActive,
                       MemberCount, AccessGrantCount, PackageGrantCount
                FROM App.vRoles
                WHERE RoleId = @Id",
                new { Id = newId });

            return Results.Created($"/roles/{newId}", created);
        }).RequireAuthorization();

        // GET /roles/{id}
        app.MapGet("/roles/{id:int}", async (int id, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var item = await conn.QuerySingleOrDefaultAsync<RoleDto>(@"
                SELECT
                    RoleId,
                    RoleCode,
                    RoleName,
                    Description,
                    IsActive,
                    MemberCount,
                    AccessGrantCount,
                    PackageGrantCount
                FROM App.vRoles
                WHERE RoleId = @Id",
                new { Id = id });

            return item is null
                ? Results.NotFound(new ApiError("ROLE_NOT_FOUND", $"Role {id} not found."))
                : Results.Ok(item);
        }).RequireAuthorization();

        // PATCH /roles/{id}/status
        app.MapMethods("/roles/{id:int}/status", new[] { "PATCH" },
            async (int id, SetActiveRequest req, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();

            var role = await conn.QuerySingleOrDefaultAsync<RoleDto>(@"
                SELECT RoleId, RoleCode, RoleName, Description, IsActive,
                       MemberCount, AccessGrantCount, PackageGrantCount
                FROM App.vRoles
                WHERE RoleId = @Id",
                new { Id = id });

            if (role is null)
                return Results.NotFound(new ApiError("ROLE_NOT_FOUND", $"Role {id} not found."));

            await conn.ExecuteAsync("App.usp_SetRoleActive",
                new { RoleId = id, req.IsActive },
                commandType: System.Data.CommandType.StoredProcedure);

            return Results.NoContent();
        }).RequireAuthorization();

        // GET /roles/{id}/members
        app.MapGet("/roles/{id:int}/members", async (int id, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var items = await conn.QueryAsync<RoleMemberDto>(@"
                SELECT RoleId, MemberPrincipalId, UPN, DisplayName, AddedOnUtc
                FROM App.vRoleMembers
                WHERE RoleId = @Id
                ORDER BY DisplayName",
                new { Id = id });

            var list = items.ToList();
            return Results.Ok(new ApiList<RoleMemberDto>(list, list.Count));
        }).RequireAuthorization();

        // POST /roles/{id}/members — add a user to this role
        app.MapPost("/roles/{id:int}/members", async (int id, AddRoleMemberRequest req, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();

            // Resolve the role code for the stored proc
            var roleCode = await conn.QuerySingleOrDefaultAsync<string>(
                "SELECT RoleCode FROM App.vRoles WHERE RoleId = @Id", new { Id = id });

            if (roleCode is null)
                return Results.NotFound(new ApiError("ROLE_NOT_FOUND", $"Role {id} not found."));

            var p = new DynamicParameters();
            p.Add("@RoleCode", roleCode);
            p.Add("@UserUPN",  req.UserUpn.Trim().ToLowerInvariant());

            await conn.ExecuteAsync("App.AddRoleMember", p,
                commandType: System.Data.CommandType.StoredProcedure);

            return Results.NoContent();
        }).RequireAuthorization();

        // DELETE /roles/{id}/members/{userId} — remove a user from this role
        app.MapDelete("/roles/{id:int}/members/{userId:int}", async (int id, int userId, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();

            var roleCode = await conn.QuerySingleOrDefaultAsync<string>(
                "SELECT RoleCode FROM App.vRoles WHERE RoleId = @Id", new { Id = id });

            if (roleCode is null)
                return Results.NotFound(new ApiError("ROLE_NOT_FOUND", $"Role {id} not found."));

            var upn = await conn.QuerySingleOrDefaultAsync<string>(
                "SELECT UPN FROM App.vUsers WHERE UserId = @UserId", new { UserId = userId });

            if (upn is null)
                return Results.NotFound(new ApiError("USER_NOT_FOUND", $"User {userId} not found."));

            var p = new DynamicParameters();
            p.Add("@RoleCode", roleCode);
            p.Add("@UserUPN",  upn);

            await conn.ExecuteAsync("App.RemoveRoleMember", p,
                commandType: System.Data.CommandType.StoredProcedure);

            return Results.NoContent();
        }).RequireAuthorization();

        // GET /roles/{id}/grants
        app.MapGet("/roles/{id:int}/grants", async (int id, DbConnectionFactory db) =>
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

        // GET /roles/{id}/package-grants
        app.MapGet("/roles/{id:int}/package-grants", async (int id, DbConnectionFactory db) =>
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
