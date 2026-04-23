import { PERMISSIONS, type Permission } from '@/types/api'

/**
 * Route → required permission(s) map.
 *
 * Single source of truth for which permission a user needs to reach each admin
 * route. Consumed by:
 *   - `(admin)/admin-shell.tsx` — blocks direct-URL navigation for users
 *     without the required permission.
 *   - `components/layout/sidebar.tsx` — hides nav items the user can't reach.
 *
 * A route may require a single permission, or an array meaning "any of". The
 * array form is how we express rules like "KPI Assignments needs kpi.assign
 * OR kpi.admin" — kpi.admin is a strict superset of kpi.assign on every check.
 *
 * Routes not listed here are account-scoped pages that any tenant admin can
 * reach (Dashboard, Users, Sites, KPI Monitoring). Those pages are still
 * responsible for scoping their own data to `useAccount().selectedAccount`.
 *
 * Match order: the longest prefix wins. `/kpi/assignments` is checked before
 * `/kpi`, so nested routes can tighten or loosen their parent.
 */
export type RequiredPermission = Permission | readonly Permission[]

export const ROUTE_PERMISSIONS: ReadonlyArray<{ prefix: string; permission: RequiredPermission }> = [
  // Platform-wide (Super Admin only)
  { prefix: '/accounts',          permission: PERMISSIONS.SUPER_ADMIN },
  { prefix: '/packages',          permission: PERMISSIONS.SUPER_ADMIN },
  { prefix: '/platform-roles',    permission: PERMISSIONS.SUPER_ADMIN },
  { prefix: '/tags',              permission: PERMISSIONS.SUPER_ADMIN },
  { prefix: '/reports',           permission: PERMISSIONS.SUPER_ADMIN },
  { prefix: '/coverage',          permission: PERMISSIONS.SUPER_ADMIN },
  { prefix: '/source-mapping',    permission: PERMISSIONS.SUPER_ADMIN },
  { prefix: '/shared-geography',  permission: PERMISSIONS.SUPER_ADMIN },

  // Access control (platform permissions)
  { prefix: '/roles',             permission: PERMISSIONS.PLATFORM_ROLES_MANAGE },
  { prefix: '/delegations',       permission: PERMISSIONS.GRANTS_MANAGE },
  { prefix: '/policies',          permission: PERMISSIONS.POLICIES_MANAGE },

  // KPI catalog authoring — KPI Admin only
  { prefix: '/kpi/definitions',   permission: PERMISSIONS.KPI_ADMIN },
  { prefix: '/kpi/periods',       permission: PERMISSIONS.KPI_ADMIN },
  { prefix: '/kpi/packages',      permission: PERMISSIONS.KPI_ADMIN },
  // KPI Assignments — account-side managers (KPI Assign) or admins
  { prefix: '/kpi/assignments',   permission: [PERMISSIONS.KPI_ASSIGN, PERMISSIONS.KPI_ADMIN] },
]

/**
 * Returns the permission(s) required to access a given pathname, or `null` if
 * the route is open to all authenticated admin users. Callers should use
 * `hasRequiredPermission` (below) rather than interpreting the return shape
 * themselves.
 *
 * Longest prefix wins so nested routes (e.g. `/kpi/assignments`) can be listed
 * before their parent (e.g. `/kpi`) without being shadowed.
 */
export function getRequiredPermission(pathname: string): RequiredPermission | null {
  const sorted = [...ROUTE_PERMISSIONS].sort((a, b) => b.prefix.length - a.prefix.length)
  for (const { prefix, permission } of sorted) {
    if (pathname === prefix || pathname.startsWith(`${prefix}/`)) {
      return permission
    }
  }
  return null
}

/**
 * Predicate: does `can(permission)` satisfy the RequiredPermission shape?
 * Hides the single-vs-array discriminant from call sites.
 */
export function hasRequiredPermission(
  required: RequiredPermission,
  can: (permission: string) => boolean,
): boolean {
  return Array.isArray(required) ? required.some((p) => can(p)) : can(required as Permission)
}
