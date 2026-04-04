using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Models;
using System.Security.Claims;
using System.Text.Json;

namespace GcePlatform.Api.Endpoints;

public static class KpiSubmissionTokenEndpoints
{
    public static WebApplication MapKpiSubmissionTokenEndpoints(this WebApplication app)
    {
        // POST /kpi/submission-tokens  — generate a token for a site + period
        app.MapPost("/kpi/submission-tokens", async (CreateSubmissionTokenRequest request, HttpContext http, DbConnectionFactory db) =>
        {
            var callerUpn = http.User.FindFirst("preferred_username")?.Value
                         ?? http.User.FindFirst(ClaimTypes.Email)?.Value
                         ?? http.User.FindFirst(ClaimTypes.Name)?.Value
                         ?? "unknown";

            using var conn = db.CreateConnection();

            // Validate the site exists and belongs to an account
            var site = await conn.QuerySingleOrDefaultAsync<SiteLookup?>(@"
                SELECT ou.OrgUnitCode, ou.OrgUnitName, a.AccountId, a.AccountCode, a.AccountName
                FROM Dim.OrgUnit AS ou
                JOIN Dim.Account AS a ON a.AccountId = ou.AccountId
                WHERE ou.OrgUnitId = @SiteOrgUnitId
                  AND ou.OrgUnitType = 'Site'
                  AND ou.IsActive = 1",
                new { request.SiteOrgUnitId });

            if (site is null)
                return Results.NotFound(new ApiError("SITE_NOT_FOUND", $"Active site {request.SiteOrgUnitId} not found."));

            // Validate the period exists and get its close date for expiry
            var period = await conn.QuerySingleOrDefaultAsync<PeriodLookup?>(@"
                SELECT PeriodLabel, Status, CAST(SubmissionCloseDate AS DATETIME2) AS SubmissionCloseDate
                FROM KPI.Period
                WHERE PeriodID = @PeriodId",
                new { request.PeriodId });

            if (period is null)
                return Results.NotFound(new ApiError("PERIOD_NOT_FOUND", $"Period {request.PeriodId} not found."));

            // Token expires at end of period's submission close date (UTC midnight)
            var expiresAt = period.SubmissionCloseDate.Date.AddDays(1).AddSeconds(-1);

            var tokenIdGuid = Guid.NewGuid();
            await conn.ExecuteAsync(@"
                INSERT INTO KPI.SubmissionToken
                    (TokenId, SiteOrgUnitId, AccountId, PeriodId, ExpiresAtUtc, CreatedBy)
                VALUES
                    (@TokenId, @SiteOrgUnitId, @AccountId, @PeriodId, @ExpiresAtUtc, @CreatedBy)",
                new
                {
                    TokenId      = tokenIdGuid,
                    request.SiteOrgUnitId,
                    AccountId    = site.AccountId,
                    request.PeriodId,
                    ExpiresAtUtc = expiresAt,
                    CreatedBy    = callerUpn
                });

            var dto = new SubmissionTokenDto(
                TokenId:        tokenIdGuid,
                SiteCode:       site.OrgUnitCode,
                SiteName:       site.OrgUnitName,
                AccountCode:    site.AccountCode,
                AccountName:    site.AccountName,
                PeriodLabel:    period.PeriodLabel,
                PeriodStatus:   period.Status,
                PeriodCloseDate: period.SubmissionCloseDate,
                ExpiresAtUtc:   expiresAt,
                CreatedBy:      callerUpn,
                CreatedAtUtc:   DateTime.UtcNow,
                RevokedAtUtc:   null
            );

            return Results.Created($"/kpi/submission-tokens/{tokenIdGuid}", dto);
        }).RequireAuthorization();

        // GET /kpi/submission-tokens/{tokenId}  — validate token and return full context
        app.MapGet("/kpi/submission-tokens/{tokenId:guid}", async (Guid tokenId, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();

            var header = await conn.QuerySingleOrDefaultAsync<TokenContextHeader?>(@"
                SELECT
                    st.TokenId,
                    st.ExpiresAtUtc,
                    ou.OrgUnitCode  AS SiteCode,
                    ou.OrgUnitName  AS SiteName,
                    a.AccountCode,
                    a.AccountName,
                    p.PeriodLabel,
                    p.Status        AS PeriodStatus,
                    CAST(p.SubmissionCloseDate AS DATETIME2) AS PeriodCloseDate
                FROM KPI.SubmissionToken AS st
                JOIN Dim.OrgUnit AS ou ON ou.OrgUnitId = st.SiteOrgUnitId
                JOIN Dim.Account AS a  ON a.AccountId  = st.AccountId
                JOIN KPI.Period  AS p  ON p.PeriodID   = st.PeriodId
                WHERE st.TokenId       = @TokenId
                  AND st.RevokedAtUtc  IS NULL
                  AND st.ExpiresAtUtc  > SYSUTCDATETIME()",
                new { TokenId = tokenId });

            if (header is null)
                return Results.NotFound(new ApiError("TOKEN_INVALID", "Token not found, expired, or revoked."));

            var rawAssignments = await conn.QueryAsync<AssignmentWithSubmissionDto>(@"
                SELECT
                    asgn.AssignmentID                                       AS AssignmentId,
                    asgn.ExternalId,
                    d.KPICode                                               AS KpiCode,
                    d.KPIName                                               AS KpiName,
                    COALESCE(t.CustomKpiName,        d.KPIName)             AS EffectiveKpiName,
                    COALESCE(t.CustomKpiDescription, d.KPIDescription)      AS EffectiveKpiDescription,
                    d.Category,
                    d.DataType,
                    d.AllowMultiValue,
                    -- Effective drop-down options: template overrides when present, else definition defaults
                    CASE WHEN d.DataType = 'DropDown' THEN
                        COALESCE(
                            CASE WHEN asgn.AssignmentTemplateID IS NOT NULL AND EXISTS (
                                SELECT 1 FROM KPI.AssignmentTemplateDropDownOption x
                                WHERE x.AssignmentTemplateID = asgn.AssignmentTemplateID
                            ) THEN (
                                SELECT STRING_AGG(opt.OptionValue, '||') WITHIN GROUP (ORDER BY opt.SortOrder)
                                FROM KPI.AssignmentTemplateDropDownOption opt
                                WHERE opt.AssignmentTemplateID = asgn.AssignmentTemplateID
                            ) END,
                            (
                                SELECT STRING_AGG(opt.OptionValue, '||') WITHIN GROUP (ORDER BY opt.SortOrder)
                                FROM KPI.DropDownOption opt
                                WHERE opt.KPIID = d.KPIID AND opt.IsActive = 1
                            )
                        )
                    ELSE NULL END                                           AS DropDownOptionsRaw,
                    CAST(asgn.IsRequired AS BIT)                            AS IsRequired,
                    asgn.TargetValue,
                    asgn.ThresholdGreen,
                    asgn.ThresholdAmber,
                    asgn.ThresholdRed,
                    COALESCE(asgn.ThresholdDirection, d.ThresholdDirection) AS EffectiveThresholdDirection,
                    asgn.SubmitterGuidance,
                    sub.SubmissionID                                        AS SubmissionId,
                    sub.SubmissionValue,
                    sub.SubmissionText,
                    sub.SubmissionBoolean,
                    sub.SubmissionNotes,
                    sub.LockState,
                    CAST(CASE WHEN sub.SubmissionID IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS IsSubmitted
                FROM KPI.SubmissionToken        AS st
                JOIN KPI.Assignment             AS asgn
                    ON  asgn.PeriodID  = st.PeriodId
                    AND asgn.IsActive  = 1
                    AND (
                            -- site-specific assignment for this exact site
                            asgn.OrgUnitId = st.SiteOrgUnitId
                            OR
                            -- account-wide assignment, not shadowed by a site-specific one
                            (
                                asgn.OrgUnitId IS NULL
                                AND asgn.AccountId = st.AccountId
                                AND NOT EXISTS (
                                    SELECT 1 FROM KPI.Assignment sa
                                    WHERE  sa.KPIID     = asgn.KPIID
                                      AND  sa.OrgUnitId = st.SiteOrgUnitId
                                      AND  sa.PeriodID  = st.PeriodId
                                      AND  sa.IsActive  = 1
                                )
                            )
                        )
                JOIN KPI.Definition             AS d    ON d.KPIID         = asgn.KPIID
                LEFT JOIN KPI.AssignmentTemplate AS t   ON t.AssignmentTemplateID = asgn.AssignmentTemplateID
                LEFT JOIN KPI.Submission         AS sub ON sub.AssignmentID = asgn.AssignmentID
                WHERE st.TokenId = @TokenId
                ORDER BY d.Category, d.KPIName",
                new { TokenId = tokenId });

            var assignments = rawAssignments;

            var ctx = new SubmissionTokenContextDto(
                TokenId:        header.TokenId,
                SiteCode:       header.SiteCode,
                SiteName:       header.SiteName,
                AccountCode:    header.AccountCode,
                AccountName:    header.AccountName,
                PeriodLabel:    header.PeriodLabel,
                PeriodStatus:   header.PeriodStatus,
                PeriodCloseDate: header.PeriodCloseDate,
                ExpiresAtUtc:   header.ExpiresAtUtc,
                Assignments:    assignments
            );

            return Results.Ok(ctx);
        }).RequireAuthorization();

        // DELETE /kpi/submission-tokens/{tokenId}  — revoke a token
        app.MapDelete("/kpi/submission-tokens/{tokenId:guid}", async (Guid tokenId, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var rows = await conn.ExecuteAsync(@"
                UPDATE KPI.SubmissionToken
                SET RevokedAtUtc = SYSUTCDATETIME()
                WHERE TokenId = @TokenId
                  AND RevokedAtUtc IS NULL",
                new { TokenId = tokenId });

            return rows == 0
                ? Results.NotFound(new ApiError("TOKEN_NOT_FOUND", $"Token {tokenId} not found or already revoked."))
                : Results.NoContent();
        }).RequireAuthorization();

        // GET /kpi/submission-tokens?siteOrgUnitId=&periodId=  — list tokens (admin view)
        app.MapGet("/kpi/submission-tokens", async (int? siteOrgUnitId, int? periodId, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var items = await conn.QueryAsync<SubmissionTokenDto>(@"
                SELECT
                    st.TokenId,
                    ou.OrgUnitCode  AS SiteCode,
                    ou.OrgUnitName  AS SiteName,
                    a.AccountCode,
                    a.AccountName,
                    p.PeriodLabel,
                    p.Status        AS PeriodStatus,
                    CAST(p.SubmissionCloseDate AS DATETIME2) AS PeriodCloseDate,
                    st.ExpiresAtUtc,
                    st.CreatedBy,
                    st.CreatedAtUtc,
                    st.RevokedAtUtc
                FROM KPI.SubmissionToken AS st
                JOIN Dim.OrgUnit AS ou ON ou.OrgUnitId = st.SiteOrgUnitId
                JOIN Dim.Account AS a  ON a.AccountId  = st.AccountId
                JOIN KPI.Period  AS p  ON p.PeriodID   = st.PeriodId
                WHERE (@SiteOrgUnitId IS NULL OR st.SiteOrgUnitId = @SiteOrgUnitId)
                  AND (@PeriodId      IS NULL OR st.PeriodId      = @PeriodId)
                ORDER BY st.CreatedAtUtc DESC",
                new { SiteOrgUnitId = siteOrgUnitId, PeriodId = periodId });

            var list = items.ToList();
            return Results.Ok(new ApiList<SubmissionTokenDto>(list, list.Count));
        }).RequireAuthorization();

        return app;
    }

    // Private DTOs — kept here to avoid polluting the public model surface
    private sealed class SiteLookup
    {
        public string   OrgUnitCode { get; init; } = "";
        public string   OrgUnitName { get; init; } = "";
        public int      AccountId   { get; init; }
        public string   AccountCode { get; init; } = "";
        public string   AccountName { get; init; } = "";
    }

    private sealed class PeriodLookup
    {
        public string   PeriodLabel          { get; init; } = "";
        public string   Status               { get; init; } = "";
        public DateTime SubmissionCloseDate  { get; init; }
    }

    private sealed class TokenContextHeader
    {
        public Guid     TokenId       { get; init; }
        public string   SiteCode      { get; init; } = "";
        public string   SiteName      { get; init; } = "";
        public string   AccountCode   { get; init; } = "";
        public string   AccountName   { get; init; } = "";
        public string   PeriodLabel   { get; init; } = "";
        public string   PeriodStatus  { get; init; } = "";
        public DateTime PeriodCloseDate { get; init; }
        public DateTime ExpiresAtUtc  { get; init; }
    }
}
