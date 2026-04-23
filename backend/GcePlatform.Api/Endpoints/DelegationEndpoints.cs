using System.Security.Claims;
using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Helpers;
using GcePlatform.Api.Models;
using GcePlatform.Api.Services;
using Microsoft.Data.SqlClient;

namespace GcePlatform.Api.Endpoints;

public static class DelegationEndpoints
{
    public static WebApplication MapDelegationEndpoints(this WebApplication app)
    {
        app.MapGet("/delegations/scope-options", async (
            string delegatorType,
            string delegatorIdentifier,
            string accessType,
            string? accountCode,
            DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();

            var principal = await conn.QuerySingleOrDefaultAsync<(int PrincipalId, string PrincipalType)>(@"
                SELECT PrincipalId, PrincipalType
                FROM App.vPrincipals
                WHERE IsActive = 1
                  AND (
                        (@DelegatorType = 'USER' AND PrincipalType = 'User' AND UPN = @DelegatorIdentifier)
                     OR (@DelegatorType = 'ROLE' AND PrincipalType = 'Role' AND RoleCode = @DelegatorIdentifier)
                  )",
                new
                {
                    DelegatorType = delegatorType,
                    DelegatorIdentifier = delegatorIdentifier,
                });

            if (principal.PrincipalId == 0)
            {
                return Results.NotFound(new ApiError("PRINCIPAL_NOT_FOUND", "Delegator principal not found."));
            }

            var accounts = (await conn.QueryAsync<DelegationScopeAccountOptionDto>(@"
                WITH EffectiveScopes AS
                (
                    SELECT
                        @PrincipalId AS PrincipalId,
                        eff.AccessType,
                        eff.AccountId,
                        eff.ScopeType,
                        eff.OrgUnitId
                    FROM Sec.vPrincipalEffectiveAccess AS eff
                    WHERE eff.PrincipalId = @PrincipalId

                    UNION ALL

                    SELECT
                        @PrincipalId AS PrincipalId,
                        eff.AccessType,
                        eff.AccountId,
                        eff.ScopeType,
                        eff.OrgUnitId
                    FROM Sec.vUserGrantPrincipals AS gp
                    JOIN Sec.vPrincipalEffectiveAccess AS eff
                        ON eff.PrincipalId = gp.GrantPrincipalId
                    WHERE gp.UserPrincipalId = @PrincipalId
                ),
                DelegableAccounts AS
                (
                    SELECT DISTINCT a.AccountCode, a.AccountName
                    FROM Dim.Account AS a
                    WHERE EXISTS (
                        SELECT 1
                        FROM EffectiveScopes AS eff
                        LEFT JOIN Dim.OrgUnit AS effOrg ON eff.OrgUnitId = effOrg.OrgUnitId
                        WHERE (
                                eff.AccessType = 'ALL'
                            AND eff.ScopeType = 'NONE'
                        )
                        OR (
                                eff.AccessType = 'ACCOUNT'
                            AND eff.ScopeType = 'NONE'
                            AND eff.AccountId = a.AccountId
                        )
                        OR (
                                @AccessType = 'ACCOUNT'
                            AND eff.ScopeType = 'ORGUNIT'
                            AND (
                                   (eff.AccessType = 'ACCOUNT' AND eff.AccountId = a.AccountId)
                                OR (eff.AccessType = 'ALL' AND effOrg.AccountId = a.AccountId)
                            )
                        )
                    )
                )
                SELECT AccountCode, AccountName
                FROM DelegableAccounts
                ORDER BY AccountName, AccountCode;",
                new { PrincipalId = principal.PrincipalId, AccessType = accessType })).ToList();

            var orgUnits = (await conn.QueryAsync<DelegationScopeOrgUnitOptionDto>(@"
                DECLARE @AccountId INT = (
                    SELECT AccountId
                    FROM Dim.Account
                    WHERE AccountCode = @AccountCode
                );

                WITH EffectiveScopes AS
                (
                    SELECT
                        @PrincipalId AS PrincipalId,
                        eff.AccessType,
                        eff.AccountId,
                        eff.ScopeType,
                        eff.OrgUnitId
                    FROM Sec.vPrincipalEffectiveAccess AS eff
                    WHERE eff.PrincipalId = @PrincipalId

                    UNION ALL

                    SELECT
                        @PrincipalId AS PrincipalId,
                        eff.AccessType,
                        eff.AccountId,
                        eff.ScopeType,
                        eff.OrgUnitId
                    FROM Sec.vUserGrantPrincipals AS gp
                    JOIN Sec.vPrincipalEffectiveAccess AS eff
                        ON eff.PrincipalId = gp.GrantPrincipalId
                    WHERE gp.UserPrincipalId = @PrincipalId
                ),
                AllowedOrgUnits AS
                (
                    SELECT DISTINCT
                        ou.OrgUnitId,
                        ou.AccountId,
                        acct.AccountCode,
                        ou.OrgUnitType,
                        ou.OrgUnitCode,
                        ou.OrgUnitName,
                        ou.Path
                    FROM App.vOrgUnits AS ou
                    JOIN Dim.Account AS acct ON acct.AccountId = ou.AccountId
                    WHERE ou.IsActive = 1
                      AND (@AccountId IS NULL OR ou.AccountId = @AccountId)
                      AND EXISTS
                      (
                          SELECT 1
                          FROM EffectiveScopes AS eff
                          LEFT JOIN Dim.OrgUnit AS effOrg ON eff.OrgUnitId = effOrg.OrgUnitId
                          WHERE
                                (
                                    eff.AccessType = 'ALL'
                                AND eff.ScopeType = 'NONE'
                                )
                             OR (
                                    @AccessType = 'ACCOUNT'
                                AND eff.AccessType = 'ACCOUNT'
                                AND eff.ScopeType = 'NONE'
                                AND eff.AccountId = ou.AccountId
                                )
                             OR (
                                    eff.AccessType = @AccessType
                                AND eff.ScopeType = 'ORGUNIT'
                                AND effOrg.Path IS NOT NULL
                                AND ou.Path LIKE effOrg.Path + '%'
                                AND (
                                       (eff.AccessType = 'ALL')
                                    OR (eff.AccessType = 'ACCOUNT' AND eff.AccountId = ou.AccountId)
                                )
                                )
                      )
                )
                SELECT
                    OrgUnitId,
                    AccountCode,
                    OrgUnitType,
                    OrgUnitCode,
                    OrgUnitName,
                    Path
                FROM AllowedOrgUnits
                ORDER BY AccountCode, Path;",
                new
                {
                    PrincipalId = principal.PrincipalId,
                    AccessType = accessType,
                    AccountCode = accountCode,
                })).ToList();

            return Results.Ok(new DelegationScopeOptionsDto(accounts, orgUnits));
        }).RequireAuthorization();

        // GET /delegations — super-admins see all (including platform-level
        // delegations with AccountCode='ALL'); others only see delegations
        // scoped to an account they can access.
        app.MapGet("/delegations", async (ClaimsPrincipal user, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            IEnumerable<DelegationDto> items;
            if (await platformAuth.HasPermissionAsync(user, conn, Permissions.SuperAdmin))
            {
                items = await conn.QueryAsync<DelegationDto>(@"
                    SELECT
                        PrincipalDelegationId,
                        DelegatorPrincipalId,
                        DelegatePrincipalId,
                        DelegatorName,
                        DelegatorType,
                        DelegateName,
                        DelegateType,
                        AccessType,
                        ScopeType,
                        AccountCode,
                        AccountName,
                        OrgUnitType,
                        OrgUnitCode,
                        OrgUnitName,
                        ValidFromDate,
                        ValidToDate,
                        IsActive,
                        CreatedOnUtc
                    FROM App.vDelegations
                    ORDER BY DelegatorName, DelegateName");
            }
            else
            {
                var currentUserId = await AccessScope.GetCurrentUserIdAsync(user, conn);
                if (currentUserId is null)
                    return Results.Ok(new ApiList<DelegationDto>(new List<DelegationDto>(), 0));

                items = await conn.QueryAsync<DelegationDto>($@"
                    {AccessScope.AccessibleAccountsCte}
                    SELECT
                        d.PrincipalDelegationId,
                        d.DelegatorPrincipalId,
                        d.DelegatePrincipalId,
                        d.DelegatorName,
                        d.DelegatorType,
                        d.DelegateName,
                        d.DelegateType,
                        d.AccessType,
                        d.ScopeType,
                        d.AccountCode,
                        d.AccountName,
                        d.OrgUnitType,
                        d.OrgUnitCode,
                        d.OrgUnitName,
                        d.ValidFromDate,
                        d.ValidToDate,
                        d.IsActive,
                        d.CreatedOnUtc
                    FROM App.vDelegations AS d
                    JOIN Dim.Account AS a ON a.AccountCode = d.AccountCode
                    WHERE a.AccountId IN (SELECT AccountId FROM AccessibleAccounts)
                    ORDER BY d.DelegatorName, d.DelegateName",
                    new { UserId = currentUserId.Value });
            }

            var list = items.ToList();
            return Results.Ok(new ApiList<DelegationDto>(list, list.Count));
        }).RequireAuthorization();

        // POST /delegations — Sec.GrantDelegation
        app.MapPost("/delegations", async (ClaimsPrincipal user, GrantDelegationRequest req, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            DateTime? validFromDate = null;
            DateTime? validToDate = null;
            DateOnly parsedValidFromDate = default;
            DateOnly parsedValidToDate = default;

            if (!string.IsNullOrWhiteSpace(req.ValidFromDate) &&
                !DateOnly.TryParse(req.ValidFromDate, out parsedValidFromDate))
            {
                return Results.BadRequest(new ApiError("INVALID_VALID_FROM_DATE", "Valid from date is invalid."));
            }

            if (!string.IsNullOrWhiteSpace(req.ValidToDate) &&
                !DateOnly.TryParse(req.ValidToDate, out parsedValidToDate))
            {
                return Results.BadRequest(new ApiError("INVALID_VALID_TO_DATE", "Valid to date is invalid."));
            }

            if (!string.IsNullOrWhiteSpace(req.ValidFromDate))
            {
                validFromDate = parsedValidFromDate.ToDateTime(TimeOnly.MinValue);
            }

            if (!string.IsNullOrWhiteSpace(req.ValidToDate))
            {
                validToDate = parsedValidToDate.ToDateTime(TimeOnly.MinValue);
            }

            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.GrantsManage))
                return Results.Forbid();

            var p = new DynamicParameters();
            p.Add("@DelegatorPrincipalType", req.DelegatorType);
            p.Add("@DelegatorIdentifier",    req.DelegatorIdentifier);
            p.Add("@DelegatePrincipalType",  req.DelegateType);
            p.Add("@DelegateIdentifier",     req.DelegateIdentifier);
            p.Add("@AccessType",             req.AccessType);
            p.Add("@AccountCode",            req.AccountCode);
            p.Add("@ScopeType",              req.ScopeType);
            p.Add("@OrgUnitType",            req.OrgUnitType);
            p.Add("@OrgUnitCode",            req.OrgUnitCode);
            p.Add("@ValidFromDate",          validFromDate);
            p.Add("@ValidToDate",            validToDate);

            try
            {
                await conn.ExecuteAsync("Sec.GrantDelegation", p,
                    commandType: System.Data.CommandType.StoredProcedure);
            }
            catch (SqlException ex) when (ex.Number is 50029 or 50030)
            {
                return Results.NotFound(new ApiError("PRINCIPAL_NOT_FOUND", ex.Message));
            }
            catch (SqlException ex) when (ex.Number is 50031 or 50032 or 50033 or 50034 or 50036 or 50041)
            {
                return Results.BadRequest(new ApiError("INVALID_DELEGATION", ex.Message));
            }
            catch (SqlException ex) when (ex.Number is 50035 or 50037)
            {
                return Results.NotFound(new ApiError("SCOPE_NOT_FOUND", ex.Message));
            }
            catch (SqlException ex) when (ex.Number == 50038)
            {
                return Results.BadRequest(new ApiError("DELEGATOR_LACKS_COVERAGE", ex.Message));
            }

            return Results.NoContent();
        }).RequireAuthorization();

