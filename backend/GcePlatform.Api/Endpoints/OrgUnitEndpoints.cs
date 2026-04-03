using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Models;

namespace GcePlatform.Api.Endpoints;

public static class OrgUnitEndpoints
{
    public static WebApplication MapOrgUnitEndpoints(this WebApplication app)
    {
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
            var item = await conn.QuerySingleOrDefaultAsync<OrgUnitDto>(
                "SELECT OrgUnitId, AccountId, AccountCode, AccountName, OrgUnitType, OrgUnitCode, OrgUnitName, ParentOrgUnitId, ParentOrgUnitName, ParentOrgUnitType, Path, CountryCode, CAST(IsActive AS bit) AS IsActive, ChildCount, SourceMappingCount FROM App.vOrgUnits WHERE OrgUnitId = @Id",
                new { Id = id });

            if (item is null)
                return Results.NotFound(new ApiError("ORG_UNIT_NOT_FOUND", $"Org unit {id} not found."));

            // Resolve parent info for the proc
            string? parentType = item.ParentOrgUnitId.HasValue ? item.ParentOrgUnitType : null;
            string? parentCode = null;
            if (item.ParentOrgUnitId.HasValue)
            {
                parentCode = await conn.QuerySingleOrDefaultAsync<string>(
                    "SELECT OrgUnitCode FROM Dim.OrgUnit WHERE OrgUnitId = @Id",
                    new { Id = item.ParentOrgUnitId.Value });
            }

            var p = new DynamicParameters();
            p.Add("@AccountCode",       item.AccountCode);
            p.Add("@OrgUnitType",       item.OrgUnitType);
            p.Add("@OrgUnitCode",       item.OrgUnitCode);
            p.Add("@OrgUnitName",       item.OrgUnitName);
            p.Add("@ParentOrgUnitType", parentType);
            p.Add("@ParentOrgUnitCode", parentCode);
            p.Add("@CountryCode",       item.CountryCode);
            p.Add("@IsActive",          req.IsActive ? 1 : 0);
            p.Add("@ApplyPolicies",     0);
            p.Add("@OrgUnitId",         dbType: System.Data.DbType.Int32,
                                        direction: System.Data.ParameterDirection.Output);

            await conn.ExecuteAsync("App.InsertOrgUnit", p,
                commandType: System.Data.CommandType.StoredProcedure);

            return Results.NoContent();
        }).RequireAuthorization();

        // POST /org-units
        app.MapPost("/org-units", async (CreateOrgUnitRequest req, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var p = new DynamicParameters();
            p.Add("@AccountCode",      req.AccountCode);
            p.Add("@OrgUnitType",      req.OrgUnitType);
            p.Add("@OrgUnitCode",      req.OrgUnitCode);
            p.Add("@OrgUnitName",      req.OrgUnitName);
            p.Add("@ParentOrgUnitType", req.ParentOrgUnitType);
            p.Add("@ParentOrgUnitCode", req.ParentOrgUnitCode);
            p.Add("@CountryCode",      req.CountryCode);
            p.Add("@IsActive",         1);
            p.Add("@ApplyPolicies",    1);
            p.Add("@OrgUnitId",        dbType: System.Data.DbType.Int32,
                                       direction: System.Data.ParameterDirection.Output);

            await conn.ExecuteAsync("App.InsertOrgUnit",
                p, commandType: System.Data.CommandType.StoredProcedure);

            var newId = p.Get<int>("@OrgUnitId");

            var item = await conn.QuerySingleOrDefaultAsync<OrgUnitDto>(@"
                SELECT
                    OrgUnitId, AccountId, AccountCode, AccountName, OrgUnitType, OrgUnitCode,
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
