using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Models;

namespace GcePlatform.Api.Endpoints;

public static class KpiMonitoringEndpoints
{
    public static WebApplication MapKpiMonitoringEndpoints(this WebApplication app)
    {
        // GET /kpi/monitoring?periodId=&accountId=&siteOrgUnitId=&groupName=
        app.MapGet("/kpi/monitoring", async (int? periodId, int? accountId, int? siteOrgUnitId, string? groupName, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var items = await conn.QueryAsync<SiteCompletionDto>(@"
                SELECT
                    AccountCode,
                    AccountName,
                    SiteCode,
                    SiteName,
                    SiteOrgUnitId,
                    PeriodLabel,
                    PeriodID        AS PeriodId,
                    TotalRequired,
                    TotalSubmitted,
                    TotalLocked,
                    TotalMissing,
                    CompletionPct,
                    ReminderLevel,
                    ReminderResolved,
                    GroupName
                FROM App.vSiteCompletionSummary
                WHERE (@PeriodId       IS NULL OR PeriodId       = @PeriodId)
                  AND (@AccountId      IS NULL OR AccountId      = @AccountId)
                  AND (@SiteOrgUnitId  IS NULL OR SiteOrgUnitId  = @SiteOrgUnitId)
                  AND (@GroupName      IS NULL OR GroupName       = @GroupName)
                ORDER BY AccountCode, SiteCode, GroupName",
                new { PeriodId = periodId, AccountId = accountId, SiteOrgUnitId = siteOrgUnitId, GroupName = groupName });

            var list = items.ToList();
            return Results.Ok(new ApiList<SiteCompletionDto>(list, list.Count));
        }).RequireAuthorization();

        return app;
    }
}
