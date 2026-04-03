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
                    IsActive
                FROM Sec.AccountRolePolicy
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
                    IsActive
                FROM Sec.AccountRolePolicy
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
                (string.IsNullOrWhiteSpace(request.OrgUnitType) || string.IsNullOrWhiteSpace(request.OrgUnitCode)))
            {
                return Results.BadRequest(new ApiError(
                    "INVALID_SCOPE",
                    "OrgUnitType and OrgUnitCode are required when ScopeType is ORGUNIT."));
            }

            var newId = await conn.QuerySingleAsync<int>(@"
                INSERT INTO Sec.AccountRolePolicy
                    (PolicyName, RoleCodeTemplate, RoleNameTemplate, ScopeType, OrgUnitType, OrgUnitCode, IsActive)
                OUTPUT INSERTED.AccountRolePolicyId
                VALUES
                    (@PolicyName, @RoleCodeTemplate, @RoleNameTemplate, @ScopeType, @OrgUnitType, @OrgUnitCode, 1)",
                new
                {
                    request.PolicyName,
                    RoleCodeTemplate = request.RoleCodeTemplate.Trim().ToUpperInvariant(),
                    request.RoleNameTemplate,
                    request.ScopeType,
                    OrgUnitType = request.ScopeType == "ORGUNIT" ? request.OrgUnitType : null,
                    OrgUnitCode = request.ScopeType == "ORGUNIT" ? request.OrgUnitCode : null,
                });

            if (request.ApplyNow)
                await ApplySingleRolePolicyAcrossAccounts(conn, newId);

            var created = await conn.QuerySingleAsync<AccountRolePolicyDto>(@"
                SELECT AccountRolePolicyId, PolicyName, RoleCodeTemplate, RoleNameTemplate,
                       ScopeType, OrgUnitType, OrgUnitCode, IsActive
                FROM Sec.AccountRolePolicy
                WHERE AccountRolePolicyId = @Id",
                new { Id = newId });

            return Results.Created($"/policies/{newId}", created);
        }).RequireAuthorization();

        // POST /policies/{id}/refresh
        app.MapPost("/policies/{id:int}/refresh", async (int id, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();

            var exists = await conn.ExecuteScalarAsync<int>(@"
                SELECT COUNT(1)
                FROM Sec.AccountRolePolicy
                WHERE AccountRolePolicyId = @Id",
                new { Id = id });

            if (exists == 0)
                return Results.NotFound(new ApiError("POLICY_NOT_FOUND", $"Policy {id} not found."));

            await ApplySingleRolePolicyAcrossAccounts(conn, id);
            return Results.NoContent();
        }).RequireAuthorization();

        // PATCH /policies/{id}/status
        app.MapMethods("/policies/{id:int}/status", new[] { "PATCH" },
            async (int id, SetActiveRequest req, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var affected = await conn.ExecuteAsync(
                "UPDATE Sec.AccountRolePolicy SET IsActive = @IsActive, ModifiedOnUtc = SYSUTCDATETIME() WHERE AccountRolePolicyId = @Id",
                new { IsActive = req.IsActive, Id = id });

            if (affected == 0)
                return Results.NotFound(new ApiError("POLICY_NOT_FOUND", $"Policy {id} not found."));

            if (req.IsActive)
                await ApplySingleRolePolicyAcrossAccounts(conn, id);
            else
                await DeactivateMaterializedRolesForPolicy(conn, id);

            return Results.NoContent();
        }).RequireAuthorization();

        return app;
    }

    private static async Task ApplySingleRolePolicyAcrossAccounts(IDbConnection conn, int policyId)
    {
        var policy = await conn.QuerySingleOrDefaultAsync<AccountRolePolicyDto>(@"
            SELECT
                AccountRolePolicyId,
                PolicyName,
                RoleCodeTemplate,
                RoleNameTemplate,
                ScopeType,
                OrgUnitType,
                OrgUnitCode,
                IsActive
            FROM Sec.AccountRolePolicy
            WHERE AccountRolePolicyId = @PolicyId",
            new { PolicyId = policyId });

        if (policy is null || !policy.IsActive)
            return;

        var accounts = (await conn.QueryAsync<(int AccountId, string AccountCode, string AccountName)>(@"
            SELECT AccountId, AccountCode, AccountName
            FROM Dim.Account
            WHERE IsActive = 1
            ORDER BY AccountCode")).ToList();

        foreach (var account in accounts)
        {
            var roleCode = policy.RoleCodeTemplate
                .Replace("{AccountCode}", account.AccountCode, StringComparison.OrdinalIgnoreCase)
                .Replace("{AccountName}", account.AccountName, StringComparison.OrdinalIgnoreCase);
            var roleName = policy.RoleNameTemplate
                .Replace("{AccountCode}", account.AccountCode, StringComparison.OrdinalIgnoreCase)
                .Replace("{AccountName}", account.AccountName, StringComparison.OrdinalIgnoreCase);
            // Primary lookup: by name (the unique constraint).
            // Finding by name first means the subsequent UPDATE of PrincipalName
            // is always a no-op for the name column — no duplicate key risk.
            int? roleId = await conn.QuerySingleOrDefaultAsync<int?>(@"
                SELECT p.PrincipalId
                FROM Sec.Principal AS p
                WHERE p.PrincipalType = 'Role'
                  AND p.PrincipalName = @RoleName;",
                new { RoleName = roleName });

            // Fallback: look up by role code in case the template name changed.
            if (roleId is null)
            {
                roleId = await conn.QuerySingleOrDefaultAsync<int?>(@"
                    SELECT r.RoleId
                    FROM Sec.Role AS r
                    WHERE r.RoleCode = @RoleCode;",
                    new { RoleCode = roleCode });
            }

            // Still not found — create a new principal.
            if (roleId is null)
            {
                try
                {
                    roleId = await conn.QuerySingleAsync<int>(@"
                        INSERT INTO Sec.Principal (PrincipalType, PrincipalName)
                        OUTPUT INSERTED.PrincipalId
                        VALUES ('Role', @RoleName);",
                        new { RoleName = roleName });
                }
                catch (Microsoft.Data.SqlClient.SqlException ex) when (ex.Number is 2601 or 2627)
                {
                    // Race condition: fetch the row that just beat us.
                    roleId = await conn.QuerySingleOrDefaultAsync<int?>(@"
                        SELECT p.PrincipalId
                        FROM Sec.Principal AS p
                        WHERE p.PrincipalType = 'Role'
                          AND p.PrincipalName = @RoleName;",
                        new { RoleName = roleName });

                    if (roleId is null)
                        throw;
                }
            }

            await conn.ExecuteAsync(@"
                UPDATE pr
                SET pr.PrincipalName = @RoleName,
                    pr.IsActive = 1,
                    pr.ModifiedOnUtc = SYSUTCDATETIME(),
                    pr.ModifiedBy = 'policy_refresh'
                FROM Sec.Principal AS pr
                WHERE pr.PrincipalId = @RoleId;",
                new { RoleId = roleId, RoleName = roleName });

            if (await conn.ExecuteScalarAsync<int>(@"
                SELECT COUNT(1)
                FROM Sec.Role
                WHERE RoleId = @RoleId;",
                new { RoleId = roleId }) == 0)
            {
                await conn.ExecuteAsync(@"
                    INSERT INTO Sec.Role (RoleId, RoleCode, RoleName, Description)
                    VALUES (@RoleId, @RoleCode, @RoleName, NULL);",
                    new { RoleId = roleId, RoleCode = roleCode, RoleName = roleName });
            }
            else
            {
                await conn.ExecuteAsync(@"
                    UPDATE Sec.Role
                    SET RoleCode = @RoleCode,
                        RoleName = @RoleName,
                        ModifiedOnUtc = SYSUTCDATETIME(),
                        ModifiedBy = 'policy_refresh'
                    WHERE RoleId = @RoleId;",
                    new { RoleId = roleId, RoleCode = roleCode, RoleName = roleName });
            }

            int? orgUnitId = null;
            if (policy.ScopeType == "ORGUNIT")
            {
                orgUnitId = await conn.QuerySingleOrDefaultAsync<int?>(@"
                    SELECT TOP (1) ou.OrgUnitId
                    FROM Dim.OrgUnit AS ou
                    WHERE ou.AccountId = @AccountId
                      AND ou.OrgUnitType = @OrgUnitType
                      AND ou.OrgUnitCode = @OrgUnitCode
                    ORDER BY ou.OrgUnitId;",
                    new
                    {
                        account.AccountId,
                        policy.OrgUnitType,
                        policy.OrgUnitCode,
                    });

                if (orgUnitId is null)
                    continue;
            }

            await conn.ExecuteAsync(@"
                INSERT INTO Sec.PrincipalAccessGrant (PrincipalId, AccessType, AccountId, ScopeType, OrgUnitId)
                SELECT
                    @RoleId,
                    'ACCOUNT',
                    @AccountId,
                    @ScopeType,
                    @OrgUnitId
                WHERE NOT EXISTS
                (
                    SELECT 1
                    FROM Sec.PrincipalAccessGrant AS existing
                    WHERE existing.PrincipalId = @RoleId
                      AND existing.AccessType = 'ACCOUNT'
                      AND existing.AccountId = @AccountId
                      AND existing.ScopeType = @ScopeType
                      AND ISNULL(existing.OrgUnitId, -1) = ISNULL(@OrgUnitId, -1)
                );",
                new
                {
                    RoleId = roleId,
                    account.AccountId,
                    ScopeType = policy.ScopeType == "ORGUNIT" ? "ORGUNIT" : "NONE",
                    OrgUnitId = orgUnitId,
                });
        }
    }

    private static async Task DeactivateMaterializedRolesForPolicy(IDbConnection conn, int policyId)
    {
        await conn.ExecuteAsync(@"
            ;WITH Expanded AS
            (
                SELECT DISTINCT
                    REPLACE(REPLACE(REPLACE(REPLACE(pol.RoleCodeTemplate,
                        '{AccountCode}', a.AccountCode),
                        '{ACCOUNTCODE}', a.AccountCode),
                        '{AccountName}', a.AccountName),
                        '{ACCOUNTNAME}', a.AccountName) AS RoleCode
                FROM Sec.AccountRolePolicy AS pol
                CROSS JOIN Dim.Account AS a
                WHERE pol.AccountRolePolicyId = @PolicyId
            )
            UPDATE pr
            SET pr.IsActive = 0,
                pr.ModifiedOnUtc = SYSUTCDATETIME(),
                pr.ModifiedBy = 'policy_disable'
            FROM Sec.Principal AS pr
            JOIN Sec.Role AS r
                ON r.RoleId = pr.PrincipalId
            JOIN Expanded AS e
                ON e.RoleCode = r.RoleCode;",
            new { PolicyId = policyId });
    }
}
