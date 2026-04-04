using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Models;
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
                    asgn.AssignmentID                                       AS AssignmentId,
                    asgn.ExternalId,
                    d.KPICode                                               AS KpiCode,
                    d.KPIName                                               AS KpiName,
                    COALESCE(t.CustomKpiName, d.KPIName)                    AS EffectiveKpiName,
                    d.Category,
                    d.DataType,
                    CAST(asgn.IsRequired AS BIT)                            AS IsRequired,
                    asgn.TargetValue,
                    asgn.ThresholdGreen,
                    asgn.ThresholdAmber,
                    asgn.ThresholdRed,
                    COALESCE(asgn.ThresholdDirection, d.ThresholdDirection) AS EffectiveThresholdDirection,
                    sub.SubmissionID                                        AS SubmissionId,
                    sub.SubmissionValue,
                    sub.SubmissionText,
                    sub.SubmissionBoolean,
                    sub.SubmissionNotes,
                    sub.LockState,
                    u.UPN                                                   AS SubmittedByUpn,
                    sub.SubmittedAt,
                    CAST(CASE WHEN sub.SubmissionID IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS IsSubmitted,
                    CASE
                        WHEN d.DataType NOT IN ('Numeric','Percentage','Currency') THEN NULL
                        WHEN sub.SubmissionValue IS NULL                           THEN NULL
                        WHEN asgn.ThresholdGreen IS NULL                           THEN NULL
                        WHEN COALESCE(asgn.ThresholdDirection, d.ThresholdDirection) = 'Higher'
                        THEN CASE
                            WHEN sub.SubmissionValue >= asgn.ThresholdGreen THEN 'Green'
                            WHEN sub.SubmissionValue >= asgn.ThresholdAmber THEN 'Amber'
                            ELSE 'Red'
                        END
                        WHEN COALESCE(asgn.ThresholdDirection, d.ThresholdDirection) = 'Lower'
                        THEN CASE
                            WHEN sub.SubmissionValue <= asgn.ThresholdGreen THEN 'Green'
                            WHEN sub.SubmissionValue <= asgn.ThresholdAmber THEN 'Amber'
                            ELSE 'Red'
                        END
                        ELSE NULL
                    END                                                     AS RagStatus
                FROM KPI.Assignment                 AS asgn
                JOIN KPI.Definition                 AS d    ON d.KPIID              = asgn.KPIID
                LEFT JOIN KPI.AssignmentTemplate    AS t    ON t.AssignmentTemplateID = asgn.AssignmentTemplateID
                LEFT JOIN KPI.Submission            AS sub  ON sub.AssignmentID      = asgn.AssignmentID
                LEFT JOIN Sec.[User]                AS u    ON u.UserId              = sub.SubmittedByPrincipalId
                WHERE asgn.OrgUnitId  = @SiteOrgUnitId
                  AND asgn.PeriodID   = @PeriodId
                  AND asgn.IsActive   = 1
                ORDER BY d.Category, d.KPIName",
                new { SiteOrgUnitId = siteOrgUnitId, PeriodId = periodId });

            var list = items.ToList();
            return Results.Ok(new ApiList<SiteSubmissionDetailDto>(list, list.Count));
        }).RequireAuthorization();

        // PATCH /kpi/submissions/{externalId}/unlock
        // Unlock a manually-locked submission so the submitter can update it via their token link.
        // Only allowed while the period is still Open.
        app.MapMethods("/kpi/submissions/{externalId:guid}/unlock", new[] { "PATCH" },
            async (Guid externalId, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();

            var row = await conn.QuerySingleOrDefaultAsync<UnlockRow>(@"
                SELECT sub.SubmissionID, sub.LockState, p.Status AS PeriodStatus
                FROM KPI.Assignment AS a
                JOIN KPI.Period     AS p   ON p.PeriodID     = a.PeriodID
                JOIN KPI.Submission AS sub ON sub.AssignmentID = a.AssignmentID
                WHERE a.ExternalId = @ExternalId
                  AND a.IsActive   = 1",
                new { ExternalId = externalId });

            if (row is null)
                return Results.NotFound(new ApiError("SUBMISSION_NOT_FOUND", "No submission found for this assignment."));

            if (row.LockState == "Unlocked")
                return Results.NoContent();   // already unlocked — idempotent

            if (row.LockState == "LockedByPeriodClose")
                return Results.Conflict(new ApiError("PERIOD_CLOSED",
                    "This submission was locked when the period closed. Use the KpiAdmin bypass to edit post-close."));

            if (row.PeriodStatus != "Open")
                return Results.Conflict(new ApiError("PERIOD_NOT_OPEN",
                    "Cannot unlock: period is not Open."));

            await conn.ExecuteAsync(@"
                UPDATE KPI.Submission
                SET LockState           = 'Unlocked',
                    LockedAt            = NULL,
                    LockedByPrincipalId = NULL,
                    ModifiedOnUtc       = SYSUTCDATETIME()
                WHERE SubmissionID = @Id",
                new { Id = row.SubmissionId });

            return Results.NoContent();
        }).RequireAuthorization();

        return app;
    }

    private sealed class UnlockRow
    {
        public int    SubmissionId  { get; init; }
        public string LockState     { get; init; } = "";
        public string PeriodStatus  { get; init; } = "";
    }
}
