using System.Security.Claims;
using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Models;
using GcePlatform.Api.Services;

namespace GcePlatform.Api.Endpoints;

// KPI categories are a GLOBAL lookup (not per-account). Reads are open to any
// authenticated user — every KPI form needs them. Writes are gated on kpi.admin.
// Code is immutable after creation.
public static class KpiCategoryEndpoints
{
    public static WebApplication MapKpiCategoryEndpoints(this WebApplication app)
    {
        // GET /kpi/categories?includeInactive=false
        app.MapGet("/kpi/categories", async (bool? includeInactive, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var rows = await conn.QueryAsync<KpiCategoryDto>(@"
                SELECT
                    c.KpiCategoryId,
                    c.ExternalId,
                    c.Code,
                    c.Name,
                    c.Description,
                    c.IsActive,
                    c.CreatedOnUtc,
                    c.ModifiedOnUtc,
                    -- Usage counters help the admin UI warn before deactivation.
                    (SELECT COUNT(*) FROM KPI.Definition d WHERE d.KpiCategoryId = c.KpiCategoryId)         AS DefinitionCount,
                    (SELECT COUNT(*) FROM KPI.CategoryWeight w WHERE w.KpiCategoryId = c.KpiCategoryId)     AS CategoryWeightCount
                FROM KPI.Category AS c
                WHERE @IncludeInactive = 1 OR c.IsActive = 1
                ORDER BY c.Name",
                new { IncludeInactive = includeInactive == true ? 1 : 0 });

            var list = rows.ToList();
            return Results.Ok(new ApiList<KpiCategoryDto>(list, list.Count));
        }).RequireAuthorization();

        // GET /kpi/categories/{id}
        app.MapGet("/kpi/categories/{id:int}", async (int id, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var row = await conn.QuerySingleOrDefaultAsync<KpiCategoryDto>(@"
                SELECT
                    c.KpiCategoryId,
                    c.ExternalId,
                    c.Code,
                    c.Name,
                    c.Description,
                    c.IsActive,
                    c.CreatedOnUtc,
                    c.ModifiedOnUtc,
                    (SELECT COUNT(*) FROM KPI.Definition d WHERE d.KpiCategoryId = c.KpiCategoryId)         AS DefinitionCount,
                    (SELECT COUNT(*) FROM KPI.CategoryWeight w WHERE w.KpiCategoryId = c.KpiCategoryId)     AS CategoryWeightCount
                FROM KPI.Category AS c
                WHERE c.KpiCategoryId = @Id",
                new { Id = id });

            return row is null
                ? Results.NotFound(new ApiError("KPI_CATEGORY_NOT_FOUND", $"KPI category {id} not found."))
                : Results.Ok(row);
        }).RequireAuthorization();

        // POST /kpi/categories — create. Code is required and locked from this point on.
        app.MapPost("/kpi/categories", async (
            ClaimsPrincipal user,
            CreateKpiCategoryRequest req,
            DbConnectionFactory db,
            PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.KpiAdmin))
                return Results.Forbid();

            if (string.IsNullOrWhiteSpace(req.Code))
                return Results.BadRequest(new ApiError("CODE_REQUIRED", "Code is required."));
            if (string.IsNullOrWhiteSpace(req.Name))
                return Results.BadRequest(new ApiError("NAME_REQUIRED", "Name is required."));

            var normalisedCode = req.Code.Trim().ToUpperInvariant();
            // Code grammar: 1-20 chars, alphanumeric only. Same character set as KPI codes
            // because auto-generated KPI codes use this as a prefix.
            if (normalisedCode.Length > 20 || !System.Text.RegularExpressions.Regex.IsMatch(normalisedCode, @"^[A-Z0-9]+$"))
                return Results.BadRequest(new ApiError(
                    "CODE_INVALID",
                    "Code must be 1-20 alphanumeric characters (A-Z, 0-9)."));

            var existing = await conn.ExecuteScalarAsync<bool>(
                "SELECT CAST(CASE WHEN EXISTS (SELECT 1 FROM KPI.Category WHERE Code = @Code) THEN 1 ELSE 0 END AS bit)",
                new { Code = normalisedCode });
            if (existing)
                return Results.Conflict(new ApiError("CODE_DUPLICATE", $"A category with code '{normalisedCode}' already exists."));

            var actorUpn = PlatformAuthService.GetUpn(user);

            var p = new DynamicParameters();
            p.Add("@KpiCategoryId", null, System.Data.DbType.Int32);
            p.Add("@Code",          normalisedCode);
            p.Add("@Name",          req.Name.Trim());
            p.Add("@Description",   string.IsNullOrWhiteSpace(req.Description) ? null : req.Description.Trim());
            p.Add("@IsActive",      req.IsActive ?? true);
            p.Add("@ActorUPN",      actorUpn);
            p.Add("@KpiCategoryIdOut", dbType: System.Data.DbType.Int32,
                  direction: System.Data.ParameterDirection.Output);

            await conn.ExecuteAsync("App.usp_UpsertKpiCategory", p,
                commandType: System.Data.CommandType.StoredProcedure);

            var newId = p.Get<int>("@KpiCategoryIdOut");

            var created = await conn.QuerySingleAsync<KpiCategoryDto>(@"
                SELECT KpiCategoryId, ExternalId, Code, Name, Description, IsActive,
                       CreatedOnUtc, ModifiedOnUtc,
                       0 AS DefinitionCount, 0 AS CategoryWeightCount
                FROM KPI.Category WHERE KpiCategoryId = @Id", new { Id = newId });

            return Results.Created($"/kpi/categories/{newId}", created);
        }).RequireAuthorization();

