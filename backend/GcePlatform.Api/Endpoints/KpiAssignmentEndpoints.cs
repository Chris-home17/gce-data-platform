using System.Security.Claims;
using System.Text.Json;
using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Helpers;
using GcePlatform.Api.Models;
using GcePlatform.Api.Services;

namespace GcePlatform.Api.Endpoints;

public static class KpiAssignmentEndpoints
{
    // Shared column list for App.vKpiAssignmentTemplates — kept in one place so
    // POST/PATCH/status re-fetches stay in lockstep with the list endpoint.
    private const string TemplateColumns = @"
        AssignmentTemplateId,
        ExternalId,
        KpiCode,
        KpiName,
        CustomKpiName,
        CustomKpiDescription,
        EffectiveKpiName,
        EffectiveKpiDescription,
        CategoryId,
        CategoryCode,
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
        KpiPackageName,
        AssignmentGroupName,
        KpiWeight,
        ScoringMode,
        BandPointsGreen,
        BandPointsAmber,
        BandPointsRed,
        BooleanYesPoints,
        BooleanNoPoints,
        MultiSelectScoreRule,
        CAST(PenaliseMissingOnScore AS bit) AS PenaliseMissingOnScore,
        OptionPointsRaw,
        CategoryWeightSnapshot,
        ValidationMinValue,
        ValidationMaxValue,
        ValidationPrecision,
        ValidationRegex,
        ValidationMessage";

