using System.Security.Claims;
using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Models;
using GcePlatform.Api.Services;

namespace GcePlatform.Api.Endpoints;

public static class OrgUnitEndpoints
{
    public static WebApplication MapOrgUnitEndpoints(this WebApplication app)
    {
        app.MapGet("/shared-geo-units", async (string? geoUnitType, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var items = await conn.QueryAsync<SharedGeoUnitDto>(@"
                SELECT
                    SharedGeoUnitId,
                    GeoUnitType,
                    GeoUnitCode,
                    GeoUnitName,
                    CountryCode,
                    CAST(IsActive AS bit) AS IsActive
                FROM App.vSharedGeoUnits
                WHERE (@GeoUnitType IS NULL OR GeoUnitType = @GeoUnitType)
                ORDER BY GeoUnitType, GeoUnitName, GeoUnitCode",
                new { GeoUnitType = geoUnitType });

            var list = items.ToList();
            return Results.Ok(new ApiList<SharedGeoUnitDto>(list, list.Count));
        }).RequireAuthorization();

        app.MapPost("/shared-geo-units", async (CreateSharedGeoUnitRequest req, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var p = new DynamicParameters();
            p.Add("@GeoUnitType", req.GeoUnitType);
            p.Add("@GeoUnitCode", req.GeoUnitCode);
            p.Add("@GeoUnitName", req.GeoUnitName);
            p.Add("@CountryCode", req.CountryCode);
            p.Add("@IsActive", 1);
            p.Add("@ExistingSharedGeoUnitId", null);
            p.Add("@SharedGeoUnitId", dbType: System.Data.DbType.Int32,
                direction: System.Data.ParameterDirection.Output);

            await conn.ExecuteAsync("App.UpsertSharedGeoUnit", p,
                commandType: System.Data.CommandType.StoredProcedure);

            var id = p.Get<int>("@SharedGeoUnitId");
            var item = await conn.QuerySingleOrDefaultAsync<SharedGeoUnitDto>(@"
                SELECT
                    SharedGeoUnitId,
                    GeoUnitType,
                    GeoUnitCode,
                    GeoUnitName,
                    CountryCode,
                    CAST(IsActive AS bit) AS IsActive
                FROM App.vSharedGeoUnits
                WHERE SharedGeoUnitId = @Id",
                new { Id = id });

            return Results.Created($"/shared-geo-units/{id}", item);
        }).RequireAuthorization();

        app.MapPut("/shared-geo-units/{id:int}", async (int id, UpdateSharedGeoUnitRequest req, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();

            var exists = await conn.QuerySingleOrDefaultAsync<int?>(
                "SELECT SharedGeoUnitId FROM App.vSharedGeoUnits WHERE SharedGeoUnitId = @Id",
                new { Id = id });

            if (!exists.HasValue)
                return Results.NotFound(new ApiError("SHARED_GEO_NOT_FOUND", $"Shared geography item {id} not found."));

            var p = new DynamicParameters();
            p.Add("@GeoUnitType", req.GeoUnitType);
            p.Add("@GeoUnitCode", req.GeoUnitCode);
            p.Add("@GeoUnitName", req.GeoUnitName);
            p.Add("@CountryCode", req.CountryCode);
            p.Add("@IsActive", 1);
            p.Add("@ExistingSharedGeoUnitId", id);
            p.Add("@SharedGeoUnitId", dbType: System.Data.DbType.Int32,
                direction: System.Data.ParameterDirection.Output);

            await conn.ExecuteAsync("App.UpsertSharedGeoUnit", p,
                commandType: System.Data.CommandType.StoredProcedure);

            var updatedId = p.Get<int>("@SharedGeoUnitId");
            var item = await conn.QuerySingleOrDefaultAsync<SharedGeoUnitDto>(@"
                SELECT
                    SharedGeoUnitId,
                    GeoUnitType,
                    GeoUnitCode,
                    GeoUnitName,
                    CountryCode,
                    CAST(IsActive AS bit) AS IsActive
                FROM App.vSharedGeoUnits
                WHERE SharedGeoUnitId = @Id",
                new { Id = updatedId });

            return Results.Ok(item);
        }).RequireAuthorization();

        app.MapPost("/shared-geo-units/bulk", async (BulkCreateSharedGeoUnitsRequest req, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var results = new List<BulkSharedGeoUnitResult>();

            for (int i = 0; i < req.Rows.Count; i++)
            {
                var row = req.Rows[i];
                try
                {
                    var p = new DynamicParameters();
                    p.Add("@GeoUnitType", row.GeoUnitType);
                    p.Add("@GeoUnitCode", row.GeoUnitCode);
                    p.Add("@GeoUnitName", row.GeoUnitName);
                    p.Add("@CountryCode", row.CountryCode);
                    p.Add("@IsActive", 1);
                    p.Add("@ExistingSharedGeoUnitId", null);
                    p.Add("@SharedGeoUnitId", dbType: System.Data.DbType.Int32,
                        direction: System.Data.ParameterDirection.Output);

                    await conn.ExecuteAsync("App.UpsertSharedGeoUnit", p,
                        commandType: System.Data.CommandType.StoredProcedure);

                    results.Add(new BulkSharedGeoUnitResult(i, true, p.Get<int>("@SharedGeoUnitId"), null));
                }
                catch (Microsoft.Data.SqlClient.SqlException ex)
                {
                    results.Add(new BulkSharedGeoUnitResult(i, false, null, ex.Message));
                }
                catch (Exception ex)
                {
                    results.Add(new BulkSharedGeoUnitResult(i, false, null, ex.Message));
                }
            }

            return Results.Ok(new BulkCreateSharedGeoUnitsResponse(results));
        }).RequireAuthorization();

        // GET /org-units?accountId=
        app.MapGet("/org-units", async (int? accountId, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var items = await conn.QueryAsync<OrgUnitDto>(@"
                SELECT
                    OrgUnitId,
                    AccountId,
                    AccountCode,
                    AccountName,
                    SharedGeoUnitId,
                    SharedGeoUnitCode,
                    SharedGeoUnitName,
                    CountryOrgUnitId,
                    CountryOrgUnitCode,
                    CountryOrgUnitName,
                    OrgUnitType,
                    OrgUnitCode,
                    OrgUnitName,
                    ParentOrgUnitId,
                    ParentOrgUnitName,
                    ParentOrgUnitType,
                    Path,
                    CountryCode,
                    CAST(IsActive AS bit) AS IsActive,
                    ChildCount,
                    SourceMappingCount
                FROM App.vOrgUnits
                WHERE (@AccountId IS NULL OR AccountId = @AccountId)
                ORDER BY Path",
                new { AccountId = accountId });

            var list = items.ToList();
            return Results.Ok(new ApiList<OrgUnitDto>(list, list.Count));
        }).RequireAuthorization();

        // GET /org-units/{id}
        app.MapGet("/org-units/{id:int}", async (int id, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var item = await conn.QuerySingleOrDefaultAsync<OrgUnitDto>(@"
                SELECT
                    OrgUnitId,
                    AccountId,
                    AccountCode,
                    AccountName,
                    SharedGeoUnitId,
                    SharedGeoUnitCode,
                    SharedGeoUnitName,
                    CountryOrgUnitId,
                    CountryOrgUnitCode,
                    CountryOrgUnitName,
                    OrgUnitType,
                    OrgUnitCode,
                    OrgUnitName,
                    ParentOrgUnitId,
                    ParentOrgUnitName,
                    ParentOrgUnitType,
                    Path,
                    CountryCode,
                    CAST(IsActive AS bit) AS IsActive,
                    ChildCount,
                    SourceMappingCount
                FROM App.vOrgUnits
                WHERE OrgUnitId = @Id",
                new { Id = id });

            return item is null
                ? Results.NotFound(new ApiError("ORG_UNIT_NOT_FOUND", $"Org unit {id} not found."))
                : Results.Ok(item);
        }).RequireAuthorization();

        // PATCH /org-units/{id}/status
        app.MapMethods("/org-units/{id:int}/status", new[] { "PATCH" },
            async (int id, SetActiveRequest req, ClaimsPrincipal user, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();
            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.AccountsManage))
                return Results.Forbid();

            var exists = await conn.QuerySingleOrDefaultAsync<int?>(
                "SELECT OrgUnitId FROM App.vOrgUnits WHERE OrgUnitId = @Id",
                new { Id = id });

            if (!exists.HasValue)
                return Results.NotFound(new ApiError("ORG_UNIT_NOT_FOUND", $"Org unit {id} not found."));

            await conn.ExecuteAsync("App.usp_SetOrgUnitActive",
                new { OrgUnitId = id, req.IsActive },
                commandType: System.Data.CommandType.StoredProcedure);

            return Results.NoContent();
        }).RequireAuthorization();

        // POST /org-units
        app.MapPost("/org-units", async (CreateOrgUnitRequest req, ClaimsPrincipal user, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();
            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.AccountsManage))
                return Results.Forbid();

            var p = new DynamicParameters();
            if (req.OrgUnitType is "Region" or "SubRegion" or "Cluster" or "Country")
            {
                if (!req.SharedGeoUnitId.HasValue)
                    return Results.BadRequest(new ApiError("SHARED_GEO_REQUIRED", "A shared geography selection is required for Region, SubRegion, Cluster, and Country."));

                p.Add("@AccountCode", req.AccountCode);
                p.Add("@SharedGeoUnitId", req.SharedGeoUnitId.Value);
                p.Add("@ParentOrgUnitType", req.ParentOrgUnitType);
                p.Add("@ParentOrgUnitCode", req.ParentOrgUnitCode);
                p.Add("@ApplyPolicies", 1);
                p.Add("@OrgUnitId", dbType: System.Data.DbType.Int32,
                    direction: System.Data.ParameterDirection.Output);

                await conn.ExecuteAsync("App.AttachSharedGeoUnitToAccount",
                    p, commandType: System.Data.CommandType.StoredProcedure);
            }
            else
            {
                p.Add("@AccountCode", req.AccountCode);
                p.Add("@OrgUnitType", req.OrgUnitType);
                p.Add("@OrgUnitCode", req.OrgUnitCode);
                p.Add("@OrgUnitName", req.OrgUnitName);
                p.Add("@ParentOrgUnitType", req.ParentOrgUnitType);
                p.Add("@ParentOrgUnitCode", req.ParentOrgUnitCode);
                p.Add("@CountrySharedGeoUnitId", req.CountrySharedGeoUnitId);
                p.Add("@IsActive", 1);
                p.Add("@ApplyPolicies", 1);
                p.Add("@OrgUnitId", dbType: System.Data.DbType.Int32,
                    direction: System.Data.ParameterDirection.Output);

                await conn.ExecuteAsync("App.InsertOrgUnit",
                    p, commandType: System.Data.CommandType.StoredProcedure);
            }

            var newId = p.Get<int>("@OrgUnitId");

            var item = await conn.QuerySingleOrDefaultAsync<OrgUnitDto>(@"
                SELECT
                    OrgUnitId, AccountId, AccountCode, AccountName, SharedGeoUnitId, SharedGeoUnitCode, SharedGeoUnitName,
                    CountryOrgUnitId, CountryOrgUnitCode, CountryOrgUnitName, OrgUnitType, OrgUnitCode,
                    OrgUnitName, ParentOrgUnitId, ParentOrgUnitName, ParentOrgUnitType,
                    Path, CountryCode, CAST(IsActive AS bit) AS IsActive, ChildCount, SourceMappingCount
                FROM App.vOrgUnits
                WHERE OrgUnitId = @Id",
                new { Id = newId });

            return Results.Created($"/org-units/{newId}", item);
        }).RequireAuthorization();

        // POST /org-units/bulk
        app.MapPost("/org-units/bulk", async (BulkCreateOrgUnitsRequest req, ClaimsPrincipal user, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();
            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.AccountsManage))
                return Results.Forbid();

            // Verify account exists upfront
            var accountId = await conn.QuerySingleOrDefaultAsync<int?>(
                "SELECT AccountId FROM App.vAccounts WHERE AccountCode = @AccountCode",
                new { req.AccountCode });

            if (!accountId.HasValue)
                return Results.BadRequest(new ApiError("ACCOUNT_NOT_FOUND", $"Account '{req.AccountCode}' not found."));

            var results = new List<BulkOrgUnitResult>();

            for (int i = 0; i < req.Rows.Count; i++)
            {
                var row = req.Rows[i];
                try
                {
                    var p = new DynamicParameters();
                    p.Add("@AccountCode", req.AccountCode);
                    p.Add("@ParentOrgUnitType", row.ParentOrgUnitType);
                    p.Add("@ParentOrgUnitCode", row.ParentOrgUnitCode);
                    p.Add("@ApplyPolicies", 1);
                    p.Add("@OrgUnitId", dbType: System.Data.DbType.Int32,
                        direction: System.Data.ParameterDirection.Output);

                    if (row.OrgUnitType is "Region" or "SubRegion" or "Cluster" or "Country")
                    {
                        var sharedGeoUnitId = await conn.QuerySingleOrDefaultAsync<int?>(@"
                            SELECT SharedGeoUnitId
                            FROM App.vSharedGeoUnits
                            WHERE GeoUnitType = @GeoUnitType
                              AND GeoUnitCode = @GeoUnitCode",
                            new
                            {
                                GeoUnitType = row.OrgUnitType,
                                GeoUnitCode = row.OrgUnitCode,
                            });

                        if (!sharedGeoUnitId.HasValue)
                            throw new InvalidOperationException(
                                $"Shared Geography '{row.OrgUnitCode}' ({row.OrgUnitType}) does not exist."
                            );

                        p.Add("@SharedGeoUnitId", sharedGeoUnitId.Value);

                        await conn.ExecuteAsync("App.AttachSharedGeoUnitToAccount", p,
                            commandType: System.Data.CommandType.StoredProcedure);
                    }
                    else
                    {
                        p.Add("@OrgUnitType", row.OrgUnitType);
                        p.Add("@OrgUnitCode", row.OrgUnitCode);
                        p.Add("@OrgUnitName", row.OrgUnitName);
                        p.Add("@CountrySharedGeoUnitId", null);
                        p.Add("@IsActive", 1);

                        await conn.ExecuteAsync("App.InsertOrgUnit", p,
                            commandType: System.Data.CommandType.StoredProcedure);
                    }

                    results.Add(new BulkOrgUnitResult(i, true, p.Get<int>("@OrgUnitId"), null));
                }
                catch (Microsoft.Data.SqlClient.SqlException ex)
                {
                    results.Add(new BulkOrgUnitResult(i, false, null, ex.Message));
                }
                catch (Exception ex)
                {
                    results.Add(new BulkOrgUnitResult(i, false, null, ex.Message));
                }
            }

            return Results.Ok(new BulkCreateOrgUnitsResponse(results));
        }).RequireAuthorization();

        app.MapPost("/org-units/{id:int}/move", async (int id, MoveOrgUnitRequest req, ClaimsPrincipal user, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();
            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.AccountsManage))
                return Results.Forbid();

            var existing = await conn.QuerySingleOrDefaultAsync<OrgUnitDto>(@"
                SELECT
                    OrgUnitId, AccountId, AccountCode, AccountName, SharedGeoUnitId, SharedGeoUnitCode, SharedGeoUnitName,
                    CountryOrgUnitId, CountryOrgUnitCode, CountryOrgUnitName, OrgUnitType, OrgUnitCode,
                    OrgUnitName, ParentOrgUnitId, ParentOrgUnitName, ParentOrgUnitType,
                    Path, CountryCode, CAST(IsActive AS bit) AS IsActive, ChildCount, SourceMappingCount
                FROM App.vOrgUnits
                WHERE OrgUnitId = @Id",
                new { Id = id });

            if (existing is null)
                return Results.NotFound(new ApiError("ORG_UNIT_NOT_FOUND", $"Org unit {id} not found."));

            try
            {
                await conn.ExecuteAsync("App.MoveOrgUnit",
                    new
                    {
                        OrgUnitId = id,
                        NewParentOrgUnitId = req.ParentOrgUnitId,
                        ApplyPolicies = false,
                        ActorUPN = (string?)null,
                    },
                    commandType: System.Data.CommandType.StoredProcedure);
            }
            catch (Microsoft.Data.SqlClient.SqlException ex) when (ex.Number is 50231)
            {
                return Results.NotFound(new ApiError("PARENT_NOT_FOUND", ex.Message));
            }
            catch (Microsoft.Data.SqlClient.SqlException ex) when (ex.Number is 50232 or 50233 or 50234 or 50235 or 50236)
            {
                return Results.BadRequest(new ApiError("INVALID_MOVE", ex.Message));
            }

            var updated = await conn.QuerySingleAsync<OrgUnitDto>(@"
                SELECT
                    OrgUnitId, AccountId, AccountCode, AccountName, SharedGeoUnitId, SharedGeoUnitCode, SharedGeoUnitName,
                    CountryOrgUnitId, CountryOrgUnitCode, CountryOrgUnitName, OrgUnitType, OrgUnitCode,
                    OrgUnitName, ParentOrgUnitId, ParentOrgUnitName, ParentOrgUnitType,
                    Path, CountryCode, CAST(IsActive AS bit) AS IsActive, ChildCount, SourceMappingCount
                FROM App.vOrgUnits
                WHERE OrgUnitId = @Id",
                new { Id = id });

            return Results.Ok(updated);
        }).RequireAuthorization();

        return app;
    }
}