        // PATCH /kpi/categories/{id} — update Name/Description/IsActive.
        // Code is immutable from creation onward; the request DTO doesn't carry it.
        app.MapMethods("/kpi/categories/{id:int}", new[] { "PATCH" },
            async (ClaimsPrincipal user, int id, UpdateKpiCategoryRequest req,
                   DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.KpiAdmin))
                return Results.Forbid();

            var current = await conn.QuerySingleOrDefaultAsync<KpiCategoryDto>(@"
                SELECT KpiCategoryId, ExternalId, Code, Name, Description, IsActive,
                       CreatedOnUtc, ModifiedOnUtc,
                       0 AS DefinitionCount, 0 AS CategoryWeightCount
                FROM KPI.Category WHERE KpiCategoryId = @Id", new { Id = id });
            if (current is null)
                return Results.NotFound(new ApiError("KPI_CATEGORY_NOT_FOUND", $"KPI category {id} not found."));

            if (string.IsNullOrWhiteSpace(req.Name))
                return Results.BadRequest(new ApiError("NAME_REQUIRED", "Name is required."));

            var actorUpn = PlatformAuthService.GetUpn(user);

            var p = new DynamicParameters();
            p.Add("@KpiCategoryId", id);
            p.Add("@Code",          current.Code);  // ignored on UPDATE branch but required by signature
            p.Add("@Name",          req.Name.Trim());
            p.Add("@Description",   string.IsNullOrWhiteSpace(req.Description) ? null : req.Description.Trim());
            p.Add("@IsActive",      req.IsActive ?? current.IsActive);
            p.Add("@ActorUPN",      actorUpn);
            p.Add("@KpiCategoryIdOut", dbType: System.Data.DbType.Int32,
                  direction: System.Data.ParameterDirection.Output);

            await conn.ExecuteAsync("App.usp_UpsertKpiCategory", p,
                commandType: System.Data.CommandType.StoredProcedure);

            var updated = await conn.QuerySingleAsync<KpiCategoryDto>(@"
                SELECT
                    c.KpiCategoryId, c.ExternalId, c.Code, c.Name, c.Description,
                    c.IsActive, c.CreatedOnUtc, c.ModifiedOnUtc,
                    (SELECT COUNT(*) FROM KPI.Definition d WHERE d.KpiCategoryId = c.KpiCategoryId)     AS DefinitionCount,
                    (SELECT COUNT(*) FROM KPI.CategoryWeight w WHERE w.KpiCategoryId = c.KpiCategoryId) AS CategoryWeightCount
                FROM KPI.Category AS c WHERE c.KpiCategoryId = @Id", new { Id = id });

            return Results.Ok(updated);
        }).RequireAuthorization();

        // PATCH /kpi/categories/{id}/status — flip IsActive.
        app.MapMethods("/kpi/categories/{id:int}/status", new[] { "PATCH" },
            async (ClaimsPrincipal user, int id, SetActiveRequest body,
                   DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.KpiAdmin))
                return Results.Forbid();

            var exists = await conn.ExecuteScalarAsync<bool>(
                "SELECT CAST(CASE WHEN EXISTS (SELECT 1 FROM KPI.Category WHERE KpiCategoryId = @Id) THEN 1 ELSE 0 END AS bit)",
                new { Id = id });
            if (!exists)
                return Results.NotFound(new ApiError("KPI_CATEGORY_NOT_FOUND", $"KPI category {id} not found."));

            await conn.ExecuteAsync("App.usp_SetKpiCategoryActive",
                new { KpiCategoryId = id, body.IsActive, ActorUPN = PlatformAuthService.GetUpn(user) },
                commandType: System.Data.CommandType.StoredProcedure);

            return Results.NoContent();
        }).RequireAuthorization();

        return app;
    }
}
