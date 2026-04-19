using System.Security.Claims;
using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Models;
using GcePlatform.Api.Services;

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
                    DataType,
                    IsRequired,
                    TargetValue,
                    ThresholdGreen,
                    ThresholdAmber,
                    ThresholdRed,
                    EffectiveThresholdDirection,
                    IsActive,
                    GeneratedAssignmentCount,
                    KpiPackageId,
                    KpiPackageName
                FROM App.vKpiAssignmentTemplates
                WHERE (@AccountId IS NULL OR AccountId = @AccountId)
                ORDER BY ScheduleName, AccountCode, KpiCode",
                new { AccountId = accountId });

            var list = items.ToList();
            return Results.Ok(new ApiList<KpiAssignmentTemplateDto>(list, list.Count));
        }).RequireAuthorization();

        app.MapPost("/kpi/assignment-templates", async (ClaimsPrincipal user, CreateKpiAssignmentTemplateRequest request, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.KpiManage))
                return Results.Forbid();

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
                    DataType,
                    IsRequired,
                    TargetValue,
                    ThresholdGreen,
                    ThresholdAmber,
                    ThresholdRed,
                    EffectiveThresholdDirection,
                    IsActive,
                    GeneratedAssignmentCount,
                    KpiPackageId,
                    KpiPackageName
                FROM App.vKpiAssignmentTemplates
                WHERE AssignmentTemplateId = @Id",
                new { Id = newId });

            return Results.Created($"/kpi/assignment-templates/{newId}", created);
        }).RequireAuthorization();

        app.MapPost("/kpi/assignment-templates/batch",
            async (ClaimsPrincipal user, BatchCreateKpiAssignmentTemplatesRequest request, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.KpiManage))
                return Results.Forbid();

            var items = request.Items?.ToList();
            if (items is null || items.Count == 0)
                return Results.BadRequest(new ApiError("BATCH_EMPTY", "No KPI items provided."));

            // De-dupe within the request itself (first occurrence wins)
            var distinctItems = items
                .GroupBy(i => i.KpiCode, StringComparer.OrdinalIgnoreCase)
                .Select(g => g.First())
                .ToList();

            // Resolve the list of org unit codes to iterate over
            var orgUnitCodes = (request.OrgUnitCodes?.ToList() is { Count: > 0 } multi)
                ? multi
                : request.OrgUnitCode is not null
                    ? new List<string> { request.OrgUnitCode }
                    : new List<string> { (string?)null! };  // null = account-wide

            var createdIds = new List<int>();
            var skippedKpiCodes = new List<string>();
            var errors = new List<string>();

            foreach (var orgUnitCode in orgUnitCodes)
            {
                foreach (var item in distinctItems)
                {
                    try
                    {
                        var p = new DynamicParameters();
                        p.Add("@KpiCode",              item.KpiCode);
                        p.Add("@PeriodScheduleID",     request.PeriodScheduleId);
                        p.Add("@AccountCode",          request.AccountCode);
                        p.Add("@OrgUnitCode",          orgUnitCode);
                        p.Add("@OrgUnitType",          request.OrgUnitType);
                        p.Add("@IsRequired",           item.IsRequired);
                        p.Add("@TargetValue",          item.TargetValue);
                        p.Add("@ThresholdGreen",       item.ThresholdGreen);
                        p.Add("@ThresholdAmber",       item.ThresholdAmber);
                        p.Add("@ThresholdRed",         item.ThresholdRed);
                        p.Add("@ThresholdDirection",   item.ThresholdDirection);
                        p.Add("@SubmitterGuidance",    item.SubmitterGuidance);
                        p.Add("@CustomKpiName",        item.CustomKpiName);
                        p.Add("@CustomKpiDescription", item.CustomKpiDescription);
                        p.Add("@KpiPackageId",         item.KpiPackageId);
                        p.Add("@AssignmentTemplateID", dbType: System.Data.DbType.Int32,
                              direction: System.Data.ParameterDirection.Output);

                        await conn.ExecuteAsync("App.usp_UpsertKpiAssignmentTemplate", p,
                            commandType: System.Data.CommandType.StoredProcedure);

                        createdIds.Add(p.Get<int>("@AssignmentTemplateID"));
                    }
                    catch (Microsoft.Data.SqlClient.SqlException ex) when (ex.Number is 2627 or 2601)
                    {
                        var key = orgUnitCode is not null ? $"{item.KpiCode}@{orgUnitCode}" : item.KpiCode;
                        if (!skippedKpiCodes.Contains(key))
                            skippedKpiCodes.Add(key);
                    }
                    catch (Exception ex)
                    {
                        errors.Add($"{item.KpiCode}: {ex.Message}");
                    }
                }
            }

            if (request.MaterializeNow && createdIds.Count > 0)
            {
                foreach (var id in createdIds)
                {
                    await conn.ExecuteAsync("App.usp_MaterializeKpiAssignmentTemplates",
                        new { AssignmentTemplateID = id },
                        commandType: System.Data.CommandType.StoredProcedure);
                }
            }

            if (errors.Count > 0 && createdIds.Count == 0 && skippedKpiCodes.Count == 0)
                return Results.BadRequest(new ApiError("BATCH_FAILED", string.Join("; ", errors)));

            return Results.Ok(new BatchCreateKpiAssignmentTemplatesResponse(
                CreatedCount:    createdIds.Count,
                SkippedCount:    skippedKpiCodes.Count,
                SkippedKpiCodes: skippedKpiCodes,
                Errors:          errors));
        }).RequireAuthorization();

        app.MapPost("/kpi/assignment-templates/{id:int}/materialize", async (ClaimsPrincipal user, int id, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.KpiManage))
                return Results.Forbid();

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
            async (ClaimsPrincipal user, int id, SetActiveRequest body, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.KpiManage))
                return Results.Forbid();
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
                    DataType,
                    IsRequired,
                    TargetValue,
                    ThresholdGreen,
                    ThresholdAmber,
                    ThresholdRed,
                    EffectiveThresholdDirection,
                    IsActive,
                    GeneratedAssignmentCount,
                    KpiPackageId,
                    KpiPackageName
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
                    DataType,
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
                    DataType,
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
            async (ClaimsPrincipal user, int id, SetActiveRequest body, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.KpiManage))
                return Results.Forbid();
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
                    DataType,
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
        app.MapPost("/kpi/assignments", async (ClaimsPrincipal user, CreateKpiAssignmentRequest request, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.KpiManage))
                return Results.Forbid();

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
                       SiteCode, SiteName, CAST(IsAccountWide AS bit) AS IsAccountWide, DataType, PeriodLabel, IsRequired,
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
