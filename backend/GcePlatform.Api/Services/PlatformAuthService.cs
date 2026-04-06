using System.Data;
using System.Security.Claims;
using Dapper;

namespace GcePlatform.Api.Services;

/// <summary>
/// Resolves functional platform permissions for the current authenticated user.
/// Platform permissions gate write operations and sensitive sections in the admin portal.
/// They are separate from the Sec-schema data-access RBAC which controls which
/// accounts/sites/packages a user can see.
/// </summary>
public class PlatformAuthService
{
    // During initial deployment, set PLATFORM_SUPER_ADMIN_UPN to your own UPN so you
    // can log in and assign yourself the real Super Admin platform role.
    // Clear the env var once bootstrapping is complete.
    private readonly string? _bootstrapSuperAdminUpn;

    private const string DevBypassScheme = "DevBypass";

    public PlatformAuthService(IConfiguration configuration)
    {
        _bootstrapSuperAdminUpn = configuration["PlatformSuperAdminUpn"];
    }

    /// <summary>
    /// Returns the platform PermissionCode values the user holds.
    /// In dev-bypass mode, returns all permission codes without hitting the DB.
    /// </summary>
    public async Task<IEnumerable<string>> GetPermissionsAsync(
        ClaimsPrincipal user,
        IDbConnection conn)
    {
        // Dev bypass — return all permissions so every feature is accessible locally
        if (user.Identity?.AuthenticationType == DevBypassScheme)
            return AllPermissions;

        var upn = GetUpn(user);
        if (string.IsNullOrEmpty(upn))
            return Array.Empty<string>();

        // Bootstrap: if this UPN is the configured super-admin seed and has no
        // DB memberships yet, return the super-admin permission so they can
        // assign themselves a real role.
        if (!string.IsNullOrEmpty(_bootstrapSuperAdminUpn) &&
            string.Equals(upn, _bootstrapSuperAdminUpn, StringComparison.OrdinalIgnoreCase))
        {
            var count = await conn.ExecuteScalarAsync<int>(
                "SELECT COUNT(*) FROM App.vPlatformRoleMembers WHERE UPN = @Upn",
                new { Upn = upn });

            if (count == 0)
                return new[] { Permissions.SuperAdmin };
        }

        var userId = await conn.ExecuteScalarAsync<int?>(
            "SELECT UserId FROM App.vUsers WHERE UPN = @Upn AND IsActive = 1",
            new { Upn = upn });

        if (userId is null)
            return Array.Empty<string>();

        var permissions = await conn.QueryAsync<string>(
            "EXEC App.usp_GetUserPlatformPermissions @UserId",
            new { UserId = userId });

        return permissions;
    }

    /// <summary>
    /// Returns true if the user holds the specified permission OR the super-admin bypass.
    /// </summary>
    public async Task<bool> HasPermissionAsync(
        ClaimsPrincipal user,
        IDbConnection conn,
        string permission)
    {
        var permissions = await GetPermissionsAsync(user, conn);
        var list = permissions.ToList();
        return list.Contains(Permissions.SuperAdmin) ||
               list.Contains(permission);
    }

    /// <summary>
    /// Extracts the UPN from common JWT claim types issued by Azure AD / Entra ID.
    /// </summary>
    public static string? GetUpn(ClaimsPrincipal user) =>
        user.FindFirstValue("preferred_username") ??
        user.FindFirstValue(ClaimTypes.Email) ??
        user.FindFirstValue(ClaimTypes.Upn) ??
        user.FindFirstValue(ClaimTypes.Name);

    private static readonly string[] AllPermissions = new[]
    {
        Permissions.SuperAdmin,
        Permissions.AccountsManage,
        Permissions.UsersManage,
        Permissions.GrantsManage,
        Permissions.KpiManage,
        Permissions.PoliciesManage,
        Permissions.PlatformRolesManage,
    };
}

/// <summary>Centralised permission code constants — kept in sync with App.PlatformPermission seed data.</summary>
public static class Permissions
{
    public const string SuperAdmin          = "platform.super_admin";
    public const string AccountsManage      = "accounts.manage";
    public const string UsersManage         = "users.manage";
    public const string GrantsManage        = "grants.manage";
    public const string KpiManage           = "kpi.manage";
    public const string PoliciesManage      = "policies.manage";
    public const string PlatformRolesManage = "platform_roles.manage";
}
