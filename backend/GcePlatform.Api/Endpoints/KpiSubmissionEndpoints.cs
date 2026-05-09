using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Helpers;
using GcePlatform.Api.Models;
using GcePlatform.Api.Services;
using System.Security.Claims;

namespace GcePlatform.Api.Endpoints;

public static class KpiSubmissionEndpoints
{
    public static WebApplication MapKpiSubmissionEndpoints(this WebApplication app)
    {
        // POST /kpi/submissions
        app.MapPost("/kpi/submissions", async (SubmitKpiRequest request, HttpContext http, DbConnectionFactory db) =>
        {
            var upn = http.User.FindFirst("preferred_username")?.Value
                   ?? http.User.FindFirst(ClaimTypes.Email)?.Value
                   ?? http.User.FindFirst(ClaimTypes.Name)?.Value;

            if (string.IsNullOrEmpty(upn))
                return Results.Unauthorized();

            using var conn = db.CreateConnection();

            // Pre-submit validation (per-assignment rules). Runs in C# because
            // T-SQL has no native regex; usp_SubmitKpi only snapshots the rules.
            var ruleRow = await LookupRules(conn, request.AssignmentExternalId);
            if (ruleRow is not null)
            {
                var validation = SubmissionValidator.Validate(
                    ruleRow.Value.DataType,
                    new SubmissionValidator.Rules(
                        ruleRow.Value.MinValue, ruleRow.Value.MaxValue,
                        ruleRow.Value.Precision, ruleRow.Value.Regex, ruleRow.Value.Message),
                    request.SubmissionValue,
                    request.SubmissionText);
                if (!validation.Ok)
                    return Results.BadRequest(new ApiError("VALIDATION_FAILED", validation.ErrorMessage!));
            }

            var p = new DynamicParameters();
            p.Add("@AssignmentExternalId", request.AssignmentExternalId);
            p.Add("@SubmitterUPN",         upn);
            p.Add("@SubmissionValue",      request.SubmissionValue);
            p.Add("@SubmissionText",       request.SubmissionText);
            p.Add("@SubmissionBoolean",    request.SubmissionBoolean);
            p.Add("@SubmissionNotes",      request.SubmissionNotes);
            p.Add("@LockOnSubmit",         request.LockOnSubmit);
            p.Add("@ChangeReason",         request.ChangeReason);
            p.Add("@BypassLock",           request.BypassLock);
            p.Add("@SubmissionID",         dbType: System.Data.DbType.Int32,
                                           direction: System.Data.ParameterDirection.Output);

            try
            {
                await conn.ExecuteAsync("App.usp_SubmitKpi", p,
                    commandType: System.Data.CommandType.StoredProcedure);
            }
            catch (Microsoft.Data.SqlClient.SqlException ex) when (ex.Number == 50201)
            {
                return Results.NotFound(new ApiError("ASSIGNMENT_NOT_FOUND", ex.Message));
            }
            catch (Microsoft.Data.SqlClient.SqlException ex) when (ex.Number == 50202)
            {
                return Results.Conflict(new ApiError("PERIOD_NOT_OPEN", ex.Message));
            }
            catch (Microsoft.Data.SqlClient.SqlException ex) when (ex.Number == 50203)
            {
                return Results.Conflict(new ApiError("SUBMISSION_WINDOW_CLOSED", ex.Message));
            }
            catch (Microsoft.Data.SqlClient.SqlException ex) when (ex.Number == 50204)
            {
                return Results.BadRequest(new ApiError("SUBMITTER_NOT_FOUND", ex.Message));
            }
            catch (Microsoft.Data.SqlClient.SqlException ex) when (ex.Number == 50205)
            {
                return Results.Conflict(new ApiError("SUBMISSION_LOCKED", ex.Message));
            }

            var submissionId = p.Get<int>("@SubmissionID");
            return Results.Ok(new { submissionId });
        }).RequireAuthorization();

        // POST /kpi/submissions/bulk  — submit multiple KPIs in one call (e.g., from the completion form)
        app.MapPost("/kpi/submissions/bulk", async (IEnumerable<SubmitKpiRequest> requests, HttpContext http, DbConnectionFactory db) =>
        {
            var upn = http.User.FindFirst("preferred_username")?.Value
                   ?? http.User.FindFirst(ClaimTypes.Email)?.Value
                   ?? http.User.FindFirst(ClaimTypes.Name)?.Value;

            if (string.IsNullOrEmpty(upn))
                return Results.Unauthorized();

            using var conn = db.CreateConnection();
            var results = new List<object>();

            foreach (var request in requests)
            {
                // Validate before calling the proc (rules pulled per-assignment).
                var ruleRow = await LookupRules(conn, request.AssignmentExternalId);
                if (ruleRow is not null)
                {
                    var validation = SubmissionValidator.Validate(
                        ruleRow.Value.DataType,
                        new SubmissionValidator.Rules(
                            ruleRow.Value.MinValue, ruleRow.Value.MaxValue,
                            ruleRow.Value.Precision, ruleRow.Value.Regex, ruleRow.Value.Message),
                        request.SubmissionValue,
                        request.SubmissionText);
                    if (!validation.Ok)
                    {
                        results.Add(new
                        {
                            assignmentExternalId = request.AssignmentExternalId,
                            submissionId = (int?)null,
                            success = false,
                            error = validation.ErrorMessage,
                        });
                        continue;
                    }
                }

                var p = new DynamicParameters();
                p.Add("@AssignmentExternalId", request.AssignmentExternalId);
                p.Add("@SubmitterUPN",         upn);
                p.Add("@SubmissionValue",      request.SubmissionValue);
                p.Add("@SubmissionText",       request.SubmissionText);
                p.Add("@SubmissionBoolean",    request.SubmissionBoolean);
                p.Add("@SubmissionNotes",      request.SubmissionNotes);
                p.Add("@LockOnSubmit",         request.LockOnSubmit);
                p.Add("@ChangeReason",         request.ChangeReason);
                p.Add("@BypassLock",           request.BypassLock);
                p.Add("@SubmissionID",         dbType: System.Data.DbType.Int32,
                                               direction: System.Data.ParameterDirection.Output);

                try
                {
                    await conn.ExecuteAsync("App.usp_SubmitKpi", p,
                        commandType: System.Data.CommandType.StoredProcedure);

                    results.Add(new
                    {
                        assignmentExternalId = request.AssignmentExternalId,
                        submissionId = p.Get<int>("@SubmissionID"),
                        success = true,
                        error = (string?)null
                    });
                }
                catch (Microsoft.Data.SqlClient.SqlException ex)
                {
                    results.Add(new
                    {
                        assignmentExternalId = request.AssignmentExternalId,
                        submissionId = (int?)null,
                        success = false,
                        error = ex.Message
                    });
                }
            }

            return Results.Ok(results);
        }).RequireAuthorization();

        // GET /kpi/site-submissions?siteOrgUnitId=&periodId=
        // Admin drill-down: all assignments for a site+period with current submission state.
        // Non-super-admins are rejected when the site belongs to an account they cannot access.
        app.MapGet("/kpi/site-submissions", async (ClaimsPrincipal user, int siteOrgUnitId, int periodId, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.SuperAdmin))
            {
                var currentUserId = await AccessScope.GetCurrentUserIdAsync(user, conn);
                if (currentUserId is null)
                    return Results.NotFound(new ApiError("SITE_NOT_FOUND", $"Site {siteOrgUnitId} not found."));

                var canAccess = await conn.ExecuteScalarAsync<bool>($@"
                    {AccessScope.AccessibleAccountsCte}
                    SELECT CAST(
                        CASE WHEN EXISTS
                        (
                            SELECT 1
                            FROM Dim.OrgUnit AS ou
                            WHERE ou.OrgUnitId = @SiteOrgUnitId
                              AND ou.AccountId IN (SELECT AccountId FROM AccessibleAccounts)
                        )
                        THEN 1 ELSE 0 END AS bit)",
                    new { SiteOrgUnitId = siteOrgUnitId, UserId = currentUserId.Value });

                if (!canAccess)
                    return Results.NotFound(new ApiError("SITE_NOT_FOUND", $"Site {siteOrgUnitId} not found."));
            }

            var items = await conn.QueryAsync<SiteSubmissionDetailDto>(@"
                SELECT
                    sd.AssignmentId,
                    sd.ExternalId,
                    sd.KpiCode,
                    sd.KpiName,
                    sd.EffectiveKpiName,
                    sd.CategoryId,
                    sd.CategoryCode,
                    sd.Category,
                    sd.DataType,
                    sd.IsRequired,
                    sd.TargetValue,
                    sd.ThresholdGreen,
                    sd.ThresholdAmber,
                    sd.ThresholdRed,
                    sd.EffectiveThresholdDirection,
                    sd.SubmissionId,
                    sd.SubmissionValue,
                    sd.SubmissionText,
                    sd.SubmissionBoolean,
                    sd.SubmissionNotes,
                    sd.LockState,
                    sd.SubmittedByUpn,
                    sd.SubmittedAt,
                    sd.IsSubmitted,
                    sd.RagStatus,
                    sd.AssignmentGroupName,
                    sc.Score,
                    sc.MaxScore,
                    sc.KpiWeight
                FROM App.vSiteSubmissionDetails AS sd
                LEFT JOIN App.vKpiSubmissionScores AS sc ON sc.AssignmentID = sd.AssignmentId
                WHERE sd.SiteOrgUnitId = @SiteOrgUnitId
                  AND sd.PeriodId = @PeriodId
                ORDER BY sd.Category, sd.KpiName",
                new { SiteOrgUnitId = siteOrgUnitId, PeriodId = periodId });

            var list = items.ToList();
            return Results.Ok(new ApiList<SiteSubmissionDetailDto>(list, list.Count));
        }).RequireAuthorization();

        // PATCH /kpi/submissions/{externalId}/unlock
        // Unlock a manually-locked submission so the submitter can update it via their token link.
        // Only allowed while the period is still Open.
        app.MapMethods("/kpi/submissions/{externalId:guid}/unlock", new[] { "PATCH" },
            async (ClaimsPrincipal user, Guid externalId, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasAnyPermissionAsync(user, conn, Permissions.KpiAssign, Permissions.KpiAdmin))
                return Results.Forbid();

            try
            {
                await conn.ExecuteAsync("App.usp_UnlockKpiSubmission",
                    new { AssignmentExternalId = externalId },
                    commandType: System.Data.CommandType.StoredProcedure);
            }
            catch (Microsoft.Data.SqlClient.SqlException ex) when (ex.Number == 50220)
            {
                return Results.NotFound(new ApiError("SUBMISSION_NOT_FOUND", ex.Message));
            }
            catch (Microsoft.Data.SqlClient.SqlException ex) when (ex.Number == 50221)
            {
                return Results.Conflict(new ApiError("PERIOD_CLOSED",
                    "This submission was locked when the period closed. Use the KpiAdmin bypass to edit post-close."));
            }
            catch (Microsoft.Data.SqlClient.SqlException ex) when (ex.Number == 50222)
            {
                return Results.Conflict(new ApiError("PERIOD_NOT_OPEN", ex.Message));
            }

            return Results.NoContent();
        }).RequireAuthorization();

        return app;
    }

    /// <summary>
    /// Single Dapper read of an assignment's validation rules + data type
    /// keyed by ExternalId. Returns null if the assignment doesn't exist —
    /// usp_SubmitKpi will then raise the standard "not found" error.
    /// </summary>
    private static async Task<RuleRow?> LookupRules(System.Data.IDbConnection conn, Guid assignmentExternalId)
    {
        return await conn.QuerySingleOrDefaultAsync<RuleRow?>(@"
            SELECT
                d.DataType                AS DataType,
                a.ValidationMinValue      AS MinValue,
                a.ValidationMaxValue      AS MaxValue,
                a.ValidationPrecision     AS Precision,
                a.ValidationRegex         AS Regex,
                a.ValidationMessage       AS Message
            FROM KPI.Assignment AS a
            JOIN KPI.Definition AS d ON d.KPIID = a.KPIID
            WHERE a.ExternalId = @AssignmentExternalId
              AND a.IsActive = 1",
            new { AssignmentExternalId = assignmentExternalId });
    }

    private record struct RuleRow(string DataType, decimal? MinValue, decimal? MaxValue, int? Precision, string? Regex, string? Message);
}
