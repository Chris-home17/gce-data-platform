using System.Security.Claims;
using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Models;
using GcePlatform.Api.Services;

namespace GcePlatform.Api.Endpoints;

public static class KpiPackageEndpoints
{
    public static WebApplication MapKpiPackageEndpoints(this WebApplication app)
    {
        // GET /kpi/packages
        app.MapGet("/kpi/packages", async (DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var items = await conn.QueryAsync<KpiPackageDto>(@"
                SELECT KpiPackageId, PackageCode, PackageName, IsActive, KpiCount, TagsRaw
                FROM App.vKpiPackages
                ORDER BY PackageName");

            var list = items.ToList();
            return Results.Ok(new ApiList<KpiPackageDto>(list, list.Count));
        }).RequireAuthorization();

        // GET /kpi/packages/{id}
        app.MapGet("/kpi/packages/{id:int}", async (int id, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();

            var pkg = await conn.QuerySingleOrDefaultAsync<KpiPackageDto>(@"
                SELECT KpiPackageId, PackageCode, PackageName, IsActive, KpiCount, TagsRaw
                FROM App.vKpiPackages
                WHERE KpiPackageId = @Id",
                new { Id = id });

            if (pkg is null)
                return Results.NotFound(new ApiError("KPI_PACKAGE_NOT_FOUND", $"KPI package {id} not found."));

            var items = await conn.QueryAsync<KpiPackageItemDto>(@"
                SELECT KpiPackageItemId, KpiPackageId, KpiId, KpiCode, KpiName, Category, DataType, KpiIsActive
                FROM App.vKpiPackageItems
                WHERE KpiPackageId = @Id
                ORDER BY KpiCode",
                new { Id = id });

            return Results.Ok(new { Package = pkg, Items = items.ToList() });
        }).RequireAuthorization();

        // POST /kpi/packages
        app.MapPost("/kpi/packages", async (ClaimsPrincipal user, CreateKpiPackageRequest request, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.KpiAdmin))
                return Results.Forbid();

            var upn = user.FindFirst(System.Security.Claims.ClaimTypes.Email)?.Value
                   ?? user.FindFirst(System.Security.Claims.ClaimTypes.Name)?.Value;

            var p = new DynamicParameters();
            p.Add("@PackageCode",  request.PackageCode.ToUpperInvariant());
            p.Add("@PackageName",  request.PackageName);
            p.Add("@ActorUPN",     upn);
            p.Add("@KpiPackageId", dbType: System.Data.DbType.Int32,
                  direction: System.Data.ParameterDirection.Output);

            await conn.ExecuteAsync("App.usp_UpsertKpiPackage", p,
                commandType: System.Data.CommandType.StoredProcedure);

            var newId = p.Get<int>("@KpiPackageId");

            var tagIdsCsv = request.TagIds is null ? "" : string.Join(",", request.TagIds);
            await conn.ExecuteAsync("App.usp_SetKpiPackageTags",
                new { KpiPackageId = newId, TagIds = tagIdsCsv, ActorUPN = upn },
                commandType: System.Data.CommandType.StoredProcedure);

            var created = await conn.QuerySingleAsync<KpiPackageDto>(@"
                SELECT KpiPackageId, PackageCode, PackageName, IsActive, KpiCount, TagsRaw
                FROM App.vKpiPackages WHERE KpiPackageId = @Id",
                new { Id = newId });

            return Results.Created($"/kpi/packages/{newId}", created);
        }).RequireAuthorization();

        // PATCH /kpi/packages/{id}
        app.MapMethods("/kpi/packages/{id:int}", new[] { "PATCH" },
            async (ClaimsPrincipal user, int id, UpdateKpiPackageRequest request, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.KpiAdmin))
                return Results.Forbid();

            var current = await conn.QuerySingleOrDefaultAsync<KpiPackageDto>(@"
                SELECT KpiPackageId, PackageCode, PackageName, IsActive, KpiCount, TagsRaw
                FROM App.vKpiPackages WHERE KpiPackageId = @Id",
                new { Id = id });

