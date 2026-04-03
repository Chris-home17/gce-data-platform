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
                FROM KPI.AssignmentTemplate
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
            var rows = await conn.ExecuteAsync(@"
                UPDATE KPI.AssignmentTemplate
                SET IsActive = @IsActive,
                    ModifiedOnUtc = SYSUTCDATETIME(),
                    ModifiedBy = SESSION_USER
                WHERE AssignmentTemplateId = @Id",
                new { Id = id, body.IsActive });

            if (rows == 0)
                return Results.NotFound(new ApiError("ASSIGNMENT_TEMPLATE_NOT_FOUND", $"Assignment template {id} not found."));

            if (body.IsActive)
            {
                await conn.ExecuteAsync("App.usp_MaterializeKpiAssignmentTemplates",
                    new { AssignmentTemplateID = id },
                    commandType: System.Data.CommandType.StoredProcedure);
            }

            return Results.NoContent();
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
            var rows = await conn.ExecuteAsync(
                "UPDATE KPI.Assignment SET IsActive = @IsActive WHERE AssignmentId = @Id",
                new { Id = id, body.IsActive });
            return rows == 0
                ? Results.NotFound(new ApiError("ASSIGNMENT_NOT_FOUND", $"Assignment {id} not found."))
                : Results.NoContent();
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
