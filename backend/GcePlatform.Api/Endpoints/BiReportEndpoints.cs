using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Models;

namespace GcePlatform.Api.Endpoints;

public static class BiReportEndpoints
{
    public static WebApplication MapBiReportEndpoints(this WebApplication app)
    {
        // GET /reports
        app.MapGet("/reports", async (DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var items = await conn.QueryAsync<BiReportDto>(@"
                SELECT
                    BiReportId,
                    ReportCode,
                    ReportName,
                    ReportUri,
                    CAST(IsActive AS bit) AS IsActive,
                    PackageCount,
                    ISNULL(PackageList, '') AS PackageList
                FROM App.vBiReports
                ORDER BY ReportCode");

            var list = items.ToList();
            return Results.Ok(new ApiList<BiReportDto>(list, list.Count));
        }).RequireAuthorization();

        // GET /reports/{id}
        app.MapGet("/reports/{id:int}", async (int id, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var item = await conn.QuerySingleOrDefaultAsync<BiReportDto>(@"
                SELECT
                    BiReportId,
                    ReportCode,
                    ReportName,
                    ReportUri,
                    CAST(IsActive AS bit) AS IsActive,
                    PackageCount,
                    ISNULL(PackageList, '') AS PackageList
                FROM App.vBiReports
                WHERE BiReportId = @Id",
                new { Id = id });

            return item is null
                ? Results.NotFound(new ApiError("REPORT_NOT_FOUND", $"Report {id} not found."))
                : Results.Ok(item);
        }).RequireAuthorization();

        // POST /reports
        app.MapPost("/reports", async (CreateBiReportRequest req, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var p = new DynamicParameters();
            p.Add("@ReportCode", req.ReportCode);
            p.Add("@ReportName", req.ReportName);
            p.Add("@ReportUri",  req.ReportUri);
            p.Add("@IsActive",   1);
            p.Add("@BiReportId", dbType: System.Data.DbType.Int32,
                                 direction: System.Data.ParameterDirection.Output);

            await conn.ExecuteAsync("App.UpsertBiReport",
                p, commandType: System.Data.CommandType.StoredProcedure);

            var newId = p.Get<int>("@BiReportId");

            var item = await conn.QuerySingleOrDefaultAsync<BiReportDto>(@"
                SELECT BiReportId, ReportCode, ReportName, ReportUri,
                       CAST(IsActive AS bit) AS IsActive,
                       PackageCount, ISNULL(PackageList, '') AS PackageList
                FROM App.vBiReports WHERE BiReportId = @Id",
                new { Id = newId });

            return Results.Created($"/reports/{newId}", item);
        }).RequireAuthorization();

        // PUT /reports/{id} — update name and URI
        app.MapPut("/reports/{id:int}", async (int id, UpdateBiReportRequest req, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var existing = await conn.QuerySingleOrDefaultAsync<BiReportDto>(
                "SELECT BiReportId, ReportCode, ReportName, ReportUri, CAST(IsActive AS bit) AS IsActive, PackageCount, ISNULL(PackageList,'') AS PackageList FROM App.vBiReports WHERE BiReportId = @Id",
                new { Id = id });

            if (existing is null)
                return Results.NotFound(new ApiError("REPORT_NOT_FOUND", $"Report {id} not found."));

            var p = new DynamicParameters();
            p.Add("@ReportCode", existing.ReportCode);
            p.Add("@ReportName", req.ReportName);
            p.Add("@ReportUri",  req.ReportUri);
            p.Add("@IsActive",   existing.IsActive ? 1 : 0);
            p.Add("@BiReportId", dbType: System.Data.DbType.Int32,
                                 direction: System.Data.ParameterDirection.Output);

            await conn.ExecuteAsync("App.UpsertBiReport", p,
                commandType: System.Data.CommandType.StoredProcedure);

            var updated = await conn.QuerySingleOrDefaultAsync<BiReportDto>(
                "SELECT BiReportId, ReportCode, ReportName, ReportUri, CAST(IsActive AS bit) AS IsActive, PackageCount, ISNULL(PackageList,'') AS PackageList FROM App.vBiReports WHERE BiReportId = @Id",
                new { Id = id });

            return Results.Ok(updated);
        }).RequireAuthorization();

        // POST /reports/assign  — add or remove a report↔package link
        app.MapPost("/reports/assign", async (AssignReportToPackageRequest req, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var p = new DynamicParameters();
            p.Add("@ReportCode",  req.ReportCode);
            p.Add("@PackageCode", req.PackageCode);
            p.Add("@Remove",      req.Remove ? 1 : 0);

            await conn.ExecuteAsync("App.AssignReportToPackage",
                p, commandType: System.Data.CommandType.StoredProcedure);

            return Results.NoContent();
        }).RequireAuthorization();

        // PATCH /reports/{id}/status
        app.MapMethods("/reports/{id:int}/status", new[] { "PATCH" },
            async (int id, SetActiveRequest req, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var item = await conn.QuerySingleOrDefaultAsync<BiReportDto>(
                "SELECT BiReportId, ReportCode, ReportName, ReportUri, CAST(IsActive AS bit) AS IsActive, PackageCount, ISNULL(PackageList,'') AS PackageList FROM App.vBiReports WHERE BiReportId = @Id",
                new { Id = id });

            if (item is null)
                return Results.NotFound(new ApiError("REPORT_NOT_FOUND", $"Report {id} not found."));

            var p = new DynamicParameters();
            p.Add("@ReportCode", item.ReportCode);
            p.Add("@ReportName", item.ReportName);
            p.Add("@ReportUri",  item.ReportUri);
            p.Add("@IsActive",   req.IsActive ? 1 : 0);
            p.Add("@BiReportId", dbType: System.Data.DbType.Int32,
                                 direction: System.Data.ParameterDirection.Output);

            await conn.ExecuteAsync("App.UpsertBiReport", p,
                commandType: System.Data.CommandType.StoredProcedure);

            return Results.NoContent();
        }).RequireAuthorization();

        return app;
    }
}