            if (current is null)
                return Results.NotFound(new ApiError("KPI_PACKAGE_NOT_FOUND", $"KPI package {id} not found."));

            var upn = user.FindFirst(System.Security.Claims.ClaimTypes.Email)?.Value
                   ?? user.FindFirst(System.Security.Claims.ClaimTypes.Name)?.Value;

            var p = new DynamicParameters();
            p.Add("@PackageCode",  current.PackageCode);
            p.Add("@PackageName",  request.PackageName);
            p.Add("@ActorUPN",     upn);
            p.Add("@KpiPackageId", dbType: System.Data.DbType.Int32,
                  direction: System.Data.ParameterDirection.Output);

            await conn.ExecuteAsync("App.usp_UpsertKpiPackage", p,
                commandType: System.Data.CommandType.StoredProcedure);

            var tagIdsCsv = request.TagIds is null ? "" : string.Join(",", request.TagIds);
            await conn.ExecuteAsync("App.usp_SetKpiPackageTags",
                new { KpiPackageId = id, TagIds = tagIdsCsv, ActorUPN = upn },
                commandType: System.Data.CommandType.StoredProcedure);

            var updated = await conn.QuerySingleAsync<KpiPackageDto>(@"
                SELECT KpiPackageId, PackageCode, PackageName, IsActive, KpiCount, TagsRaw
                FROM App.vKpiPackages WHERE KpiPackageId = @Id",
                new { Id = id });

