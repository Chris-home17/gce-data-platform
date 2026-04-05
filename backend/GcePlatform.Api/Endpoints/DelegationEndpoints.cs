using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Models;

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
                    IsActive,
                    CreatedOnUtc
                FROM App.vDelegations
                ORDER BY DelegatorName, DelegateName");

            var list = items.ToList();
            return Results.Ok(new ApiList<DelegationDto>(list, list.Count));
        }).RequireAuthorization();

        // POST /delegations — Sec.GrantDelegation
        app.MapPost("/delegations", async (GrantDelegationRequest req, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
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

            await conn.ExecuteAsync("Sec.GrantDelegation", p,
                commandType: System.Data.CommandType.StoredProcedure);

            return Results.NoContent();
        }).RequireAuthorization();

        // DELETE /delegations/{id} — deactivate by ID
        app.MapDelete("/delegations/{id:int}", async (int id, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
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

        return app;
    }
}
