using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Models;

namespace GcePlatform.Api.Endpoints;

public static class KpiMonitoringEndpoints
{
    public static WebApplication MapKpiMonitoringEndpoints(this WebApplication app)
    {
        // GET /kpi/monitoring?periodId=&accountId=
        app.MapGet("/kpi/monitoring", async (int? periodId, int? accountId, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var items = await conn.QueryAsync<SiteCompletionDto>(@"
                SELECT
                    AccountCode,
                    AccountName,
                    SiteCode,
                    SiteName,
                    PeriodLabel,
                    TotalRequired,
                    TotalSubmitted,
                    TotalLocked,
                    TotalMissing,
                    CompletionPct,
                    ReminderLevel,
                    ReminderResolved
                FROM App.vSiteCompletionSummary
                WHERE (@PeriodId IS NULL OR PeriodId = @PeriodId)
                  AND (@AccountId IS NULL OR AccountId = @AccountId)
                ORDER BY AccountCode, SiteCode",
                new { PeriodId = periodId, AccountId = accountId });

            var list = items.ToList();
            return Results.Ok(new ApiList<SiteCompletionDto>(list, list.Count));
        }).RequireAuthorization();

        return app;
    }
}