            return Results.Ok(updated);
        }).RequireAuthorization();

        // PATCH /kpi/packages/{id}/status
        app.MapMethods("/kpi/packages/{id:int}/status", new[] { "PATCH" },
            async (ClaimsPrincipal user, int id, SetActiveRequest body, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.KpiAdmin))
                return Results.Forbid();

            if (!await conn.ExecuteScalarAsync<bool>("SELECT CAST(1 AS bit) FROM KPI.KpiPackage WHERE KpiPackageId = @Id", new { Id = id }))
                return Results.NotFound(new ApiError("KPI_PACKAGE_NOT_FOUND", $"KPI package {id} not found."));

            var upn = user.FindFirst(System.Security.Claims.ClaimTypes.Email)?.Value
                   ?? user.FindFirst(System.Security.Claims.ClaimTypes.Name)?.Value;

            await conn.ExecuteAsync("App.usp_SetKpiPackageActive",
                new { KpiPackageId = id, body.IsActive, ActorUPN = upn },
                commandType: System.Data.CommandType.StoredProcedure);

            return Results.NoContent();
        }).RequireAuthorization();

        // PUT /kpi/packages/{id}/items — replace KPI membership
        app.MapPut("/kpi/packages/{id:int}/items",
            async (ClaimsPrincipal user, int id, SetKpiPackageItemsRequest body, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.KpiAdmin))
                return Results.Forbid();

            if (!await conn.ExecuteScalarAsync<bool>("SELECT CAST(1 AS bit) FROM KPI.KpiPackage WHERE KpiPackageId = @Id", new { Id = id }))
                return Results.NotFound(new ApiError("KPI_PACKAGE_NOT_FOUND", $"KPI package {id} not found."));

            var upn = user.FindFirst(System.Security.Claims.ClaimTypes.Email)?.Value
                   ?? user.FindFirst(System.Security.Claims.ClaimTypes.Name)?.Value;

            var kpiIdsCsv = body.KpiIds is null ? "" : string.Join(",", body.KpiIds);

            await conn.ExecuteAsync("App.usp_SetKpiPackageItems",
                new { KpiPackageId = id, KpiIds = kpiIdsCsv, ActorUPN = upn },
                commandType: System.Data.CommandType.StoredProcedure);

            var items = await conn.QueryAsync<KpiPackageItemDto>(@"
                SELECT KpiPackageItemId, KpiPackageId, KpiId, KpiCode, KpiName, Category, DataType, KpiIsActive
                FROM App.vKpiPackageItems
                WHERE KpiPackageId = @Id
                ORDER BY KpiCode",
                new { Id = id });

            return Results.Ok(items.ToList());
        }).RequireAuthorization();

        // POST /kpi/packages/{id}/assign-templates
        // Creates one assignment template per KPI in the package, all tagged with the package.
        app.MapPost("/kpi/packages/{id:int}/assign-templates",
            async (ClaimsPrincipal user, int id, CreateTemplatesFromPackageRequest request, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            // Account-side endpoint: creating assignment templates from a package
            // is assign-level work. KpiAdmin accepted as a strict superset.
            if (!await platformAuth.HasAnyPermissionAsync(user, conn, Permissions.KpiAssign, Permissions.KpiAdmin))
                return Results.Forbid();

            var packageItems = (await conn.QueryAsync<KpiPackageItemDto>(@"
                SELECT KpiPackageItemId, KpiPackageId, KpiId, KpiCode, KpiName, Category, DataType, KpiIsActive
                FROM App.vKpiPackageItems
                WHERE KpiPackageId = @Id AND KpiIsActive = 1
                ORDER BY KpiCode",
                new { Id = id })).ToList();

            if (packageItems.Count == 0)
                return Results.BadRequest(new ApiError("PACKAGE_EMPTY", "The package has no active KPIs."));

            // Defensive cap: a package is expected to hold tens of KPIs, not thousands.
            const int MaxPackageItems = 500;
            if (packageItems.Count > MaxPackageItems)
                return Results.BadRequest(new ApiError(
                    "PACKAGE_TOO_LARGE",
                    $"Package has {packageItems.Count} items; the per-request cap is {MaxPackageItems}."));

            var upn = user.FindFirst(System.Security.Claims.ClaimTypes.Email)?.Value
                   ?? user.FindFirst(System.Security.Claims.ClaimTypes.Name)?.Value;

            var createdIds = new List<int>();
            var errors = new List<string>();

            foreach (var item in packageItems)
            {
                try
                {
                    var p = new DynamicParameters();
                    p.Add("@KpiCode",              item.KpiCode);
                    p.Add("@PeriodScheduleID",     request.PeriodScheduleId);
                    p.Add("@AccountCode",          request.AccountCode);
                    p.Add("@OrgUnitCode",          request.OrgUnitCode);
                    p.Add("@OrgUnitType",          request.OrgUnitType);
                    p.Add("@IsRequired",           request.IsRequired);
                    p.Add("@TargetValue",          (decimal?)null);
                    p.Add("@ThresholdGreen",       (decimal?)null);
                    p.Add("@ThresholdAmber",       (decimal?)null);
                    p.Add("@ThresholdRed",         (decimal?)null);
                    p.Add("@ThresholdDirection",   (string?)null);
                    p.Add("@SubmitterGuidance",    (string?)null);
                    p.Add("@CustomKpiName",        (string?)null);
                    p.Add("@CustomKpiDescription", (string?)null);
                    p.Add("@KpiPackageId",         id);
                    p.Add("@AssignmentTemplateID", dbType: System.Data.DbType.Int32,
                          direction: System.Data.ParameterDirection.Output);

                    await conn.ExecuteAsync("App.usp_UpsertKpiAssignmentTemplate", p,
                        commandType: System.Data.CommandType.StoredProcedure);

                    createdIds.Add(p.Get<int>("@AssignmentTemplateID"));
                }
                catch (Exception ex)
                {
                    errors.Add($"{item.KpiCode}: {ex.Message}");
                }
            }

            if (request.MaterializeNow && createdIds.Count > 0)
            {
                await conn.ExecuteAsync("App.usp_MaterializeKpiAssignmentTemplates",
                    new { PeriodScheduleIDFilter = request.PeriodScheduleId, ActorUPN = upn },
                    commandType: System.Data.CommandType.StoredProcedure);
            }

            if (errors.Count > 0 && createdIds.Count == 0)
                return Results.BadRequest(new ApiError("PACKAGE_ASSIGN_FAILED", string.Join("; ", errors)));

            return Results.Ok(new { CreatedCount = createdIds.Count, Errors = errors });
        }).RequireAuthorization();

        return app;
    }
}
