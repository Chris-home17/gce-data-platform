using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Helpers;
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

            var p = new DynamicParameters();
            p.Add("@SiteOrgUnitId", request.SiteOrgUnitId);
            p.Add("@PeriodId", request.PeriodId);
            p.Add("@CreatedBy", callerUpn);
            p.Add("@TokenId", dbType: System.Data.DbType.Guid,
                direction: System.Data.ParameterDirection.Output);

            try
            {
                await conn.ExecuteAsync("App.usp_CreateSubmissionToken", p,
                    commandType: System.Data.CommandType.StoredProcedure);
            }
            catch (Microsoft.Data.SqlClient.SqlException ex) when (ex.Number == 50210)
            {
                return Results.NotFound(new ApiError("SITE_NOT_FOUND", ex.Message));
            }
            catch (Microsoft.Data.SqlClient.SqlException ex) when (ex.Number == 50211)
            {
                return Results.NotFound(new ApiError("PERIOD_NOT_FOUND", ex.Message));
            }

            var tokenIdGuid = p.Get<Guid>("@TokenId");
            var dto = await conn.QuerySingleAsync<SubmissionTokenDto>(@"
                SELECT
                    TokenId,
                    SiteCode,
                    SiteName,
                    AccountCode,
                    AccountName,
                    PeriodLabel,
                    PeriodStatus,
                    PeriodCloseDate,
                    ExpiresAtUtc,
                    CreatedBy,
                    CreatedAtUtc,
                    RevokedAtUtc
                FROM App.vSubmissionTokens
                WHERE TokenId = @TokenId",
                new { TokenId = tokenIdGuid });

            return Results.Created($"/kpi/submission-tokens/{tokenIdGuid}", dto);
        }).RequireAuthorization();

        // GET /kpi/submission-tokens/{tokenId}  — validate token and return full context
        app.MapGet("/kpi/submission-tokens/{tokenId:guid}", async (Guid tokenId, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();

            var header = await conn.QuerySingleOrDefaultAsync<TokenContextHeader?>(@"
                SELECT
                    TokenId,
                    ExpiresAtUtc,
                    SiteCode,
                    SiteName,
                    AccountCode,
                    AccountName,
                    PeriodLabel,
                    PeriodStatus,
                    PeriodCloseDate
                FROM App.vSubmissionTokens
                WHERE TokenId = @TokenId
                  AND RevokedAtUtc IS NULL
                  AND ExpiresAtUtc > SYSUTCDATETIME()",
                new { TokenId = tokenId });

            if (header is null)
                return Results.NotFound(new ApiError("TOKEN_INVALID", "Token not found, expired, or revoked."));

            var rawAssignments = await conn.QueryAsync<AssignmentWithSubmissionDto>(@"
                SELECT
                    AssignmentId,
                    ExternalId,
                    KpiCode,
                    KpiName,
                    EffectiveKpiName,
                    EffectiveKpiDescription,
                    Category,
                    DataType,
                    AllowMultiValue,
                    DropDownOptionsRaw,
                    IsRequired,
                    TargetValue,
                    ThresholdGreen,
                    ThresholdAmber,
                    ThresholdRed,
                    EffectiveThresholdDirection,
                    SubmitterGuidance,
                    SubmissionId,
                    SubmissionValue,
                    SubmissionText,
                    SubmissionBoolean,
                    SubmissionNotes,
                    LockState,
                    IsSubmitted
                FROM App.vSubmissionTokenAssignments
                WHERE TokenId = @TokenId
                ORDER BY Category, KpiName",
                new { TokenId = tokenId });

            var assignments = rawAssignments;

            var brandingRaw = await conn.QuerySingleOrDefaultAsync<AccountBrandingRaw?>(@"
                SELECT
                    AccountId,
                    PrimaryColor,
                    PrimaryColor2,
                    SecondaryColor,
                    SecondaryColor2,
                    AccentColor,
                    TextOnPrimaryOverride,
                    TextOnSecondaryOverride,
                    LogoDataUrl
                FROM Dim.Account
                WHERE AccountCode = @AccountCode",
                new { header.AccountCode });

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
                Assignments:    assignments,
                Branding:       BrandingHelper.Resolve(brandingRaw)
            );

            return Results.Ok(ctx);
        }).RequireAuthorization();

        // DELETE /kpi/submission-tokens/{tokenId}  — revoke a token
        app.MapDelete("/kpi/submission-tokens/{tokenId:guid}", async (Guid tokenId, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();

            try
            {
                await conn.ExecuteAsync("App.usp_RevokeSubmissionToken",
                    new { TokenId = tokenId },
                    commandType: System.Data.CommandType.StoredProcedure);
            }
            catch (Microsoft.Data.SqlClient.SqlException ex) when (ex.Number == 50212)
            {
                return Results.NotFound(new ApiError("TOKEN_NOT_FOUND", ex.Message));
            }

            return Results.NoContent();
        }).RequireAuthorization();

        // GET /kpi/submission-tokens?siteOrgUnitId=&periodId=  — list tokens (admin view)
        app.MapGet("/kpi/submission-tokens", async (int? siteOrgUnitId, int? periodId, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var items = await conn.QueryAsync<SubmissionTokenDto>(@"
                SELECT
                    TokenId,
                    SiteCode,
                    SiteName,
                    AccountCode,
                    AccountName,
                    PeriodLabel,
                    PeriodStatus,
                    PeriodCloseDate,
                    ExpiresAtUtc,
                    CreatedBy,
                    CreatedAtUtc,
                    RevokedAtUtc
                FROM App.vSubmissionTokens
                WHERE (@SiteOrgUnitId IS NULL OR SiteOrgUnitId = @SiteOrgUnitId)
                  AND (@PeriodId      IS NULL OR PeriodId      = @PeriodId)
                ORDER BY CreatedAtUtc DESC",
                new { SiteOrgUnitId = siteOrgUnitId, PeriodId = periodId });

            var list = items.ToList();
            return Results.Ok(new ApiList<SubmissionTokenDto>(list, list.Count));
        }).RequireAuthorization();

        return app;
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
