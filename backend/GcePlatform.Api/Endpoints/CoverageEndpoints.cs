using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Models;

namespace GcePlatform.Api.Endpoints;

public static class CoverageEndpoints
{
    public static WebApplication MapCoverageEndpoints(this WebApplication app)
    {
        // GET /coverage
        app.MapGet("/coverage", async (DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var items = await conn.QueryAsync<CoverageSummaryDto>(@"
                SELECT
                    UserId,
                    UPN        AS Upn,
                    PackageCount,
                    ReportCount,
                    SiteCount,
                    AccountCount,
                    GapStatus
                FROM App.vCoverageSummary
                ORDER BY GapStatus DESC, UPN");

            var list = items.ToList();
            return Results.Ok(new ApiList<CoverageSummaryDto>(list, list.Count));
        }).RequireAuthorization();

        return app;
    }
}
