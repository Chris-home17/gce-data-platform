using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Models;

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
            async (int id, SetActiveRequest req, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var exists = await conn.QuerySingleOrDefaultAsync<int?>(
                "SELECT OrgUnitId FROM Dim.OrgUnit WHERE OrgUnitId = @Id",
                new { Id = id });

            if (!exists.HasValue)
                return Results.NotFound(new ApiError("ORG_UNIT_NOT_FOUND", $"Org unit {id} not found."));

            await conn.ExecuteAsync(@"
                UPDATE Dim.OrgUnit
                SET IsActive = @IsActive,
                    ModifiedOnUtc = SYSUTCDATETIME(),
                    ModifiedBy = SESSION_USER
                WHERE OrgUnitId = @Id",
                new { Id = id, IsActive = req.IsActive });

            return Results.NoContent();
        }).RequireAuthorization();

        // POST /org-units
        app.MapPost("/org-units", async (CreateOrgUnitRequest req, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
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

        return app;
    }
}
