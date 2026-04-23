using Dapper;
using GcePlatform.Api.Data;
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
        // Admin drill-down: all assignments for a site+period with current submission state
        app.MapGet("/kpi/site-submissions", async (int siteOrgUnitId, int periodId, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var items = await conn.QueryAsync<SiteSubmissionDetailDto>(@"
                SELECT
                    AssignmentId,
                    ExternalId,
                    KpiCode,
                    KpiName,
                    EffectiveKpiName,
                    Category,
                    DataType,
                    IsRequired,
                    TargetValue,
                    ThresholdGreen,
                    ThresholdAmber,
                    ThresholdRed,
                    EffectiveThresholdDirection,
                    SubmissionId,
                    SubmissionValue,
                    SubmissionText,
                    SubmissionBoolean,
                    SubmissionNotes,
                    LockState,
                    SubmittedByUpn,
                    SubmittedAt,
                    IsSubmitted,
                    RagStatus,
                    AssignmentGroupName
                FROM App.vSiteSubmissionDetails
                WHERE SiteOrgUnitId = @SiteOrgUnitId
                  AND PeriodId = @PeriodId
                ORDER BY Category, KpiName",
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

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.KpiManage))
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
}
