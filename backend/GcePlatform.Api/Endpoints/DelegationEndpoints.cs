using System.Security.Claims;
using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Models;
using GcePlatform.Api.Services;
using Microsoft.Data.SqlClient;

namespace GcePlatform.Api.Endpoints;

public static class DelegationEndpoints
{
    public static WebApplication MapDelegationEndpoints(this WebApplication app)
    {
        // GET /delegations
        app.MapGet("/delegations", async (DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var items = await conn.QueryAsync<DelegationDto>(@"
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

            var list = items.ToList();
            return Results.Ok(new ApiList<DelegationDto>(list, list.Count));
        }).RequireAuthorization();

        // POST /delegations — Sec.GrantDelegation
        app.MapPost("/delegations", async (ClaimsPrincipal user, GrantDelegationRequest req, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            DateTime? validFromDate = null;
            DateTime? validToDate = null;

            if (!string.IsNullOrWhiteSpace(req.ValidFromDate) &&
                !DateOnly.TryParse(req.ValidFromDate, out var parsedValidFromDate))
            {
                return Results.BadRequest(new ApiError("INVALID_VALID_FROM_DATE", "Valid from date is invalid."));
            }

            if (!string.IsNullOrWhiteSpace(req.ValidToDate) &&
                !DateOnly.TryParse(req.ValidToDate, out var parsedValidToDate))
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