        // DELETE /delegations/{id} — deactivate by ID
        app.MapDelete("/delegations/{id:int}", async (ClaimsPrincipal user, int id, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.GrantsManage))
                return Results.Forbid();
            var affected = await conn.ExecuteScalarAsync<int>(@"
                SELECT COUNT(1)
                FROM App.vDelegations
                WHERE PrincipalDelegationId = @Id",
                new { Id = id });

            if (affected > 0)
            {
                await conn.ExecuteAsync("Sec.usp_SetDelegationActive",
                    new { PrincipalDelegationId = id, IsActive = false },
                    commandType: System.Data.CommandType.StoredProcedure);
            }

            return affected == 0
                ? Results.NotFound(new ApiError("DELEGATION_NOT_FOUND", $"Delegation {id} not found."))
                : Results.NoContent();
        }).RequireAuthorization();

        // PATCH /delegations/{id}/status
        app.MapMethods("/delegations/{id:int}/status", new[] { "PATCH" }, async (ClaimsPrincipal user, int id, SetActiveRequest request, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.GrantsManage))
                return Results.Forbid();
            var affected = await conn.ExecuteScalarAsync<int>(@"
                SELECT COUNT(1)
                FROM App.vDelegations
                WHERE PrincipalDelegationId = @Id",
                new { Id = id });

            if (affected == 0)
            {
                return Results.NotFound(new ApiError("DELEGATION_NOT_FOUND", $"Delegation {id} not found."));
            }

            await conn.ExecuteAsync("Sec.usp_SetDelegationActive",
                new { PrincipalDelegationId = id, IsActive = request.IsActive },
                commandType: System.Data.CommandType.StoredProcedure);

            return Results.NoContent();
        }).RequireAuthorization();

        return app;
    }
}
