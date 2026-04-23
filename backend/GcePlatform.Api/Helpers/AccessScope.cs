using System.Data;
using System.Security.Claims;
using Dapper;
using GcePlatform.Api.Services;

namespace GcePlatform.Api.Helpers;

// Shared scoping primitives used by non-super-admin list endpoints.
//
// Usage: endpoints that must not leak cross-tenant data branch on
// PlatformAuthService.HasPermissionAsync(..., Permissions.SuperAdmin). In the
// non-super-admin branch, resolve the caller via GetCurrentUserIdAsync and
// prepend AccessibleAccountsCte to the query, then filter with
// `AccountId IN (SELECT AccountId FROM AccessibleAccounts)`.
public static class AccessScope
{
    // Resolves the current user's Sec.[User].UserId from their UPN claim.
    // Returns null for callers that have no active DB row (e.g. a stale token
    // after a user is deactivated).
    public static async Task<int?> GetCurrentUserIdAsync(ClaimsPrincipal user, IDbConnection conn)
    {
        var upn = PlatformAuthService.GetUpn(user);
        if (string.IsNullOrWhiteSpace(upn))
            return null;

        return await conn.ExecuteScalarAsync<int?>(
            "SELECT UserId FROM App.vUsers WHERE UPN = @Upn AND IsActive = 1",
            new { Upn = upn });
    }

    // Checks whether the caller identified by @CallerUserId can see the user
    // at @TargetUserId. Returns true when: the caller is super-admin (resolve
    // with PlatformAuthService before calling this), the caller is the target,
    // or the target has at least one authorized site in an account the caller
    // can reach. Intended for gating /users/{id}/* sub-resource endpoints.
    public static async Task<bool> CanAccessUserAsync(
        IDbConnection conn,
        int callerUserId,
        int targetUserId)
    {
        if (callerUserId == targetUserId) return true;

        var sql = AccessibleAccountsCte + @"
            SELECT CAST(
                CASE WHEN EXISTS
                (
                    SELECT 1
                    FROM Sec.vAuthorizedSitesDynamic AS auth
                    WHERE auth.UserPrincipalId = @TargetUserId
                      AND auth.AccountId IN (SELECT AccountId FROM AccessibleAccounts)
                )
                THEN 1 ELSE 0 END AS bit)";

        return await conn.ExecuteScalarAsync<bool>(sql,
            new { UserId = callerUserId, TargetUserId = targetUserId });
    }

    // CTE chain that defines `AccessibleAccounts(AccountId)` for the caller
    // passed as the @UserId parameter. The CTE walks the caller's direct and
    // role-inherited grants plus org-unit scopes and unions every distinct
    // AccountId they can reach. Callers must supply @UserId as a Dapper
    // parameter and append their own SELECT to this string.
    public const string AccessibleAccountsCte = @"
        WITH UserGrants AS
        (
            SELECT
                eff.AccessType,
                eff.AccountId,
                eff.ScopeType,
                eff.OrgUnitId
            FROM Sec.vUserGrantPrincipals AS gp
            JOIN Sec.vPrincipalEffectiveAccess AS eff
                ON eff.PrincipalId = gp.GrantPrincipalId
            WHERE gp.UserPrincipalId = @UserId
        ),
        AccessibleAccounts AS
        (
            SELECT DISTINCT a.AccountId
            FROM UserGrants AS g
            JOIN Dim.Account AS a
                ON g.ScopeType = 'NONE'
               AND (g.AccessType = 'ALL'
                    OR (g.AccessType = 'ACCOUNT' AND a.AccountId = g.AccountId))

            UNION

            SELECT DISTINCT site.AccountId
            FROM UserGrants AS g
            JOIN Dim.OrgUnit AS base
                ON g.ScopeType = 'ORGUNIT'
               AND g.OrgUnitId = base.OrgUnitId
            JOIN Dim.OrgUnit AS site
                ON site.Path LIKE base.Path + '%'
            WHERE site.AccountId IS NOT NULL
              AND (g.AccessType = 'ALL'
                   OR (g.AccessType = 'ACCOUNT' AND site.AccountId = g.AccountId))
        )";
}
