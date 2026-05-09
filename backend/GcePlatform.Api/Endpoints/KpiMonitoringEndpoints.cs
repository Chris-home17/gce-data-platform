using System.Security.Claims;
using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Helpers;
using GcePlatform.Api.Models;
using GcePlatform.Api.Services;

namespace GcePlatform.Api.Endpoints;

public static class KpiMonitoringEndpoints
{
    public static WebApplication MapKpiMonitoringEndpoints(this WebApplication app)
    {
        // GET /kpi/monitoring?periodId=&accountId=&siteOrgUnitId=&groupName=&withScores=
        // ?withScores=true joins to App.vSiteCompositeScore and populates CompositeScore;
        // omitted/false leaves CompositeScore NULL (cheaper, behaves like Phase 1).
        app.MapGet("/kpi/monitoring", async (ClaimsPrincipal user, int? periodId, int? accountId, int? siteOrgUnitId, string? groupName, bool? withScores, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            // Composite score column gets joined in only when requested. The
            // sub-select dedupes the per-category fanout from vSiteCompositeScore.
            var compositeJoin = withScores == true ? @"
                LEFT JOIN (
                    SELECT DISTINCT AccountId, SiteOrgUnitId, PeriodID, CompositeScore
                    FROM App.vSiteCompositeScore
                ) AS sc
                  ON sc.AccountId = sct.AccountId
                 AND sc.SiteOrgUnitId = sct.SiteOrgUnitId
                 AND sc.PeriodID = sct.PeriodId" : "";

            var compositeColumn = withScores == true ? "sc.CompositeScore" : "CAST(NULL AS DECIMAL(9,4)) AS CompositeScore";

            var baseSelect = $@"
                SELECT
                    sct.AccountCode,
                    sct.AccountName,
                    sct.SiteCode,
                    sct.SiteName,
                    sct.SiteOrgUnitId,
                    sct.PeriodLabel,
                    sct.PeriodID        AS PeriodId,
                    sct.TotalRequired,
                    sct.TotalSubmitted,
                    sct.TotalLocked,
                    sct.TotalMissing,
                    sct.CompletionPct,
                    sct.ReminderLevel,
                    sct.ReminderResolved,
                    sct.GroupName,
                    {compositeColumn}
                FROM App.vSiteCompletionSummary AS sct
                {compositeJoin}
                WHERE (@PeriodId       IS NULL OR sct.PeriodId       = @PeriodId)
                  AND (@AccountId      IS NULL OR sct.AccountId      = @AccountId)
                  AND (@SiteOrgUnitId  IS NULL OR sct.SiteOrgUnitId  = @SiteOrgUnitId)
                  AND (@GroupName      IS NULL OR sct.GroupName       = @GroupName)";

            IEnumerable<SiteCompletionDto> items;
            if (await platformAuth.HasPermissionAsync(user, conn, Permissions.SuperAdmin))
            {
                items = await conn.QueryAsync<SiteCompletionDto>(
                    baseSelect + " ORDER BY sct.AccountCode, sct.SiteCode, sct.GroupName",
                    new { PeriodId = periodId, AccountId = accountId, SiteOrgUnitId = siteOrgUnitId, GroupName = groupName });
            }
            else
            {
                var currentUserId = await AccessScope.GetCurrentUserIdAsync(user, conn);
                if (currentUserId is null)
                    return Results.Ok(new ApiList<SiteCompletionDto>(new List<SiteCompletionDto>(), 0));

                var sql = AccessScope.AccessibleAccountsCte + baseSelect +
                          " AND sct.AccountId IN (SELECT AccountId FROM AccessibleAccounts) ORDER BY sct.AccountCode, sct.SiteCode, sct.GroupName";
                items = await conn.QueryAsync<SiteCompletionDto>(sql,
                    new { PeriodId = periodId, AccountId = accountId, SiteOrgUnitId = siteOrgUnitId, GroupName = groupName, UserId = currentUserId.Value });
            }

            var list = items.ToList();
            return Results.Ok(new ApiList<SiteCompletionDto>(list, list.Count));
        }).RequireAuthorization();

        return app;
    }
}
