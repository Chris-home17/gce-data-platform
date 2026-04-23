using System.Security.Claims;
using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Models;
using GcePlatform.Api.Services;

namespace GcePlatform.Api.Endpoints;

public static class PackageEndpoints
{
    public static WebApplication MapPackageEndpoints(this WebApplication app)
    {
        // GET /packages
        app.MapGet("/packages", async (DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var items = await conn.QueryAsync<PackageDto>(@"
                SELECT
                    PackageId,
                    PackageCode,
                    PackageName,
                    PackageGroup,
                    CAST(IsActive AS bit) AS IsActive,
                    ReportCount
                FROM App.vPackages
                ORDER BY PackageGroup, PackageCode");

            var list = items.ToList();
            return Results.Ok(new ApiList<PackageDto>(list, list.Count));
        }).RequireAuthorization();

        // GET /packages/{id}
        app.MapGet("/packages/{id:int}", async (int id, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var item = await conn.QuerySingleOrDefaultAsync<PackageDto>(@"
                SELECT
                    PackageId,
                    PackageCode,
                    PackageName,
                    PackageGroup,
                    CAST(IsActive AS bit) AS IsActive,
                    ReportCount
                FROM App.vPackages
                WHERE PackageId = @Id",
                new { Id = id });

            return item is null
                ? Results.NotFound(new ApiError("PACKAGE_NOT_FOUND", $"Package {id} not found."))
                : Results.Ok(item);
        }).RequireAuthorization();

        // GET /packages/{id}/reports
        app.MapGet("/packages/{id:int}/reports", async (int id, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var items = await conn.QueryAsync<BiReportDto>(@"
                SELECT
                    BiReportId,
                    ReportCode,
                    ReportName,
                    ReportUri,
                    CAST(IsActive AS bit) AS IsActive,
                    PackageCount,
                    ISNULL(PackageList, '') AS PackageList
                FROM App.vPackageReports
                WHERE PackageId = @Id
                ORDER BY ReportCode",
                new { Id = id });

            var list = items.ToList();
            return Results.Ok(new ApiList<BiReportDto>(list, list.Count));
        }).RequireAuthorization();

        // POST /packages
        app.MapPost("/packages", async (ClaimsPrincipal user, CreatePackageRequest req, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.SuperAdmin))
                return Results.Forbid();

            var p = new DynamicParameters();
            p.Add("@PackageCode",  req.PackageCode);
            p.Add("@PackageName",  req.PackageName);
            p.Add("@PackageGroup", req.PackageGroup);
            p.Add("@IsActive",     1);
            p.Add("@PackageId",    dbType: System.Data.DbType.Int32,
                                   direction: System.Data.ParameterDirection.Output);

            await conn.ExecuteAsync("App.UpsertPackage",
                p, commandType: System.Data.CommandType.StoredProcedure);

            var newId = p.Get<int>("@PackageId");

            var item = await conn.QuerySingleOrDefaultAsync<PackageDto>(@"
                SELECT PackageId, PackageCode, PackageName, PackageGroup,
                       CAST(IsActive AS bit) AS IsActive, ReportCount
                FROM App.vPackages WHERE PackageId = @Id",
                new { Id = newId });

            return Results.Created($"/packages/{newId}", item);
        }).RequireAuthorization();

        // PATCH /packages/{id}/status
        app.MapMethods("/packages/{id:int}/status", new[] { "PATCH" },
            async (ClaimsPrincipal user, int id, SetActiveRequest req, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.SuperAdmin))
                return Results.Forbid();

            var item = await conn.QuerySingleOrDefaultAsync<PackageDto>(
                "SELECT PackageId, PackageCode, PackageName, PackageGroup, CAST(IsActive AS bit) AS IsActive, ReportCount FROM App.vPackages WHERE PackageId = @Id",
                new { Id = id });

            if (item is null)
                return Results.NotFound(new ApiError("PACKAGE_NOT_FOUND", $"Package {id} not found."));

            var p = new DynamicParameters();
            p.Add("@PackageCode",  item.PackageCode);
            p.Add("@PackageName",  item.PackageName);
            p.Add("@PackageGroup", item.PackageGroup);
            p.Add("@IsActive",     req.IsActive ? 1 : 0);
            p.Add("@PackageId",    dbType: System.Data.DbType.Int32,
                                   direction: System.Data.ParameterDirection.Output);

            await conn.ExecuteAsync("App.UpsertPackage", p,
                commandType: System.Data.CommandType.StoredProcedure);

            return Results.NoContent();
        }).RequireAuthorization();

        return app;
    }
}
