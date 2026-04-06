using System.Security.Claims;
using Dapper;
using GcePlatform.Api.Data;
using GcePlatform.Api.Models;
using GcePlatform.Api.Services;

namespace GcePlatform.Api.Endpoints;

public static class AccountEndpoints
{
    public static WebApplication MapAccountEndpoints(this WebApplication app)
    {
        // GET /accounts
        app.MapGet("/accounts", async (DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var items = await conn.QueryAsync<AccountDto>(@"
                SELECT
                    AccountId,
                    AccountCode,
                    AccountName,
                    IsActive,
                    SiteCount,
                    UserCount
                FROM App.vAccounts
                ORDER BY AccountName");

            var list = items.ToList();
            return Results.Ok(new ApiList<AccountDto>(list, list.Count));
        }).RequireAuthorization();

        // GET /accounts/{id}
        app.MapGet("/accounts/{id:int}", async (int id, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();
            var item = await conn.QuerySingleOrDefaultAsync<AccountDto>(@"
                SELECT
                    AccountId,
                    AccountCode,
                    AccountName,
                    IsActive,
                    SiteCount,
                    UserCount
                FROM App.vAccounts
                WHERE AccountId = @Id",
                new { Id = id });

            return item is null
                ? Results.NotFound(new ApiError("ACCOUNT_NOT_FOUND", $"Account {id} not found."))
                : Results.Ok(item);
        }).RequireAuthorization();

        // GET /accounts/{id}/users
        app.MapGet("/accounts/{id:int}/users", async (int id, DbConnectionFactory db) =>
        {
            using var conn = db.CreateConnection();

            var accountExists = await conn.ExecuteScalarAsync<int>(@"
                SELECT COUNT(1)
                FROM App.vAccounts
                WHERE AccountId = @Id",
                new { Id = id });

            if (accountExists == 0)
                return Results.NotFound(new ApiError("ACCOUNT_NOT_FOUND", $"Account {id} not found."));

            var items = await conn.QueryAsync<UserDto>(@"
                SELECT
                    u.UserId,
                    u.UPN,
                    u.DisplayName,
                    u.IsActive,
                    u.RoleCount,
                    u.RoleList,
                    scope.SiteCount,
                    1 AS AccountCount,
                    u.PackageCount,
                    u.ReportCount,
                    u.GapStatus
                FROM App.vUsers AS u
                JOIN
                (
                    SELECT
                        auth.UserPrincipalId,
                        COUNT(DISTINCT auth.SiteOrgUnitId) AS SiteCount
                    FROM Sec.vAuthorizedSitesDynamic AS auth
                    WHERE auth.AccountId = @Id
                    GROUP BY auth.UserPrincipalId
                ) AS scope
                    ON scope.UserPrincipalId = u.UserId
                ORDER BY u.DisplayName",
                new { Id = id });

            var list = items.ToList();
            return Results.Ok(new ApiList<UserDto>(list, list.Count));
        }).RequireAuthorization();

        // POST /accounts
        app.MapPost("/accounts", async (ClaimsPrincipal user, CreateAccountRequest request, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.AccountsManage))
                return Results.Forbid();

            var p = new DynamicParameters();
            p.Add("@AccountCode", request.AccountCode.ToUpperInvariant());
            p.Add("@AccountName", request.AccountName);
            p.Add("@IsActive", true);
            p.Add("@ApplyPolicies", true);
            p.Add("@AccountId", dbType: System.Data.DbType.Int32,
                  direction: System.Data.ParameterDirection.Output);

            await conn.ExecuteAsync("App.UpsertAccount", p,
                commandType: System.Data.CommandType.StoredProcedure);

            var newId = p.Get<int>("@AccountId");

            var created = await conn.QuerySingleAsync<AccountDto>(@"
                SELECT AccountId, AccountCode, AccountName,
                       IsActive, SiteCount, UserCount
                FROM App.vAccounts
                WHERE AccountId = @Id",
                new { Id = newId });

            return Results.Created($"/accounts/{newId}", created);
        }).RequireAuthorization();

        // PATCH /accounts/{id}/status
        app.MapMethods("/accounts/{id:int}/status", new[] { "PATCH" },
            async (ClaimsPrincipal user, int id, SetActiveRequest req, DbConnectionFactory db, PlatformAuthService platformAuth) =>
        {
            using var conn = db.CreateConnection();

            if (!await platformAuth.HasPermissionAsync(user, conn, Permissions.AccountsManage))
                return Results.Forbid();
            var item = await conn.QuerySingleOrDefaultAsync<AccountDto>(
                "SELECT AccountId, AccountCode, AccountName, CAST(IsActive AS bit) AS IsActive, SiteCount, UserCount FROM App.vAccounts WHERE AccountId = @Id",
                new { Id = id });

            if (item is null)
                return Results.NotFound(new ApiError("ACCOUNT_NOT_FOUND", $"Account {id} not found."));

            var p = new DynamicParameters();
            p.Add("@AccountCode",   item.AccountCode);
            p.Add("@AccountName",   item.AccountName);
            p.Add("@IsActive",      req.IsActive ? 1 : 0);
            p.Add("@ApplyPolicies", 0);
            p.Add("@AccountId",     dbType: System.Data.DbType.Int32,
                                    direction: System.Data.ParameterDirection.Output);

            await conn.ExecuteAsync("App.UpsertAccount", p,
                commandType: System.Data.CommandType.StoredProcedure);

            return Results.NoContent();
        }).RequireAuthorization();

        return app;
    }
}
