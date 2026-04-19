using System.Security.Claims;
using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Models;
using GcePlatform.Api.Services;

namespace GcePlatform.Api.Endpoints;

public static class TagEndpoints
{
    public static WebApplication MapTagEndpoints(this WebApplication app)
    {
        // GET /tags
        app.MapGet("/tags", async (DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var items = await conn.QueryAsync<TagDto>(@"
                SELECT
                    TagId,
                    TagCode,
                    TagName,
                    TagDescription,
                    IsActive,
                    KpiCount
                FROM App.vTags
                ORDER BY TagName");

            var list = items.ToList();
            return Results.Ok(new ApiList<TagDto>(list, list.Count));
        }).RequireAuthorization();

        // GET /tags/{id}
        app.MapGet("/tags/{id:int}", async (int id, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var item = await conn.QuerySingleOrDefaultAsync<TagDto>(@"
                SELECT TagId, TagCode, TagName, TagDescription, IsActive, KpiCount
                FROM App.vTags
                WHERE TagId = @Id",
                new { Id = id });

            return item is null
                ? Results.NotFound(new ApiError("TAG_NOT_FOUND", $"Tag {id} not found."))
                : Results.Ok(item);
        }).RequireAuthorization();

        // POST /tags
        app.MapPost("/tags", async (ClaimsPrincipal user, CreateTagRequest request, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.SuperAdmin))
                return Results.Forbid();

            var upn = user.FindFirst(System.Security.Claims.ClaimTypes.Email)?.Value
                   ?? user.FindFirst(System.Security.Claims.ClaimTypes.Name)?.Value;

            var p = new DynamicParameters();
            p.Add("@TagCode",        request.TagCode.ToUpperInvariant());
            p.Add("@TagName",        request.TagName);
            p.Add("@TagDescription", request.TagDescription);
            p.Add("@ActorUPN",       upn);
            p.Add("@TagId", dbType: System.Data.DbType.Int32,
                  direction: System.Data.ParameterDirection.Output);

            await conn.ExecuteAsync("App.usp_UpsertTag", p,
                commandType: System.Data.CommandType.StoredProcedure);

            var newId = p.Get<int>("@TagId");

            var created = await conn.QuerySingleAsync<TagDto>(@"
                SELECT TagId, TagCode, TagName, TagDescription, IsActive, KpiCount
                FROM App.vTags WHERE TagId = @Id",
                new { Id = newId });

            return Results.Created($"/tags/{newId}", created);
        }).RequireAuthorization();

        // PATCH /tags/{id}
        app.MapMethods("/tags/{id:int}", new[] { "PATCH" },
            async (ClaimsPrincipal user, int id, UpdateTagRequest request, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.SuperAdmin))
                return Results.Forbid();

            var current = await conn.QuerySingleOrDefaultAsync<TagDto>(@"
                SELECT TagId, TagCode, TagName, TagDescription, IsActive, KpiCount
                FROM App.vTags WHERE TagId = @Id",
                new { Id = id });

            if (current is null)
                return Results.NotFound(new ApiError("TAG_NOT_FOUND", $"Tag {id} not found."));

            var upn = user.FindFirst(System.Security.Claims.ClaimTypes.Email)?.Value
                   ?? user.FindFirst(System.Security.Claims.ClaimTypes.Name)?.Value;

            var p = new DynamicParameters();
            p.Add("@TagCode",        current.TagCode);
            p.Add("@TagName",        request.TagName);
            p.Add("@TagDescription", request.TagDescription);
            p.Add("@ActorUPN",       upn);
            p.Add("@TagId", dbType: System.Data.DbType.Int32,
                  direction: System.Data.ParameterDirection.Output);

            await conn.ExecuteAsync("App.usp_UpsertTag", p,
                commandType: System.Data.CommandType.StoredProcedure);

            var updated = await conn.QuerySingleAsync<TagDto>(@"
                SELECT TagId, TagCode, TagName, TagDescription, IsActive, KpiCount
                FROM App.vTags WHERE TagId = @Id",
                new { Id = id });

            return Results.Ok(updated);
        }).RequireAuthorization();

        // PATCH /tags/{id}/status
        app.MapMethods("/tags/{id:int}/status", new[] { "PATCH" },
            async (ClaimsPrincipal user, int id, SetActiveRequest body, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.SuperAdmin))
                return Results.Forbid();

            if (!await conn.ExecuteScalarAsync<bool>("SELECT CAST(1 AS bit) FROM Dim.Tag WHERE TagId = @Id", new { Id = id }))
                return Results.NotFound(new ApiError("TAG_NOT_FOUND", $"Tag {id} not found."));

            var upn = user.FindFirst(System.Security.Claims.ClaimTypes.Email)?.Value
                   ?? user.FindFirst(System.Security.Claims.ClaimTypes.Name)?.Value;

            await conn.ExecuteAsync("App.usp_SetTagActive",
                new { TagId = id, body.IsActive, ActorUPN = upn },
                commandType: System.Data.CommandType.StoredProcedure);

            return Results.NoContent();
        }).RequireAuthorization();

        return app;
    }
}
