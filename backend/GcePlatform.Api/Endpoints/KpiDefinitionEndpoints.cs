using System.Security.Claims;
using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Models;
using GcePlatform.Api.Services;

namespace GcePlatform.Api.Endpoints;

public static class KpiDefinitionEndpoints
{
    public static WebApplication MapKpiDefinitionEndpoints(this WebApplication app)
    {
        // GET /kpi/definitions
        app.MapGet("/kpi/definitions", async (DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var items = await conn.QueryAsync<KpiDefinitionDto>(@"
                SELECT
                    KpiId,
                    ExternalId,
                    KpiCode,
                    KpiName,
                    KpiDescription,
                    Category,
                    Unit,
                    DataType,
                    AllowMultiValue,
                    CollectionType,
                    ThresholdDirection,
                    IsActive,
                    AssignmentCount,
                    DropDownOptionsRaw,
                    TagsRaw
                FROM App.vKpiDefinitions
                ORDER BY KpiCode");

            var list = items.ToList();
            return Results.Ok(new ApiList<KpiDefinitionDto>(list, list.Count));
        }).RequireAuthorization();

        // GET /kpi/definitions/{id}
        app.MapGet("/kpi/definitions/{id:int}", async (int id, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var item = await conn.QuerySingleOrDefaultAsync<KpiDefinitionDto>(@"
                SELECT
                    KpiId,
                    ExternalId,
                    KpiCode,
                    KpiName,
                    KpiDescription,
                    Category,
                    Unit,
                    DataType,
                    AllowMultiValue,
                    CollectionType,
                    ThresholdDirection,
                    IsActive,
                    AssignmentCount,
                    DropDownOptionsRaw,
                    TagsRaw
                FROM App.vKpiDefinitions
                WHERE KpiId = @Id",
                new { Id = id });

            return item is null
                ? Results.NotFound(new ApiError("KPI_NOT_FOUND", $"KPI definition {id} not found."))
                : Results.Ok(item);
        }).RequireAuthorization();

        // PATCH /kpi/definitions/{id}
        app.MapMethods("/kpi/definitions/{id:int}", new[] { "PATCH" },
            async (ClaimsPrincipal user, int id, UpdateKpiDefinitionRequest request, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.KpiManage))
                return Results.Forbid();

            // Fetch current record to get KpiCode (immutable) and IsActive (preserve)
            var current = await conn.QuerySingleOrDefaultAsync<KpiDefinitionDto>(@"
                SELECT KpiId, ExternalId, KpiCode, KpiName, KpiDescription, Category, Unit,
                       DataType, AllowMultiValue, CollectionType, ThresholdDirection,
                       IsActive, AssignmentCount, DropDownOptionsRaw, TagsRaw
                FROM App.vKpiDefinitions
                WHERE KpiId = @Id",
                new { Id = id });

            if (current is null)
                return Results.NotFound(new ApiError("KPI_NOT_FOUND", $"KPI definition {id} not found."));

            string? optionsPipe = request.DropDownOptions is null
                ? null
                : string.Join("||", request.DropDownOptions.Where(o => !string.IsNullOrWhiteSpace(o)));

            var p = new DynamicParameters();
            p.Add("@KpiCode",             current.KpiCode);
            p.Add("@KpiName",             request.KpiName);
            p.Add("@KpiDescription",      request.KpiDescription);
            p.Add("@Category",            request.Category);
            p.Add("@Unit",                request.Unit);
            p.Add("@DataType",            request.DataType);
            p.Add("@AllowMultiValue",     request.AllowMultiValue);
            p.Add("@CollectionType",      request.CollectionType);
            p.Add("@ThresholdDirection",  request.ThresholdDirection);
            p.Add("@DropDownOptionsPipe", optionsPipe);
            p.Add("@IsActive",            current.IsActive);
            p.Add("@KPIID", dbType: System.Data.DbType.Int32,
                  direction: System.Data.ParameterDirection.Output);

            await conn.ExecuteAsync("App.usp_UpsertKpiDefinition", p,
                commandType: System.Data.CommandType.StoredProcedure);

            // Save tags if provided
            if (request.TagIds is not null)
            {
                var tagIdsCsv = string.Join(",", request.TagIds);
                await conn.ExecuteAsync("App.usp_SetKpiTags",
                    new { KpiId = id, TagIds = tagIdsCsv },
                    commandType: System.Data.CommandType.StoredProcedure);
            }

            var updated = await conn.QuerySingleAsync<KpiDefinitionDto>(@"
                SELECT KpiId, ExternalId, KpiCode, KpiName, KpiDescription, Category, Unit,
                       DataType, AllowMultiValue, CollectionType, ThresholdDirection,
                       IsActive, AssignmentCount, DropDownOptionsRaw, TagsRaw
                FROM App.vKpiDefinitions
                WHERE KpiId = @Id",
                new { Id = id });

            return Results.Ok(updated);
        }).RequireAuthorization();

