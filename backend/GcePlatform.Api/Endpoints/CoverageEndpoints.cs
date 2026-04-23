using System.Security.Claims;
using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Helpers;
using GcePlatform.Api.Models;
using GcePlatform.Api.Services;

namespace GcePlatform.Api.Endpoints;

public static class CoverageEndpoints
{
    public static WebApplication MapCoverageEndpoints(this WebApplication app)
    {
        // GET /coverage — super-admins see everyone; others only see users
        // who overlap with an account the caller can access (or themselves).
        app.MapGet("/coverage", async (ClaimsPrincipal user, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            IEnumerable<CoverageSummaryDto> items;
            if (await platformAuth.HasPermissionAsync(user, conn, Permissions.SuperAdmin))
            {
                items = await conn.QueryAsync<CoverageSummaryDto>(@"
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
            }
            else
            {
                var currentUserId = await AccessScope.GetCurrentUserIdAsync(user, conn);
                if (currentUserId is null)
                    return Results.Ok(new ApiList<CoverageSummaryDto>(new List<CoverageSummaryDto>(), 0));

                items = await conn.QueryAsync<CoverageSummaryDto>($@"
                    {AccessScope.AccessibleAccountsCte}
                    SELECT
                        c.UserId,
                        c.UPN        AS Upn,
                        c.PackageCount,
                        c.ReportCount,
                        c.SiteCount,
                        c.AccountCount,
                        c.GapStatus
                    FROM App.vCoverageSummary AS c
                    WHERE c.UserId = @UserId
                       OR c.UserId IN
                       (
                           SELECT DISTINCT auth.UserPrincipalId
                           FROM Sec.vAuthorizedSitesDynamic AS auth
                           WHERE auth.AccountId IN (SELECT AccountId FROM AccessibleAccounts)
                       )
                    ORDER BY c.GapStatus DESC, c.UPN",
                    new { UserId = currentUserId.Value });
            }

            var list = items.ToList();
            return Results.Ok(new ApiList<CoverageSummaryDto>(list, list.Count));
        }).RequireAuthorization();

        return app;
    }
}
