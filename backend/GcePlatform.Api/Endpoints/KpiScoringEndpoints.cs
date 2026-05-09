using System.Security.Claims;
using System.Text.Json;
using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Helpers;
using GcePlatform.Api.Models;
using GcePlatform.Api.Services;

namespace GcePlatform.Api.Endpoints;

/// <summary>
/// KPI scoring layer endpoints. Phase 1 ships per-account category weights;
/// Phase 2 will add composite-score read endpoints once the score views land.
/// </summary>
public static class KpiScoringEndpoints
{
    public static WebApplication MapKpiScoringEndpoints(this WebApplication app)
    {
        // GET /kpi/category-weights?accountCode=ACME
        // Returns the configured category weights for a single account.
        // Categories with no row default to weight 1.0 at compute time on the
        // Monitoring page (Phase 2), so an empty list is a valid steady state.
        app.MapGet("/kpi/category-weights", async (ClaimsPrincipal user, string accountCode, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.KpiAdmin))
                return Results.Forbid();

            // Tenant scoping: super-admins see anything; others see only their accessible accounts.
            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.SuperAdmin))
            {
                var currentUserId = await AccessScope.GetCurrentUserIdAsync(user, conn);
                if (currentUserId is null)
                    return Results.NotFound(new ApiError("ACCOUNT_NOT_FOUND", "Account not accessible."));

                var accessible = await conn.QuerySingleOrDefaultAsync<int?>($@"
                    {AccessScope.AccessibleAccountsCte}
                    SELECT a.AccountId
                    FROM Dim.Account AS a
                    WHERE a.AccountCode = @AccountCode
                      AND a.AccountId IN (SELECT AccountId FROM AccessibleAccounts)",
                    new { AccountCode = accountCode, UserId = currentUserId.Value });

                if (accessible is null)
                    return Results.NotFound(new ApiError("ACCOUNT_NOT_FOUND", $"Account '{accountCode}' not accessible."));
            }

            var rows = await conn.QueryAsync<CategoryWeightDto>(@"
                SELECT cw.Category, cw.Weight, CAST(cw.IsActive AS bit) AS IsActive
                FROM KPI.CategoryWeight AS cw
                JOIN Dim.Account        AS a ON a.AccountId = cw.AccountId
                WHERE a.AccountCode = @AccountCode
                ORDER BY cw.Category",
                new { AccountCode = accountCode });

            var list = rows.ToList();
            return Results.Ok(new ApiList<CategoryWeightDto>(list, list.Count));
        }).RequireAuthorization();

        // GET /kpi/site-scores?periodId=&accountId=&siteOrgUnitId=
        // Returns the per-category score breakdown + site composite from
        // App.vSiteCompositeScore. Same row count as Composite × Category, so
        // the frontend can render both the breakdown panel and the site composite.
        app.MapGet("/kpi/site-scores", async (ClaimsPrincipal user, int? periodId, int? accountId, int? siteOrgUnitId, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            const string columns = @"
                AccountId,
                SiteOrgUnitId,
                PeriodID         AS PeriodId,
                Category,
                CategoryScore,
                CategoryWeight,
                CategoryActive,
                ScoredCount,
                TotalCount,
                CompositeScore";

            IEnumerable<SiteCategoryScoreDto> items;
            if (await platformAuth.HasPermissionAsync(user, conn, Permissions.SuperAdmin))
            {
                items = await conn.QueryAsync<SiteCategoryScoreDto>($@"
                    SELECT {columns}
                    FROM App.vSiteCompositeScore
                    WHERE (@PeriodId      IS NULL OR PeriodID      = @PeriodId)
                      AND (@AccountId     IS NULL OR AccountId     = @AccountId)
                      AND (@SiteOrgUnitId IS NULL OR SiteOrgUnitId = @SiteOrgUnitId)
                    ORDER BY AccountId, SiteOrgUnitId, Category",
                    new { PeriodId = periodId, AccountId = accountId, SiteOrgUnitId = siteOrgUnitId });
            }
            else
            {
                var currentUserId = await AccessScope.GetCurrentUserIdAsync(user, conn);
                if (currentUserId is null)
                    return Results.Ok(new ApiList<SiteCategoryScoreDto>(new List<SiteCategoryScoreDto>(), 0));

                items = await conn.QueryAsync<SiteCategoryScoreDto>($@"
                    {AccessScope.AccessibleAccountsCte}
                    SELECT {columns}
                    FROM App.vSiteCompositeScore
                    WHERE (@PeriodId      IS NULL OR PeriodID      = @PeriodId)
                      AND (@AccountId     IS NULL OR AccountId     = @AccountId)
                      AND (@SiteOrgUnitId IS NULL OR SiteOrgUnitId = @SiteOrgUnitId)
                      AND AccountId IN (SELECT AccountId FROM AccessibleAccounts)
                    ORDER BY AccountId, SiteOrgUnitId, Category",
                    new { PeriodId = periodId, AccountId = accountId, SiteOrgUnitId = siteOrgUnitId, UserId = currentUserId.Value });
            }

            var list = items.ToList();
            return Results.Ok(new ApiList<SiteCategoryScoreDto>(list, list.Count));
        }).RequireAuthorization();

        // POST /kpi/category-weights/refresh-templates
        // Explicit "Re-apply to existing templates" admin action: re-snaps
        // CategoryWeightSnapshot on every template under the given account
        // (optionally filtered to one Category) from current KPI.CategoryWeight,
        // then cascades to unsubmitted assignments. Submitted rows are
        // protected by the existing cascade filter.
        app.MapPost("/kpi/category-weights/refresh-templates", async (ClaimsPrincipal user, RefreshTemplateCategoryWeightsRequest request, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.KpiAdmin))
                return Results.Forbid();

            if (string.IsNullOrWhiteSpace(request.AccountCode))
                return Results.BadRequest(new ApiError("ACCOUNT_REQUIRED", "AccountCode is required."));

            // Tenant scoping: super-admins can refresh any account; tenant-admins
            // only those they can reach.
            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.SuperAdmin))
            {
                var currentUserId = await AccessScope.GetCurrentUserIdAsync(user, conn);
                if (currentUserId is null) return Results.Forbid();

                var accessible = await conn.QuerySingleOrDefaultAsync<int?>($@"
                    {AccessScope.AccessibleAccountsCte}
                    SELECT a.AccountId
                    FROM Dim.Account AS a
                    WHERE a.AccountCode = @AccountCode
                      AND a.AccountId IN (SELECT AccountId FROM AccessibleAccounts)",
                    new { AccountCode = request.AccountCode, UserId = currentUserId.Value });

                if (accessible is null) return Results.Forbid();
            }

            var actorUpn = user.FindFirstValue("preferred_username")
                        ?? user.FindFirstValue(ClaimTypes.Upn)
                        ?? user.FindFirstValue(ClaimTypes.Name);

            var result = await conn.QuerySingleAsync<RefreshTemplateCategoryWeightsResponse>(
                "App.usp_RefreshTemplateCategoryWeights",
                new { AccountCode = request.AccountCode, Category = request.Category, ActorUPN = actorUpn },
                commandType: System.Data.CommandType.StoredProcedure);

            return Results.Ok(result);
        }).RequireAuthorization();

        // PUT /kpi/category-weights — bulk upsert for one account.
        // Categories not present in Weights are left untouched. Pass IsActive=false to disable.
        app.MapPut("/kpi/category-weights", async (ClaimsPrincipal user, UpsertCategoryWeightsRequest request, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.KpiAdmin))
                return Results.Forbid();

            if (string.IsNullOrWhiteSpace(request.AccountCode))
                return Results.BadRequest(new ApiError("ACCOUNT_REQUIRED", "AccountCode is required."));

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.SuperAdmin))
            {
                var currentUserId = await AccessScope.GetCurrentUserIdAsync(user, conn);
                if (currentUserId is null) return Results.Forbid();

                var accessible = await conn.QuerySingleOrDefaultAsync<int?>($@"
                    {AccessScope.AccessibleAccountsCte}
                    SELECT a.AccountId
                    FROM Dim.Account AS a
                    WHERE a.AccountCode = @AccountCode
                      AND a.AccountId IN (SELECT AccountId FROM AccessibleAccounts)",
                    new { AccountCode = request.AccountCode, UserId = currentUserId.Value });

                if (accessible is null) return Results.Forbid();
            }

            var actorUpn = user.FindFirstValue("preferred_username")
                        ?? user.FindFirstValue(ClaimTypes.Upn)
                        ?? user.FindFirstValue(ClaimTypes.Name);

            var weightsJson = JsonSerializer.Serialize(
                request.Weights?.Select(w => new
                {
                    category = w.Category,
                    weight   = w.Weight,
                    isActive = w.IsActive,
                }).ToArray() ?? Array.Empty<object>());

            await conn.ExecuteAsync("App.usp_UpsertCategoryWeights",
                new { AccountCode = request.AccountCode, WeightsJson = weightsJson, ActorUPN = actorUpn },
                commandType: System.Data.CommandType.StoredProcedure);

            var rows = await conn.QueryAsync<CategoryWeightDto>(@"
                SELECT cw.Category, cw.Weight, CAST(cw.IsActive AS bit) AS IsActive
                FROM KPI.CategoryWeight AS cw
                JOIN Dim.Account        AS a ON a.AccountId = cw.AccountId
                WHERE a.AccountCode = @AccountCode
                ORDER BY cw.Category",
                new { AccountCode = request.AccountCode });

            var list = rows.ToList();
            return Results.Ok(new ApiList<CategoryWeightDto>(list, list.Count));
        }).RequireAuthorization();

        return app;
    }
}