        // PATCH /kpi/definitions/{id}/status
        app.MapMethods("/kpi/definitions/{id:int}/status", new[] { "PATCH" },
            async (ClaimsPrincipal user, int id, SetActiveRequest body, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.KpiManage))
                return Results.Forbid();
            var item = await conn.QuerySingleOrDefaultAsync<KpiDefinitionDto>(@"
                SELECT
                    KpiId,
                    ExternalId,
                    KpiCode,
                    KpiName,
                    KpiDescription,
                    Category,
                    Unit,
                    DataType,
                    AllowMultiValue,
                    CollectionType,
                    ThresholdDirection,
                    IsActive,
                    AssignmentCount,
                    DropDownOptionsRaw,
                    TagsRaw
                FROM App.vKpiDefinitions
                WHERE KpiId = @Id",
                new { Id = id });

            if (item is null)
                return Results.NotFound(new ApiError("KPI_NOT_FOUND", $"KPI definition {id} not found."));

            await conn.ExecuteAsync("App.usp_SetKpiDefinitionActive",
                new { KPIID = id, body.IsActive },
                commandType: System.Data.CommandType.StoredProcedure);

            return Results.NoContent();
        }).RequireAuthorization();

        // POST /kpi/definitions
        app.MapPost("/kpi/definitions", async (ClaimsPrincipal user, CreateKpiDefinitionRequest request, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.KpiManage))
                return Results.Forbid();

            // Convert option list to pipe-delimited string expected by the stored proc
            string? optionsPipe = request.DropDownOptions is null
                ? null
                : string.Join("||", request.DropDownOptions.Where(o => !string.IsNullOrWhiteSpace(o)));

            var p = new DynamicParameters();
            p.Add("@KpiCode",             request.KpiCode.ToUpperInvariant());
            p.Add("@KpiName",             request.KpiName);
            p.Add("@KpiDescription",      request.KpiDescription);
            p.Add("@Category",            request.Category);
            p.Add("@Unit",                request.Unit);
            p.Add("@DataType",            request.DataType);
            p.Add("@AllowMultiValue",     request.AllowMultiValue);
            p.Add("@CollectionType",      request.CollectionType);
            p.Add("@ThresholdDirection",  request.ThresholdDirection);
            p.Add("@DropDownOptionsPipe", optionsPipe);
            p.Add("@IsActive",            true);
            p.Add("@KPIID", dbType: System.Data.DbType.Int32,
                  direction: System.Data.ParameterDirection.Output);

            await conn.ExecuteAsync("App.usp_UpsertKpiDefinition", p,
                commandType: System.Data.CommandType.StoredProcedure);

            var newId = p.Get<int>("@KPIID");

            // Save tags if provided
            if (request.TagIds is not null && request.TagIds.Any())
            {
                var tagIdsCsv = string.Join(",", request.TagIds);
                await conn.ExecuteAsync("App.usp_SetKpiTags",
                    new { KpiId = newId, TagIds = tagIdsCsv },
                    commandType: System.Data.CommandType.StoredProcedure);
            }

            var created = await conn.QuerySingleAsync<KpiDefinitionDto>(@"
                SELECT KpiId, ExternalId, KpiCode, KpiName, KpiDescription, Category, Unit,
                       DataType, AllowMultiValue, CollectionType, ThresholdDirection,
                       IsActive, AssignmentCount, DropDownOptionsRaw, TagsRaw
                FROM App.vKpiDefinitions
                WHERE KpiId = @Id",
                new { Id = newId });

            return Results.Created($"/kpi/definitions/{newId}", created);
        }).RequireAuthorization();

        return app;
    }
}
