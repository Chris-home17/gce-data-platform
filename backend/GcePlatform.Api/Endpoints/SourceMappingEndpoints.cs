using System.Security.Claims;
using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Models;
using GcePlatform.Api.Services;

namespace GcePlatform.Api.Endpoints;

public static class SourceMappingEndpoints
{
    public static WebApplication MapSourceMappingEndpoints(this WebApplication app)
    {
        // GET /source-mappings?accountId=
        app.MapGet("/source-mappings", GetSourceMappings).RequireAuthorization();

        // POST /source-mappings
        app.MapPost("/source-mappings", CreateSourceMapping).RequireAuthorization();

        return app;
    }

    private static async Task<IResult> GetSourceMappings(int? accountId, DbConnectionFactory db)
    {
        using var conn = db.CreateConnection();
        var items = await conn.QueryAsync<SourceMappingDto>(@"
            SELECT
                OrgUnitSourceMapId,
                OrgUnitId,
                SharedGeoUnitId,
                OrgUnitCode,
                OrgUnitName,
                OrgUnitType,
                AccountId,
                AccountCode,
                AccountName,
                SourceSystem,
                SourceOrgUnitId,
                SourceOrgUnitName,
                CAST(IsActive AS bit) AS IsActive
            FROM App.vSourceMappings
            WHERE (@AccountId IS NULL OR AccountId = @AccountId)
            ORDER BY AccountCode, OrgUnitCode, SourceSystem",
            new { AccountId = accountId });

        var list = items.ToList();
        return Results.Ok(new ApiList<SourceMappingDto>(list, list.Count));
    }

    private static async Task<IResult> CreateSourceMapping(ClaimsPrincipal user, CreateSourceMappingRequest req, DbConnectionFactory db, PlatformAuthService platformAuth)
    {
        using var conn = db.CreateConnection();

        if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.AccountsManage))
            return Results.Forbid();

        var p = new DynamicParameters();
        p.Add("@AccountCode", req.AccountCode);
        p.Add("@OrgUnitCode", req.OrgUnitCode);
        p.Add("@OrgUnitType", req.OrgUnitType);
        p.Add("@SourceSystem", req.SourceSystem);
        p.Add("@SourceOrgUnitId", req.SourceOrgUnitId);
        p.Add("@SourceOrgUnitName", req.SourceOrgUnitName);
        p.Add("@IsActive", 1);
        p.Add("@OrgUnitSourceMapId", dbType: System.Data.DbType.Int32,
            direction: System.Data.ParameterDirection.Output);

        await conn.ExecuteAsync("App.UpsertOrgUnitSourceMap",
            p, commandType: System.Data.CommandType.StoredProcedure);

        var newId = p.Get<int>("@OrgUnitSourceMapId");

        var item = await conn.QuerySingleOrDefaultAsync<SourceMappingDto>(@"
            SELECT
                OrgUnitSourceMapId, OrgUnitId, SharedGeoUnitId, OrgUnitCode, OrgUnitName, OrgUnitType,
                AccountId, AccountCode, AccountName, SourceSystem, SourceOrgUnitId,
                SourceOrgUnitName, CAST(IsActive AS bit) AS IsActive
            FROM App.vSourceMappings
            WHERE OrgUnitSourceMapId = @Id",
            new { Id = newId });

        return Results.Created($"/source-mappings/{newId}", item);
    }
}
