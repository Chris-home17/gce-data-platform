using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Models;
using System.Data;
using System.Linq;

namespace GcePlatform.Api.Endpoints;

public static class PolicyEndpoints
{
    public static WebApplication MapPolicyEndpoints(this WebApplication app)
    {
        // GET /policies
        app.MapGet("/policies", async (DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var items = await conn.QueryAsync<AccountRolePolicyDto>(@"
                SELECT
                    AccountRolePolicyId,
                    PolicyName,
                    RoleCodeTemplate,
                    RoleNameTemplate,
                    ScopeType,
                    OrgUnitType,
                    OrgUnitCode,
                    CAST(ExpandPerOrgUnit AS bit) AS ExpandPerOrgUnit,
                    IsActive
                FROM App.vAccountRolePolicies
                ORDER BY PolicyName");

            var list = items.ToList();
            return Results.Ok(new ApiList<AccountRolePolicyDto>(list, list.Count));
        }).RequireAuthorization();

        // GET /policies/{id}
        app.MapGet("/policies/{id:int}", async (int id, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var item = await conn.QuerySingleOrDefaultAsync<AccountRolePolicyDto>(@"
                SELECT
                    AccountRolePolicyId,
                    PolicyName,
                    RoleCodeTemplate,
                    RoleNameTemplate,
                    ScopeType,
                    OrgUnitType,
                    OrgUnitCode,
                    CAST(ExpandPerOrgUnit AS bit) AS ExpandPerOrgUnit,
                    IsActive
                FROM App.vAccountRolePolicies
                WHERE AccountRolePolicyId = @Id",
                new { Id = id });

            return item is null
                ? Results.NotFound(new ApiError("POLICY_NOT_FOUND", $"Policy {id} not found."))
                : Results.Ok(item);
        }).RequireAuthorization();

        // POST /policies
        app.MapPost("/policies", async (CreateAccountRolePolicyRequest request, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();

            // Validate ORGUNIT scope has the required fields
            if (request.ScopeType == "ORGUNIT" &&
                (string.IsNullOrWhiteSpace(request.OrgUnitType)
                    || (!request.ExpandPerOrgUnit && string.IsNullOrWhiteSpace(request.OrgUnitCode))))
            {
                return Results.BadRequest(new ApiError(
                    "INVALID_SCOPE",
                    request.ExpandPerOrgUnit
                        ? "OrgUnitType is required when ScopeType is ORGUNIT and expansion is enabled."
                        : "OrgUnitType and OrgUnitCode are required when ScopeType is ORGUNIT."));
            }

            if (request.ScopeType != "ORGUNIT" && request.ExpandPerOrgUnit)
            {
                return Results.BadRequest(new ApiError(
                    "INVALID_EXPANSION",
                    "ExpandPerOrgUnit can only be enabled when ScopeType is ORGUNIT."));
            }

            if (request.ExpandPerOrgUnit &&
                (!ContainsOrgUnitToken(request.RoleCodeTemplate) || !ContainsOrgUnitToken(request.RoleNameTemplate)))
            {
                return Results.BadRequest(new ApiError(
                    "ORG_UNIT_TOKEN_REQUIRED",
                    "Per-org-unit expansion requires both role templates to include {OrgUnitCode} or {OrgUnitName}."));
            }

            var p = new DynamicParameters();
            p.Add("@AccountRolePolicyId", null);
            p.Add("@PolicyName", request.PolicyName);
            p.Add("@RoleCodeTemplate", request.RoleCodeTemplate.Trim().ToUpperInvariant());
            p.Add("@RoleNameTemplate", request.RoleNameTemplate);
            p.Add("@ScopeType", request.ScopeType);
            p.Add("@OrgUnitType", request.ScopeType == "ORGUNIT" ? request.OrgUnitType : null);
            p.Add("@OrgUnitCode", request.ScopeType == "ORGUNIT" ? request.OrgUnitCode : null);
            p.Add("@ExpandPerOrgUnit", request.ExpandPerOrgUnit);
            p.Add("@ApplyNow", request.ApplyNow);
            p.Add("@ResultAccountRolePolicyId", dbType: System.Data.DbType.Int32,
                direction: System.Data.ParameterDirection.Output);

            await conn.ExecuteAsync("App.usp_UpsertAccountRolePolicy", p,
                commandType: System.Data.CommandType.StoredProcedure);

            var newId = p.Get<int>("@ResultAccountRolePolicyId");

            var created = await conn.QuerySingleAsync<AccountRolePolicyDto>(@"
                SELECT AccountRolePolicyId, PolicyName, RoleCodeTemplate, RoleNameTemplate,
                       ScopeType, OrgUnitType, OrgUnitCode, CAST(ExpandPerOrgUnit AS bit) AS ExpandPerOrgUnit, IsActive
                FROM App.vAccountRolePolicies
                WHERE AccountRolePolicyId = @Id",
                new { Id = newId });

            return Results.Created($"/policies/{newId}", created);
        }).RequireAuthorization();

        // PUT /policies/{id}
        app.MapPut("/policies/{id:int}", async (int id, UpdateAccountRolePolicyRequest request, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();

            var existing = await conn.QuerySingleOrDefaultAsync<AccountRolePolicyDto>(@"
                SELECT AccountRolePolicyId, PolicyName, RoleCodeTemplate, RoleNameTemplate,
                       ScopeType, OrgUnitType, OrgUnitCode, CAST(ExpandPerOrgUnit AS bit) AS ExpandPerOrgUnit, IsActive
                FROM App.vAccountRolePolicies
                WHERE AccountRolePolicyId = @Id",
                new { Id = id });

            if (existing is null)
                return Results.NotFound(new ApiError("POLICY_NOT_FOUND", $"Policy {id} not found."));

            // Validate ORGUNIT scope has the required fields
            if (request.ScopeType == "ORGUNIT" &&
                (string.IsNullOrWhiteSpace(request.OrgUnitType)
                    || (!request.ExpandPerOrgUnit && string.IsNullOrWhiteSpace(request.OrgUnitCode))))
            {
                return Results.BadRequest(new ApiError(
                    "INVALID_SCOPE",
                    request.ExpandPerOrgUnit
                        ? "OrgUnitType is required when ScopeType is ORGUNIT and expansion is enabled."
                        : "OrgUnitType and OrgUnitCode are required when ScopeType is ORGUNIT."));
            }

            if (request.ScopeType != "ORGUNIT" && request.ExpandPerOrgUnit)
            {
                return Results.BadRequest(new ApiError(
                    "INVALID_EXPANSION",
                    "ExpandPerOrgUnit can only be enabled when ScopeType is ORGUNIT."));
            }

            if (request.ExpandPerOrgUnit &&
                (!ContainsOrgUnitToken(request.RoleCodeTemplate) || !ContainsOrgUnitToken(request.RoleNameTemplate)))
            {
                return Results.BadRequest(new ApiError(
                    "ORG_UNIT_TOKEN_REQUIRED",
                    "Per-org-unit expansion requires both role templates to include {OrgUnitCode} or {OrgUnitName}."));
            }

            var p = new DynamicParameters();
            p.Add("@AccountRolePolicyId", id);
            p.Add("@PolicyName", request.PolicyName);
            p.Add("@RoleCodeTemplate", request.RoleCodeTemplate.Trim().ToUpperInvariant());
            p.Add("@RoleNameTemplate", request.RoleNameTemplate);
            p.Add("@ScopeType", request.ScopeType);
            p.Add("@OrgUnitType", request.ScopeType == "ORGUNIT" ? request.OrgUnitType : null);
            p.Add("@OrgUnitCode", request.ScopeType == "ORGUNIT" ? request.OrgUnitCode : null);
            p.Add("@ExpandPerOrgUnit", request.ExpandPerOrgUnit);
            p.Add("@ApplyNow", request.RefreshAfterSave);
            p.Add("@ResultAccountRolePolicyId", dbType: System.Data.DbType.Int32,
                direction: System.Data.ParameterDirection.Output);

            await conn.ExecuteAsync("App.usp_UpsertAccountRolePolicy", p,
                commandType: System.Data.CommandType.StoredProcedure);

            var updated = await conn.QuerySingleAsync<AccountRolePolicyDto>(@"
                SELECT AccountRolePolicyId, PolicyName, RoleCodeTemplate, RoleNameTemplate,
                       ScopeType, OrgUnitType, OrgUnitCode, CAST(ExpandPerOrgUnit AS bit) AS ExpandPerOrgUnit, IsActive
                FROM App.vAccountRolePolicies
                WHERE AccountRolePolicyId = @Id",
                new { Id = id });

            return Results.Ok(updated);
        }).RequireAuthorization();

        // POST /policies/{id}/refresh
        app.MapPost("/policies/{id:int}/refresh", async (int id, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();

            var exists = await conn.ExecuteScalarAsync<int>(@"
                SELECT COUNT(1)
                FROM App.vAccountRolePolicies
                WHERE AccountRolePolicyId = @Id",
                new { Id = id });

            if (exists == 0)
                return Results.NotFound(new ApiError("POLICY_NOT_FOUND", $"Policy {id} not found."));

            await conn.ExecuteAsync("App.usp_RefreshAccountRolePolicy",
                new { AccountRolePolicyId = id },
                commandType: System.Data.CommandType.StoredProcedure);
            return Results.NoContent();
        }).RequireAuthorization();

        // PATCH /policies/{id}/status
        app.MapMethods("/policies/{id:int}/status", new[] { "PATCH" },
            async (int id, SetActiveRequest req, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();

            var exists = await conn.ExecuteScalarAsync<int>(@"
                SELECT COUNT(1)
                FROM App.vAccountRolePolicies
                WHERE AccountRolePolicyId = @Id",
                new { Id = id });

            if (exists == 0)
                return Results.NotFound(new ApiError("POLICY_NOT_FOUND", $"Policy {id} not found."));

            await conn.ExecuteAsync("App.usp_SetAccountRolePolicyActive",
                new { AccountRolePolicyId = id, req.IsActive },
                commandType: System.Data.CommandType.StoredProcedure);

            return Results.NoContent();
        }).RequireAuthorization();

        return app;
    }
    private static bool ContainsOrgUnitToken(string template) =>
        template.Contains("{OrgUnitCode}", StringComparison.OrdinalIgnoreCase)
        || template.Contains("{OrgUnitName}", StringComparison.OrdinalIgnoreCase);
}
