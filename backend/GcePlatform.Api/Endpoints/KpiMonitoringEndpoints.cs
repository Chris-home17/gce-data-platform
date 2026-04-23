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
        // GET /kpi/monitoring?periodId=&accountId=&siteOrgUnitId=&groupName=
        app.MapGet("/kpi/monitoring", async (ClaimsPrincipal user, int? periodId, int? accountId, int? siteOrgUnitId, string? groupName, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            const string baseSelect = @"
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
                  AND (@GroupName      IS NULL OR GroupName       = @GroupName)";

            IEnumerable<SiteCompletionDto> items;
            if (await platformAuth.HasPermissionAsync(user, conn, Permissions.SuperAdmin))
            {
                items = await conn.QueryAsync<SiteCompletionDto>(
                    baseSelect + " ORDER BY AccountCode, SiteCode, GroupName",
                    new { PeriodId = periodId, AccountId = accountId, SiteOrgUnitId = siteOrgUnitId, GroupName = groupName });
            }
            else
            {
                var currentUserId = await AccessScope.GetCurrentUserIdAsync(user, conn);
                if (currentUserId is null)
                    return Results.Ok(new ApiList<SiteCompletionDto>(new List<SiteCompletionDto>(), 0));

                var sql = AccessScope.AccessibleAccountsCte + baseSelect +
                          " AND AccountId IN (SELECT AccountId FROM AccessibleAccounts) ORDER BY AccountCode, SiteCode, GroupName";
                items = await conn.QueryAsync<SiteCompletionDto>(sql,
                    new { PeriodId = periodId, AccountId = accountId, SiteOrgUnitId = siteOrgUnitId, GroupName = groupName, UserId = currentUserId.Value });
            }

            var list = items.ToList();
            return Results.Ok(new ApiList<SiteCompletionDto>(list, list.Count));
        }).RequireAuthorization();

        return app;
    }
}
