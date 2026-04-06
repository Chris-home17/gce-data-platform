using System.Security.Claims;
using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Models;
using GcePlatform.Api.Services;
using Microsoft.Data.SqlClient;

namespace GcePlatform.Api.Endpoints;

public static class PlatformRoleEndpoints
{
    public static WebApplication MapPlatformRoleEndpoints(this WebApplication app)
    {
        // GET /auth/me — current user identity + platform permissions
        app.MapGet("/auth/me", async (ClaimsPrincipal user, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            var upn = PlatformAuthService.GetUpn(user) ?? "dev@gce-platform.local";

            // JIT provisioning: record login (creates user in DB if not yet present)
            var p = new DynamicParameters();
            p.Add("@EntraObjectId", user.FindFirstValue("oid") ?? "dev-user-001");
            p.Add("@UPN", upn);
            p.Add("@DisplayName", user.FindFirstValue(ClaimTypes.Name) ?? user.FindFirstValue("name") ?? upn);
            p.Add("@UserId", dbType: System.Data.DbType.Int32, direction: System.Data.ParameterDirection.Output);
            await conn.ExecuteAsync("App.RecordUserLogin", p, commandType: System.Data.CommandType.StoredProcedure);
            var userId = p.Get<int?>("@UserId") ?? 0;

            var permissions = await platformAuth.GetPermissionsAsync(user, conn);

            var displayName = await conn.ExecuteScalarAsync<string>(
                "SELECT COALESCE(DisplayName, UPN) FROM App.vUsers WHERE UserId = @Id",
                new { Id = userId }) ?? upn;

            return Results.Ok(new CurrentUserDto(userId, upn, displayName, permissions));
        }).RequireAuthorization();

        // GET /platform-permissions — full permission catalog (for role editing UI)
        app.MapGet("/platform-permissions", async (DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var items = await conn.QueryAsync<PlatformPermissionDto>(@"
                SELECT PermissionId, PermissionCode, DisplayName, Description, Category, SortOrder
                FROM App.vPlatformPermissions
                ORDER BY SortOrder, PermissionCode");
            var list = items.ToList();
            return Results.Ok(new ApiList<PlatformPermissionDto>(list, list.Count));
        }).RequireAuthorization();

        // GET /platform-roles
        app.MapGet("/platform-roles", async (DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var items = await conn.QueryAsync<PlatformRoleDto>(@"
                SELECT PlatformRoleId, RoleCode, RoleName, Description, IsActive,
                       MemberCount, PermissionCount
                FROM App.vPlatformRoles
                ORDER BY RoleName");
            var list = items.ToList();
            return Results.Ok(new ApiList<PlatformRoleDto>(list, list.Count));
        }).RequireAuthorization();

        // POST /platform-roles
        app.MapPost("/platform-roles", async (
            CreatePlatformRoleRequest request,
            ClaimsPrincipal user,
            DbConnectionFactory db,
            PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.PlatformRolesManage))
                return Results.Forbid();

            var p = new DynamicParameters();
            p.Add("@RoleCode", request.RoleCode.Trim().ToUpperInvariant());
            p.Add("@RoleName", request.RoleName);
            p.Add("@Description", request.Description);
            p.Add("@PlatformRoleId", dbType: System.Data.DbType.Int32, direction: System.Data.ParameterDirection.Output);

            await conn.ExecuteAsync("App.usp_UpsertPlatformRole", p,
                commandType: System.Data.CommandType.StoredProcedure);

            var newId = p.Get<int>("@PlatformRoleId");

            var created = await conn.QuerySingleAsync<PlatformRoleDto>(@"
                SELECT PlatformRoleId, RoleCode, RoleName, Description, IsActive,
                       MemberCount, PermissionCount
                FROM App.vPlatformRoles
                WHERE PlatformRoleId = @Id",
                new { Id = newId });

            return Results.Created($"/platform-roles/{newId}", created);
        }).RequireAuthorization();

        // GET /platform-roles/{id}
        app.MapGet("/platform-roles/{id:int}", async (int id, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();

            var role = await conn.QuerySingleOrDefaultAsync<PlatformRoleDto>(@"
                SELECT PlatformRoleId, RoleCode, RoleName, Description, IsActive,
                       MemberCount, PermissionCount
                FROM App.vPlatformRoles
                WHERE PlatformRoleId = @Id",
                new { Id = id });

            if (role is null) return Results.NotFound();

            var permissions = await conn.QueryAsync<PlatformPermissionDto>(@"
                SELECT PermissionId, PermissionCode, DisplayName, Description,
                       Category, SortOrder
                FROM App.vPlatformRolePermissions
                WHERE PlatformRoleId = @Id
                ORDER BY SortOrder, PermissionCode",
                new { Id = id });

            var members = await conn.QueryAsync<PlatformRoleMemberDto>(@"
                SELECT UserId, UPN, DisplayName, AssignedOnUtc
                FROM App.vPlatformRoleMembers
                WHERE PlatformRoleId = @Id
                ORDER BY DisplayName",
                new { Id = id });

            return Results.Ok(new PlatformRoleDetailDto(role, permissions, members));
        }).RequireAuthorization();

        // PATCH /platform-roles/{id}/status
        app.MapMethods("/platform-roles/{id:int}/status", new[] { "PATCH" }, async (
            int id,
            SetActiveRequest request,
            ClaimsPrincipal user,
            DbConnectionFactory db,
            PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.PlatformRolesManage))
                return Results.Forbid();

            var exists = await conn.ExecuteScalarAsync<bool>(
                "SELECT CAST(1 AS BIT) FROM App.vPlatformRoles WHERE PlatformRoleId = @Id",
                new { Id = id });

            if (!exists)
                return Results.NotFound();

            await conn.ExecuteAsync("App.usp_SetPlatformRoleActive",
                new { PlatformRoleId = id, request.IsActive },
                commandType: System.Data.CommandType.StoredProcedure);

            return Results.NoContent();
        }).RequireAuthorization();

        // PUT /platform-roles/{id}/permissions — replace full permission set
        app.MapPut("/platform-roles/{id:int}/permissions", async (
            int id,
            SetPlatformRolePermissionsRequest request,
            ClaimsPrincipal user,
            DbConnectionFactory db,
            PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.PlatformRolesManage))
                return Results.Forbid();

            if (!await conn.ExecuteScalarAsync<bool>(
                    "SELECT CAST(1 AS BIT) FROM App.vPlatformRoles WHERE PlatformRoleId = @Id", new { Id = id }))
                return Results.NotFound();

            await conn.ExecuteAsync("App.usp_SetPlatformRolePermissions",
                new
                {
                    PlatformRoleId = id,
                    PermissionCodesCsv = string.Join(",", request.PermissionCodes.Select(code => code.Trim())),
                },
                commandType: System.Data.CommandType.StoredProcedure);

            return Results.NoContent();
        }).RequireAuthorization();

        // GET /platform-roles/{id}/members
        app.MapGet("/platform-roles/{id:int}/members", async (int id, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var items = await conn.QueryAsync<PlatformRoleMemberDto>(@"
                SELECT UserId, UPN, DisplayName, AssignedOnUtc
                FROM App.vPlatformRoleMembers
                WHERE PlatformRoleId = @Id
                ORDER BY DisplayName",
                new { Id = id });
            var list = items.ToList();
            return Results.Ok(new ApiList<PlatformRoleMemberDto>(list, list.Count));
        }).RequireAuthorization();

        // POST /platform-roles/{id}/members
        app.MapPost("/platform-roles/{id:int}/members", async (
            int id,
            AddPlatformRoleMemberRequest request,
            ClaimsPrincipal user,
            DbConnectionFactory db,
            PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.PlatformRolesManage))
                return Results.Forbid();

            var actingUserId = await conn.ExecuteScalarAsync<int?>(
                "SELECT UserId FROM App.vUsers WHERE UPN = @Upn AND IsActive = 1",
                new { Upn = PlatformAuthService.GetUpn(user) });

            try
            {
                var p = new DynamicParameters();
                p.Add("@RoleCode", await conn.ExecuteScalarAsync<string>(
                    "SELECT RoleCode FROM App.vPlatformRoles WHERE PlatformRoleId = @Id", new { Id = id }));
                p.Add("@UserUPN", request.UserUpn.Trim().ToLowerInvariant());
                p.Add("@AssignedByUserId", actingUserId);
                await conn.ExecuteAsync("App.usp_AddPlatformRoleMember", p,
                    commandType: System.Data.CommandType.StoredProcedure);
            }
            catch (SqlException ex) when (ex.Number is 50201 or 50202 or 50203)
            {
                return Results.BadRequest(new ApiError("MEMBER_ERROR", ex.Message));
            }

            return Results.NoContent();
        }).RequireAuthorization();

        // DELETE /platform-roles/{id}/members/{userId}
        app.MapDelete("/platform-roles/{id:int}/members/{userId:int}", async (
            int id,
            int userId,
            ClaimsPrincipal user,
            DbConnectionFactory db,
            PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.PlatformRolesManage))
                return Results.Forbid();

            try
            {
                var p = new DynamicParameters();
                p.Add("@PlatformRoleId", id);
                p.Add("@UserId", userId);
                await conn.ExecuteAsync("App.usp_RemovePlatformRoleMember", p,
                    commandType: System.Data.CommandType.StoredProcedure);
            }
            catch (SqlException ex) when (ex.Number == 50204)
            {
                return Results.NotFound(new ApiError("NOT_MEMBER", ex.Message));
            }

            return Results.NoContent();
        }).RequireAuthorization();

        return app;
    }
}
