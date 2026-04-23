import { PERMISSIONS, type Permission } from '@/types/api'

/**
 * Route → required permission map.
 *
 * Single source of truth for which permission a user needs to reach each admin
 * route. Consumed by:
 *   - `(admin)/layout-guard.tsx` — blocks direct-URL navigation for users
 *     without the required permission.
 *   - `components/layout/sidebar.tsx` — hides nav items the user can't reach.
 *
 * Routes not listed here are account-scoped pages that any tenant admin can
 * reach (Dashboard, Users, Sites, KPI Monitoring). Those pages are still
 * responsible for scoping their own data to `useAccount().selectedAccount`.
 *
 * Match order: the longest prefix wins. `/kpi/assignments` is checked before
 * `/kpi`, so nested routes can tighten or loosen their parent.
 */
export const ROUTE_PERMISSIONS: ReadonlyArray<{ prefix: string; permission: Permission }> = [
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

  // KPI admin (KPI_MANAGE)
  { prefix: '/kpi/definitions',   permission: PERMISSIONS.KPI_MANAGE },
  { prefix: '/kpi/periods',       permission: PERMISSIONS.KPI_MANAGE },
  { prefix: '/kpi/packages',      permission: PERMISSIONS.KPI_MANAGE },
  { prefix: '/kpi/assignments',   permission: PERMISSIONS.KPI_MANAGE },
]

/**
 * Returns the permission required to access a given pathname, or `null` if the
 * route is open to all authenticated admin users.
 *
 * Longest prefix wins so nested routes (e.g. `/kpi/assignments`) can be listed
 * before their parent (e.g. `/kpi`) without being shadowed.
 */
export function getRequiredPermission(pathname: string): Permission | null {
  const sorted = [...ROUTE_PERMISSIONS].sort((a, b) => b.prefix.length - a.prefix.length)
  for (const { prefix, permission } of sorted) {
    if (pathname === prefix || pathname.startsWith(`${prefix}/`)) {
      return permission
    }
  }
  return null
}
