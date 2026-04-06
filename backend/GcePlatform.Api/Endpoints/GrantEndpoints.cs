using System.Security.Claims;
using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Models;
using GcePlatform.Api.Services;

namespace GcePlatform.Api.Endpoints;

public static class GrantEndpoints
{
    public static WebApplication MapGrantEndpoints(this WebApplication app)
    {
        // POST /grants — App.GrantAccess wrapper
        app.MapPost("/grants", async (ClaimsPrincipal user, GrantAccessRequest req, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.GrantsManage))
                return Results.Forbid();
            var p = new DynamicParameters();
            p.Add("@PrincipalType",       req.PrincipalType);
            p.Add("@PrincipalIdentifier", req.PrincipalIdentifier);
            p.Add("@GrantType",           req.GrantType);
            p.Add("@PackageCode",         req.PackageCode);
            p.Add("@AccountCode",         req.AccountCode);
            p.Add("@OrgUnitType",         req.OrgUnitType);
            p.Add("@OrgUnitCode",         req.OrgUnitCode);
            p.Add("@CountryCode",         req.CountryCode);

            await conn.ExecuteAsync("App.GrantAccess", p,
                commandType: System.Data.CommandType.StoredProcedure);

            return Results.NoContent();
        }).RequireAuthorization();

        // DELETE /grants/{id} — App.RevokeAccess
        app.MapDelete("/grants/{id:int}", async (ClaimsPrincipal user, int id, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.GrantsManage))
                return Results.Forbid();
            var p = new DynamicParameters();
            p.Add("@PrincipalAccessGrantId", id);

            try
            {
                await conn.ExecuteAsync("App.RevokeAccess", p,
                    commandType: System.Data.CommandType.StoredProcedure);
            }
            catch (Microsoft.Data.SqlClient.SqlException ex) when (ex.Number == 50061)
            {
                return Results.NotFound(new ApiError("GRANT_NOT_FOUND", ex.Message));
            }
            catch (Microsoft.Data.SqlClient.SqlException ex) when (ex.Number == 50063)
            {
                return Results.Conflict(new ApiError("GRANT_ALREADY_REVOKED", ex.Message));
            }

            return Results.NoContent();
        }).RequireAuthorization();

        // DELETE /package-grants/{id} — App.RevokePackageGrant
        app.MapDelete("/package-grants/{id:int}", async (ClaimsPrincipal user, int id, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.GrantsManage))
                return Results.Forbid();
            var p = new DynamicParameters();
            p.Add("@PrincipalPackageGrantId", id);

            try
            {
                await conn.ExecuteAsync("App.RevokePackageGrant", p,
                    commandType: System.Data.CommandType.StoredProcedure);
            }
            catch (Microsoft.Data.SqlClient.SqlException ex) when (ex.Number == 50062)
            {
                return Results.NotFound(new ApiError("GRANT_NOT_FOUND", ex.Message));
            }
            catch (Microsoft.Data.SqlClient.SqlException ex) when (ex.Number == 50064)
            {
                return Results.Conflict(new ApiError("GRANT_ALREADY_REVOKED", ex.Message));
            }

            return Results.NoContent();
        }).RequireAuthorization();

        return app;
    }
}