    public static WebApplication MapKpiAssignmentEndpoints(this WebApplication app)
    {
        app.MapGet("/kpi/assignment-groups", async (ClaimsPrincipal user, int? accountId, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            IEnumerable<KpiAssignmentGroupDto> items;
            if (await platformAuth.HasPermissionAsync(user, conn, Permissions.SuperAdmin))
            {
                items = await conn.QueryAsync<KpiAssignmentGroupDto>(@"
                    SELECT AccountId, AccountCode, AccountName, GroupName
                    FROM App.vAssignmentGroups
                    WHERE (@AccountId IS NULL OR AccountId = @AccountId)
                    ORDER BY AccountCode, GroupName",
                    new { AccountId = accountId });
            }
            else
            {
                var currentUserId = await AccessScope.GetCurrentUserIdAsync(user, conn);
                if (currentUserId is null)
                    return Results.Ok(new ApiList<KpiAssignmentGroupDto>(new List<KpiAssignmentGroupDto>(), 0));

                items = await conn.QueryAsync<KpiAssignmentGroupDto>($@"
                    {AccessScope.AccessibleAccountsCte}
                    SELECT AccountId, AccountCode, AccountName, GroupName
                    FROM App.vAssignmentGroups
                    WHERE (@AccountId IS NULL OR AccountId = @AccountId)
                      AND AccountId IN (SELECT AccountId FROM AccessibleAccounts)
                    ORDER BY AccountCode, GroupName",
                    new { AccountId = accountId, UserId = currentUserId.Value });
            }

            var list = items.ToList();
            return Results.Ok(new ApiList<KpiAssignmentGroupDto>(list, list.Count));
        }).RequireAuthorization();

        app.MapGet("/kpi/assignment-templates", async (ClaimsPrincipal user, int? accountId, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            const string columns = @"
                AssignmentTemplateId,
                ExternalId,
                KpiCode,
                KpiName,
                CustomKpiName,
                CustomKpiDescription,
                EffectiveKpiName,
                EffectiveKpiDescription,
                CategoryId,
                CategoryCode,
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
                KpiPackageName,
                AssignmentGroupName,
                KpiWeight,
                ScoringMode,
                BandPointsGreen,
                BandPointsAmber,
                BandPointsRed,
                BooleanYesPoints,
                BooleanNoPoints,
                MultiSelectScoreRule,
                CAST(PenaliseMissingOnScore AS bit) AS PenaliseMissingOnScore,
                OptionPointsRaw,
                CategoryWeightSnapshot,
                ValidationMinValue,
                ValidationMaxValue,
                ValidationPrecision,
                ValidationRegex,
                ValidationMessage";

            IEnumerable<KpiAssignmentTemplateDto> items;
            if (await platformAuth.HasPermissionAsync(user, conn, Permissions.SuperAdmin))
            {
                items = await conn.QueryAsync<KpiAssignmentTemplateDto>($@"
                    SELECT {columns}
                    FROM App.vKpiAssignmentTemplates
                    WHERE (@AccountId IS NULL OR AccountId = @AccountId)
                    ORDER BY ScheduleName, AccountCode, KpiCode",
                    new { AccountId = accountId });
            }
            else
            {
                var currentUserId = await AccessScope.GetCurrentUserIdAsync(user, conn);
                if (currentUserId is null)
                    return Results.Ok(new ApiList<KpiAssignmentTemplateDto>(new List<KpiAssignmentTemplateDto>(), 0));

                items = await conn.QueryAsync<KpiAssignmentTemplateDto>($@"
                    {AccessScope.AccessibleAccountsCte}
                    SELECT {columns}
                    FROM App.vKpiAssignmentTemplates
                    WHERE (@AccountId IS NULL OR AccountId = @AccountId)
                      AND AccountId IN (SELECT AccountId FROM AccessibleAccounts)
                    ORDER BY ScheduleName, AccountCode, KpiCode",
                    new { AccountId = accountId, UserId = currentUserId.Value });
            }

            var list = items.ToList();
            return Results.Ok(new ApiList<KpiAssignmentTemplateDto>(list, list.Count));
        }).RequireAuthorization();

        app.MapPost("/kpi/assignment-templates", async (ClaimsPrincipal user, CreateKpiAssignmentTemplateRequest request, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasAnyPermissionAsync(user, conn, Permissions.KpiAssign, Permissions.KpiAdmin))
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
            p.Add("@AssignmentGroupName", request.AssignmentGroupName);
            p.Add("@KpiWeight", request.KpiWeight);
            p.Add("@ScoringMode", request.ScoringMode);
            p.Add("@BandPointsGreen", request.BandPointsGreen);
            p.Add("@BandPointsAmber", request.BandPointsAmber);
            p.Add("@BandPointsRed", request.BandPointsRed);
            p.Add("@BooleanYesPoints", request.BooleanYesPoints);
            p.Add("@BooleanNoPoints", request.BooleanNoPoints);
            p.Add("@MultiSelectScoreRule", request.MultiSelectScoreRule);
            p.Add("@PenaliseMissingOnScore", request.PenaliseMissingOnScore);
            p.Add("@OptionPoints", SerializeOptionPoints(request.OptionPoints));
            p.Add("@ValidationMinValue", request.ValidationMinValue);
            p.Add("@ValidationMaxValue", request.ValidationMaxValue);
            p.Add("@ValidationPrecision", request.ValidationPrecision);
            p.Add("@ValidationRegex", request.ValidationRegex);
            p.Add("@ValidationMessage", request.ValidationMessage);
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
                SELECT " + TemplateColumns + @"
                FROM App.vKpiAssignmentTemplates
                WHERE AssignmentTemplateId = @Id",
                new { Id = newId });

            return Results.Created($"/kpi/assignment-templates/{newId}", created);
        }).RequireAuthorization();

        // PATCH /kpi/assignment-templates/{id}
        // KPI / schedule / account / scope / group name are part of the natural key
        // (immutable). Mutable fields update the template, then we cascade to every
        // unsubmitted assignment that references it. Submitted rows already carry
        // their per-submission threshold snapshot, so RAG history stays frozen.
        app.MapMethods("/kpi/assignment-templates/{id:int}", new[] { "PATCH" },
            async (ClaimsPrincipal user, int id, UpdateKpiAssignmentTemplateRequest request, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasAnyPermissionAsync(user, conn, Permissions.KpiAssign, Permissions.KpiAdmin))
                return Results.Forbid();

            // Resolve the immutable natural-key fields the upsert proc needs.
            // The view exposes the org-unit code as SiteCode and doesn't carry
            // OrgUnitType — templates always target Sites, so we hardcode it.
            var current = await conn.QuerySingleOrDefaultAsync<(string KpiCode, int PeriodScheduleId, string AccountCode, string? SiteCode, string? AssignmentGroupName)>(@"
                SELECT t.KpiCode, t.PeriodScheduleId, t.AccountCode, t.SiteCode, t.AssignmentGroupName
                FROM App.vKpiAssignmentTemplates AS t
                WHERE t.AssignmentTemplateId = @Id",
                new { Id = id });

            if (current.KpiCode is null)
                return Results.NotFound(new ApiError("TEMPLATE_NOT_FOUND", $"Assignment template {id} not found."));

            var p = new DynamicParameters();
            p.Add("@KpiCode", current.KpiCode);
            p.Add("@PeriodScheduleID", current.PeriodScheduleId);
            p.Add("@AccountCode", current.AccountCode);
            p.Add("@OrgUnitCode", current.SiteCode);
            p.Add("@OrgUnitType", "Site");
            p.Add("@IsRequired", request.IsRequired);
            p.Add("@TargetValue", request.TargetValue);
            p.Add("@ThresholdGreen", request.ThresholdGreen);
            p.Add("@ThresholdAmber", request.ThresholdAmber);
            p.Add("@ThresholdRed", request.ThresholdRed);
            p.Add("@ThresholdDirection", request.ThresholdDirection);
            p.Add("@SubmitterGuidance", request.SubmitterGuidance);
            p.Add("@CustomKpiName", request.CustomKpiName);
            p.Add("@CustomKpiDescription", request.CustomKpiDescription);
            p.Add("@AssignmentGroupName", current.AssignmentGroupName);
            p.Add("@KpiWeight", request.KpiWeight);
            p.Add("@ScoringMode", request.ScoringMode);
            p.Add("@BandPointsGreen", request.BandPointsGreen);
            p.Add("@BandPointsAmber", request.BandPointsAmber);
            p.Add("@BandPointsRed", request.BandPointsRed);
            p.Add("@BooleanYesPoints", request.BooleanYesPoints);
            p.Add("@BooleanNoPoints", request.BooleanNoPoints);
            p.Add("@MultiSelectScoreRule", request.MultiSelectScoreRule);
            p.Add("@PenaliseMissingOnScore", request.PenaliseMissingOnScore);
            p.Add("@OptionPoints", SerializeOptionPoints(request.OptionPoints));
            p.Add("@ValidationMinValue", request.ValidationMinValue);
            p.Add("@ValidationMaxValue", request.ValidationMaxValue);
            p.Add("@ValidationPrecision", request.ValidationPrecision);
            p.Add("@ValidationRegex", request.ValidationRegex);
            p.Add("@ValidationMessage", request.ValidationMessage);
            p.Add("@AssignmentTemplateID", dbType: System.Data.DbType.Int32,
                  direction: System.Data.ParameterDirection.Output);

            await conn.ExecuteAsync("App.usp_UpsertKpiAssignmentTemplate", p,
                commandType: System.Data.CommandType.StoredProcedure);

            await conn.ExecuteAsync("App.usp_CascadeAssignmentTemplateThresholds",
                new { AssignmentTemplateID = id },
                commandType: System.Data.CommandType.StoredProcedure);

            var updated = await conn.QuerySingleAsync<KpiAssignmentTemplateDto>(@"
                SELECT " + TemplateColumns + @"
                FROM App.vKpiAssignmentTemplates
                WHERE AssignmentTemplateId = @Id",
                new { Id = id });

            return Results.Ok(updated);
        }).RequireAuthorization();

        app.MapPost("/kpi/assignment-templates/batch",
            async (ClaimsPrincipal user, BatchCreateKpiAssignmentTemplatesRequest request, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasAnyPermissionAsync(user, conn, Permissions.KpiAssign, Permissions.KpiAdmin))
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

            // Bound the work a single request can do: each SP call is its own
            // atomic unit, so a runaway batch would otherwise hold the connection
            // indefinitely and can't be cleanly rolled back as a set.
            const int MaxBatchOperations = 500;
            var totalOps = distinctItems.Count * orgUnitCodes.Count;
            if (totalOps > MaxBatchOperations)
                return Results.BadRequest(new ApiError(
                    "BATCH_TOO_LARGE",
                    $"This batch would create {totalOps} templates; the per-request cap is {MaxBatchOperations}. Split it into smaller requests."));

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
                        p.Add("@AssignmentGroupName",  request.AssignmentGroupName);
                        p.Add("@KpiWeight",            item.KpiWeight);
                        p.Add("@ScoringMode",          item.ScoringMode);
                        p.Add("@BandPointsGreen",      item.BandPointsGreen);
                        p.Add("@BandPointsAmber",      item.BandPointsAmber);
                        p.Add("@BandPointsRed",        item.BandPointsRed);
                        p.Add("@BooleanYesPoints",     item.BooleanYesPoints);
                        p.Add("@BooleanNoPoints",      item.BooleanNoPoints);
                        p.Add("@MultiSelectScoreRule", item.MultiSelectScoreRule);
                        p.Add("@PenaliseMissingOnScore", item.PenaliseMissingOnScore);
                        p.Add("@OptionPoints", SerializeOptionPoints(item.OptionPoints));
                        p.Add("@ValidationMinValue", item.ValidationMinValue);
                        p.Add("@ValidationMaxValue", item.ValidationMaxValue);
                        p.Add("@ValidationPrecision", item.ValidationPrecision);
                        p.Add("@ValidationRegex", item.ValidationRegex);
                        p.Add("@ValidationMessage", item.ValidationMessage);
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

            if (!await platformAuth.HasAnyPermissionAsync(user, conn, Permissions.KpiAssign, Permissions.KpiAdmin))
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

            if (!await platformAuth.HasAnyPermissionAsync(user, conn, Permissions.KpiAssign, Permissions.KpiAdmin))
                return Results.Forbid();
            var item = await conn.QuerySingleOrDefaultAsync<KpiAssignmentTemplateDto>(@"
                SELECT " + TemplateColumns + @"
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
        app.MapGet("/kpi/effective-assignments", async (ClaimsPrincipal user, int? periodId, int? accountId, string? siteCode, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            const string columns = @"
                AssignmentId,
                ExternalId,
                KpiCode,
                KpiName,
                EffectiveKpiName,
                EffectiveKpiDescription,
                CategoryId,
                CategoryCode,
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
                IsActive";

            IEnumerable<EffectiveKpiAssignmentDto> items;
            if (await platformAuth.HasPermissionAsync(user, conn, Permissions.SuperAdmin))
            {
                items = await conn.QueryAsync<EffectiveKpiAssignmentDto>($@"
                    SELECT {columns}
                    FROM App.vEffectiveKpiAssignments
                    WHERE (@PeriodId  IS NULL OR PeriodId   = @PeriodId)
                      AND (@AccountId IS NULL OR AccountId  = @AccountId)
                      AND (@SiteCode  IS NULL OR SiteCode   = @SiteCode)
                      AND IsActive = 1
                    ORDER BY AccountCode, SiteCode, KpiCode",
                    new { PeriodId = periodId, AccountId = accountId, SiteCode = siteCode });
            }
            else
            {
                var currentUserId = await AccessScope.GetCurrentUserIdAsync(user, conn);
                if (currentUserId is null)
                    return Results.Ok(new ApiList<EffectiveKpiAssignmentDto>(new List<EffectiveKpiAssignmentDto>(), 0));

                items = await conn.QueryAsync<EffectiveKpiAssignmentDto>($@"
                    {AccessScope.AccessibleAccountsCte}
                    SELECT {columns}
                    FROM App.vEffectiveKpiAssignments
                    WHERE (@PeriodId  IS NULL OR PeriodId   = @PeriodId)
                      AND (@AccountId IS NULL OR AccountId  = @AccountId)
                      AND (@SiteCode  IS NULL OR SiteCode   = @SiteCode)
                      AND AccountId IN (SELECT AccountId FROM AccessibleAccounts)
                      AND IsActive = 1
                    ORDER BY AccountCode, SiteCode, KpiCode",
                    new { PeriodId = periodId, AccountId = accountId, SiteCode = siteCode, UserId = currentUserId.Value });
            }

            var list = items.ToList();
            return Results.Ok(new ApiList<EffectiveKpiAssignmentDto>(list, list.Count));
        }).RequireAuthorization();

        // GET /kpi/assignments?periodId=&accountId=&siteCode=
        app.MapGet("/kpi/assignments", async (ClaimsPrincipal user, int? periodId, int? accountId, string? siteCode, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            const string columns = @"
                AssignmentId,
                ExternalId,
                KpiCode,
                KpiName,
                CategoryId,
                CategoryCode,
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
                IsActive,
                AssignmentGroupName";

            IEnumerable<KpiAssignmentDto> items;
            if (await platformAuth.HasPermissionAsync(user, conn, Permissions.SuperAdmin))
            {
                items = await conn.QueryAsync<KpiAssignmentDto>($@"
                    SELECT {columns}
                    FROM App.vKpiAssignments
                    WHERE (@PeriodId IS NULL OR PeriodId = @PeriodId)
                      AND (@AccountId IS NULL OR AccountId = @AccountId)
                      AND (@SiteCode IS NULL OR SiteCode = @SiteCode)
                    ORDER BY AccountCode, KpiCode",
                    new { PeriodId = periodId, AccountId = accountId, SiteCode = siteCode });
            }
            else
            {
                var currentUserId = await AccessScope.GetCurrentUserIdAsync(user, conn);
                if (currentUserId is null)
                    return Results.Ok(new ApiList<KpiAssignmentDto>(new List<KpiAssignmentDto>(), 0));

                items = await conn.QueryAsync<KpiAssignmentDto>($@"
                    {AccessScope.AccessibleAccountsCte}
                    SELECT {columns}
                    FROM App.vKpiAssignments
                    WHERE (@PeriodId IS NULL OR PeriodId = @PeriodId)
                      AND (@AccountId IS NULL OR AccountId = @AccountId)
                      AND (@SiteCode IS NULL OR SiteCode = @SiteCode)
                      AND AccountId IN (SELECT AccountId FROM AccessibleAccounts)
                    ORDER BY AccountCode, KpiCode",
                    new { PeriodId = periodId, AccountId = accountId, SiteCode = siteCode, UserId = currentUserId.Value });
            }

            var list = items.ToList();
            return Results.Ok(new ApiList<KpiAssignmentDto>(list, list.Count));
        }).RequireAuthorization();

        // GET /kpi/assignments/{id} — scoped to caller's accessible accounts.
        app.MapGet("/kpi/assignments/{id:int}", async (ClaimsPrincipal user, int id, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            const string columns = @"
                AssignmentId,
                ExternalId,
                KpiCode,
                KpiName,
                CategoryId,
                CategoryCode,
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
                IsActive,
                AssignmentGroupName";

            KpiAssignmentDto? item;
            if (await platformAuth.HasPermissionAsync(user, conn, Permissions.SuperAdmin))
            {
                item = await conn.QuerySingleOrDefaultAsync<KpiAssignmentDto>($@"
                    SELECT {columns}
                    FROM App.vKpiAssignments
                    WHERE AssignmentId = @Id",
                    new { Id = id });
            }
            else
            {
                var currentUserId = await AccessScope.GetCurrentUserIdAsync(user, conn);
                if (currentUserId is null)
                    return Results.NotFound(new ApiError("ASSIGNMENT_NOT_FOUND", $"Assignment {id} not found."));

                item = await conn.QuerySingleOrDefaultAsync<KpiAssignmentDto>($@"
                    {AccessScope.AccessibleAccountsCte}
                    SELECT {columns}
                    FROM App.vKpiAssignments
                    WHERE AssignmentId = @Id
                      AND AccountId IN (SELECT AccountId FROM AccessibleAccounts)",
                    new { Id = id, UserId = currentUserId.Value });
            }

            return item is null
                ? Results.NotFound(new ApiError("ASSIGNMENT_NOT_FOUND", $"Assignment {id} not found."))
                : Results.Ok(item);
        }).RequireAuthorization();

        // PATCH /kpi/assignments/{id}/status
        app.MapMethods("/kpi/assignments/{id:int}/status", new[] { "PATCH" },
            async (ClaimsPrincipal user, int id, SetActiveRequest body, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasAnyPermissionAsync(user, conn, Permissions.KpiAssign, Permissions.KpiAdmin))
                return Results.Forbid();
            var item = await conn.QuerySingleOrDefaultAsync<KpiAssignmentDto>(@"
                SELECT
                    AssignmentId,
                    ExternalId,
                    KpiCode,
                    KpiName,
                    CategoryId,
                    CategoryCode,
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
                    IsActive,
                    AssignmentGroupName
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

            if (!await platformAuth.HasAnyPermissionAsync(user, conn, Permissions.KpiAssign, Permissions.KpiAdmin))
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
            p.Add("@AssignmentGroupName", request.AssignmentGroupName);
            p.Add("@AssignmentId", dbType: System.Data.DbType.Int32,
                  direction: System.Data.ParameterDirection.Output);

            await conn.ExecuteAsync("App.usp_AssignKpi", p,
                commandType: System.Data.CommandType.StoredProcedure);

            var newId = p.Get<int>("@AssignmentId");

            var created = await conn.QuerySingleAsync<KpiAssignmentDto>(@"
                SELECT AssignmentId, ExternalId, KpiCode, KpiName,
                       CategoryId, CategoryCode, Category,
                       AccountCode, AccountName,
                       SiteCode, SiteName, CAST(IsAccountWide AS bit) AS IsAccountWide, DataType,
                       PeriodId, PeriodScheduleId, ScheduleName, PeriodLabel, IsRequired,
                       TargetValue, ThresholdGreen, ThresholdAmber, ThresholdRed,
                       EffectiveThresholdDirection, IsActive, AssignmentGroupName
                FROM App.vKpiAssignments
                WHERE AssignmentId = @Id",
                new { Id = newId });

            return Results.Created($"/kpi/assignments/{newId}", created);
        }).RequireAuthorization();

        return app;
    }

    /// <summary>
    /// Serialise a list of DropDown option points into the JSON shape the
    /// stored proc expects. Returns NULL when the caller didn't supply
    /// options — the proc treats NULL as "leave existing options alone".
    /// </summary>
    private static string? SerializeOptionPoints(IEnumerable<DropDownOptionPointsDto>? options)
    {
        if (options is null) return null;
        var list = options.ToList();
        if (list.Count == 0) return "[]";
        return JsonSerializer.Serialize(list.Select(o => new
        {
            value     = o.OptionValue,
            points    = o.Points,
            sortOrder = o.SortOrder,
        }));
    }
}
