using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Models;

namespace GcePlatform.Api.Endpoints;

public static class KpiAssignmentEndpoints
{
    public static WebApplication MapKpiAssignmentEndpoints(this WebApplication app)
    {
        app.MapGet("/kpi/assignment-templates", async (int? accountId, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var items = await conn.QueryAsync<KpiAssignmentTemplateDto>(@"
                SELECT
                    AssignmentTemplateId,
                    ExternalId,
                    KpiCode,
                    KpiName,
                    CustomKpiName,
                    CustomKpiDescription,
                    EffectiveKpiName,
                    EffectiveKpiDescription,
                    Category,
                    PeriodScheduleId,
                    ScheduleName,
                    FrequencyType,
                    FrequencyInterval,
                    AccountCode,
                    AccountName,
                    SiteCode,
                    SiteName,
                    CAST(IsAccountWide AS bit) AS IsAccountWide,
                    IsRequired,
                    TargetValue,
                    ThresholdGreen,
                    ThresholdAmber,
                    ThresholdRed,
                    EffectiveThresholdDirection,
                    IsActive,
                    GeneratedAssignmentCount
                FROM App.vKpiAssignmentTemplates
                WHERE (@AccountId IS NULL OR AccountId = @AccountId)
                ORDER BY ScheduleName, AccountCode, KpiCode",
                new { AccountId = accountId });

            var list = items.ToList();
            return Results.Ok(new ApiList<KpiAssignmentTemplateDto>(list, list.Count));
        }).RequireAuthorization();

        app.MapPost("/kpi/assignment-templates", async (CreateKpiAssignmentTemplateRequest request, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();

            var p = new DynamicParameters();
            p.Add("@KpiCode", request.KpiCode);
            p.Add("@PeriodScheduleID", request.PeriodScheduleId);
            p.Add("@AccountCode", request.AccountCode);
            p.Add("@OrgUnitCode", request.OrgUnitCode);
            p.Add("@OrgUnitType", request.OrgUnitType);
            p.Add("@IsRequired", request.IsRequired);
            p.Add("@TargetValue", request.TargetValue);
            p.Add("@ThresholdGreen", request.ThresholdGreen);
            p.Add("@ThresholdAmber", request.ThresholdAmber);
            p.Add("@ThresholdRed", request.ThresholdRed);
            p.Add("@ThresholdDirection", request.ThresholdDirection);
            p.Add("@SubmitterGuidance", request.SubmitterGuidance);
            p.Add("@CustomKpiName", request.CustomKpiName);
            p.Add("@CustomKpiDescription", request.CustomKpiDescription);
            p.Add("@AssignmentTemplateID", dbType: System.Data.DbType.Int32,
                  direction: System.Data.ParameterDirection.Output);

            await conn.ExecuteAsync("App.usp_UpsertKpiAssignmentTemplate", p,
                commandType: System.Data.CommandType.StoredProcedure);

            var newId = p.Get<int>("@AssignmentTemplateID");

            if (request.MaterializeNow)
            {
                await conn.ExecuteAsync("App.usp_MaterializeKpiAssignmentTemplates",
                    new { AssignmentTemplateID = newId },
                    commandType: System.Data.CommandType.StoredProcedure);
            }

            var created = await conn.QuerySingleAsync<KpiAssignmentTemplateDto>(@"
                SELECT
                    AssignmentTemplateId,
                    ExternalId,
                    KpiCode,
                    KpiName,
                    CustomKpiName,
                    CustomKpiDescription,
                    EffectiveKpiName,
                    EffectiveKpiDescription,
                    Category,
                    PeriodScheduleId,
                    ScheduleName,
                    FrequencyType,
                    FrequencyInterval,
                    AccountCode,
                    AccountName,
                    SiteCode,
                    SiteName,
                    CAST(IsAccountWide AS bit) AS IsAccountWide,
                    IsRequired,
                    TargetValue,
                    ThresholdGreen,
                    ThresholdAmber,
                    ThresholdRed,
                    EffectiveThresholdDirection,
                    IsActive,
                    GeneratedAssignmentCount
                FROM App.vKpiAssignmentTemplates
                WHERE AssignmentTemplateId = @Id",
                new { Id = newId });

            return Results.Created($"/kpi/assignment-templates/{newId}", created);
        }).RequireAuthorization();

        app.MapPost("/kpi/assignment-templates/{id:int}/materialize", async (int id, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();

            var exists = await conn.QuerySingleOrDefaultAsync<int?>(@"
                SELECT AssignmentTemplateId
                FROM App.vKpiAssignmentTemplates
                WHERE AssignmentTemplateId = @Id",
                new { Id = id });

            if (exists is null)
                return Results.NotFound(new ApiError("ASSIGNMENT_TEMPLATE_NOT_FOUND", $"Assignment template {id} not found."));

            await conn.ExecuteAsync("App.usp_MaterializeKpiAssignmentTemplates",
                new { AssignmentTemplateID = id },
                commandType: System.Data.CommandType.StoredProcedure);

            return Results.NoContent();
        }).RequireAuthorization();

        app.MapMethods("/kpi/assignment-templates/{id:int}/status", new[] { "PATCH" },
            async (int id, SetActiveRequest body, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var item = await conn.QuerySingleOrDefaultAsync<KpiAssignmentTemplateDto>(@"
                SELECT
                    AssignmentTemplateId,
                    ExternalId,
                    KpiCode,
                    KpiName,
                    CustomKpiName,
                    CustomKpiDescription,
                    EffectiveKpiName,
                    EffectiveKpiDescription,
                    Category,
                    PeriodScheduleId,
                    ScheduleName,
                    FrequencyType,
                    FrequencyInterval,
                    AccountCode,
                    AccountName,
                    SiteCode,
                    SiteName,
                    CAST(IsAccountWide AS bit) AS IsAccountWide,
                    IsRequired,
                    TargetValue,
                    ThresholdGreen,
                    ThresholdAmber,
                    ThresholdRed,
                    EffectiveThresholdDirection,
                    IsActive,
                    GeneratedAssignmentCount
                FROM App.vKpiAssignmentTemplates
                WHERE AssignmentTemplateId = @Id",
                new { Id = id });

            if (item is null)
                return Results.NotFound(new ApiError("ASSIGNMENT_TEMPLATE_NOT_FOUND", $"Assignment template {id} not found."));

            await conn.ExecuteAsync("App.usp_SetKpiAssignmentTemplateActive",
                new { AssignmentTemplateID = id, body.IsActive },
                commandType: System.Data.CommandType.StoredProcedure);

            if (body.IsActive)
            {
                await conn.ExecuteAsync("App.usp_MaterializeKpiAssignmentTemplates",
                    new { AssignmentTemplateID = id },
                    commandType: System.Data.CommandType.StoredProcedure);
            }

            return Results.NoContent();
        }).RequireAuthorization();

        // GET /kpi/effective-assignments?periodId=&accountId=&siteCode=
        // Returns the resolved assignment set for submission-facing screens:
        // site-specific assignments shadow account-wide ones for the same KPI + period,
        // and account-wide assignments are expanded to one row per active site.
        app.MapGet("/kpi/effective-assignments", async (int? periodId, int? accountId, string? siteCode, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var items = await conn.QueryAsync<EffectiveKpiAssignmentDto>(@"
                SELECT
                    AssignmentId,
                    ExternalId,
                    KpiCode,
                    KpiName,
                    EffectiveKpiName,
                    EffectiveKpiDescription,
                    Category,
                    AccountCode,
                    AccountName,
                    SiteCode,
                    SiteName,
                    CAST(IsAccountWide AS bit) AS IsAccountWide,
                    PeriodLabel,
                    PeriodYear,
                    PeriodMonth,
                    PeriodStatus,
                    IsRequired,
                    TargetValue,
                    ThresholdGreen,
                    ThresholdAmber,
                    ThresholdRed,
                    EffectiveThresholdDirection,
                    SubmitterGuidance,
                    IsActive
                FROM App.vEffectiveKpiAssignments
                WHERE (@PeriodId  IS NULL OR PeriodId   = @PeriodId)
                  AND (@AccountId IS NULL OR AccountId  = @AccountId)
                  AND (@SiteCode  IS NULL OR SiteCode   = @SiteCode)
                  AND IsActive = 1
                ORDER BY AccountCode, SiteCode, KpiCode",
                new { PeriodId = periodId, AccountId = accountId, SiteCode = siteCode });

            var list = items.ToList();
            return Results.Ok(new ApiList<EffectiveKpiAssignmentDto>(list, list.Count));
        }).RequireAuthorization();

        // GET /kpi/assignments?periodId=&accountId=&siteCode=
        app.MapGet("/kpi/assignments", async (int? periodId, int? accountId, string? siteCode, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var items = await conn.QueryAsync<KpiAssignmentDto>(@"
                SELECT
                    AssignmentId,
                    ExternalId,
                    KpiCode,
                    KpiName,
                    Category,
                    AccountCode,
                    AccountName,
                    SiteCode,
                    SiteName,
                    CAST(IsAccountWide AS bit) AS IsAccountWide,
                    PeriodId,
                    PeriodScheduleId,
                    ScheduleName,
                    PeriodLabel,
                    IsRequired,
                    TargetValue,
                    ThresholdGreen,
                    ThresholdAmber,
                    ThresholdRed,
                    EffectiveThresholdDirection,
                    IsActive
                FROM App.vKpiAssignments
                WHERE (@PeriodId IS NULL OR PeriodId = @PeriodId)
                  AND (@AccountId IS NULL OR AccountId = @AccountId)
                  AND (@SiteCode IS NULL OR SiteCode = @SiteCode)
                ORDER BY AccountCode, KpiCode",
                new { PeriodId = periodId, AccountId = accountId, SiteCode = siteCode });

            var list = items.ToList();
            return Results.Ok(new ApiList<KpiAssignmentDto>(list, list.Count));
        }).RequireAuthorization();

        // GET /kpi/assignments/{id}
        app.MapGet("/kpi/assignments/{id:int}", async (int id, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var item = await conn.QuerySingleOrDefaultAsync<KpiAssignmentDto>(@"
                SELECT
                    AssignmentId,
                    ExternalId,
                    KpiCode,
                    KpiName,
                    Category,
                    AccountCode,
                    AccountName,
                    SiteCode,
                    SiteName,
                    CAST(IsAccountWide AS bit) AS IsAccountWide,
                    PeriodId,
                    PeriodScheduleId,
                    ScheduleName,
                    PeriodLabel,
                    IsRequired,
                    TargetValue,
                    ThresholdGreen,
                    ThresholdAmber,
                    ThresholdRed,
                    EffectiveThresholdDirection,
                    IsActive
                FROM App.vKpiAssignments
                WHERE AssignmentId = @Id",
                new { Id = id });

            return item is null
                ? Results.NotFound(new ApiError("ASSIGNMENT_NOT_FOUND", $"Assignment {id} not found."))
                : Results.Ok(item);
        }).RequireAuthorization();

        // PATCH /kpi/assignments/{id}/status
        app.MapMethods("/kpi/assignments/{id:int}/status", new[] { "PATCH" },
            async (int id, SetActiveRequest body, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var item = await conn.QuerySingleOrDefaultAsync<KpiAssignmentDto>(@"
                SELECT
                    AssignmentId,
                    ExternalId,
                    KpiCode,
                    KpiName,
                    Category,
                    AccountCode,
                    AccountName,
                    SiteCode,
                    SiteName,
                    CAST(IsAccountWide AS bit) AS IsAccountWide,
                    PeriodId,
                    PeriodScheduleId,
                    ScheduleName,
                    PeriodLabel,
                    IsRequired,
                    TargetValue,
                    ThresholdGreen,
                    ThresholdAmber,
                    ThresholdRed,
                    EffectiveThresholdDirection,
                    IsActive
                FROM App.vKpiAssignments
                WHERE AssignmentId = @Id",
                new { Id = id });

            if (item is null)
                return Results.NotFound(new ApiError("ASSIGNMENT_NOT_FOUND", $"Assignment {id} not found."));

            try
            {
                await conn.ExecuteAsync("App.usp_SetKpiAssignmentActive",
                    new { AssignmentID = id, body.IsActive },
                    commandType: System.Data.CommandType.StoredProcedure);
            }
            catch (Microsoft.Data.SqlClient.SqlException ex) when (ex.Number == 50115)
            {
                return Results.Conflict(new ApiError("ASSIGNMENT_HAS_SUBMISSIONS", ex.Message));
            }

            return Results.NoContent();
        }).RequireAuthorization();

        // POST /kpi/assignments
        app.MapPost("/kpi/assignments", async (CreateKpiAssignmentRequest request, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();

            var p = new DynamicParameters();
            p.Add("@KpiCode", request.KpiCode);
            p.Add("@AccountCode", request.AccountCode);
            p.Add("@OrgUnitCode", request.OrgUnitCode);
            p.Add("@OrgUnitType", request.OrgUnitType);
            p.Add("@PeriodYear", request.PeriodYear);
            p.Add("@PeriodMonth", request.PeriodMonth);
            p.Add("@IsRequired", request.IsRequired);
            p.Add("@TargetValue", request.TargetValue);
            p.Add("@ThresholdGreen", request.ThresholdGreen);
            p.Add("@ThresholdAmber", request.ThresholdAmber);
            p.Add("@ThresholdRed", request.ThresholdRed);
            p.Add("@ThresholdDirection", request.ThresholdDirection);
            p.Add("@SubmitterGuidance", request.SubmitterGuidance);
            p.Add("@AssignmentId", dbType: System.Data.DbType.Int32,
                  direction: System.Data.ParameterDirection.Output);

            await conn.ExecuteAsync("App.usp_AssignKpi", p,
                commandType: System.Data.CommandType.StoredProcedure);

            var newId = p.Get<int>("@AssignmentId");

            var created = await conn.QuerySingleAsync<KpiAssignmentDto>(@"
                SELECT AssignmentId, ExternalId, KpiCode, KpiName, Category, AccountCode, AccountName,
                       SiteCode, SiteName, CAST(IsAccountWide AS bit) AS IsAccountWide, PeriodLabel, IsRequired,
                       TargetValue, ThresholdGreen, ThresholdAmber, ThresholdRed,
                       EffectiveThresholdDirection, IsActive
                FROM App.vKpiAssignments
                WHERE AssignmentId = @Id",
                new { Id = newId });

            return Results.Created($"/kpi/assignments/{newId}", created);
        }).RequireAuthorization();

        return app;
    }
}
