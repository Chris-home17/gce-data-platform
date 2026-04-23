'use client'

import { useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import { api } from '@/lib/api'
import { usePermissions } from '@/hooks/usePermissions'

/**
 * Describes the set of sites the current user should see in tenant-scoped lists
 * (sites table, KPI monitoring, dashboard counts).
 *
 * - `mode: 'all'` — platform super-admins see every site. No filter is applied.
 * - `mode: 'scoped'` — every other user, including tenant account admins, is
 *   narrowed to the sites their roles/delegations resolve to. Account-level
 *   platform permissions (ACCOUNTS_MANAGE, USERS_MANAGE, KPI_MANAGE) do NOT
 *   bypass the filter — those permissions authorize *operations*, not
 *   visibility of sites outside the user's effective access scope.
 *
 * `siteCodes` is the canonical set of `orgUnitCode` / `siteCode` values to
 * keep. While the underlying resolvedAccess query is in flight, `isLoading`
 * is true and callers should render an empty result rather than flashing
 * unfiltered data.
 */
export type AccessibleSites =
  | { mode: 'all'; isLoading: false }
  | { mode: 'scoped'; isLoading: boolean; siteCodes: Set<string> }

/**
 * Resolves which sites the current user is allowed to see. Backed by
 * `api.users.resolvedAccess(userId)`, which the backend computes from the
 * user's roles, delegations, and direct grants.
 *
 * Callers should treat this as a UI-visibility filter. The backend remains
 * the authorization boundary — if it returns a site the user shouldn't see,
 * this hook won't know to hide it. In the opposite direction, this hook
 * prevents *over-disclosure from underscoped endpoints* (e.g. `/org-units`
 * which today returns every unit in the account) by narrowing the render.
 */
export function useAccessibleSites(): AccessibleSites {
  const { userId, isSuperAdmin } = usePermissions()

  const { data, isLoading } = useQuery({
    queryKey: ['users', userId, 'resolved-access'],
    queryFn: () => api.users.resolvedAccess(userId!),
    enabled: !!userId && !isSuperAdmin,
  })

  const siteCodes = useMemo(() => {
    const set = new Set<string>()
    data?.sites.forEach((site) => set.add(site.siteCode))
    return set
  }, [data])

  if (isSuperAdmin) {
    return { mode: 'all', isLoading: false }
  }

  // Treat "no userId in session yet" as still-loading rather than an empty
  // access set — this avoids flashing an empty list during login hydration.
  return { mode: 'scoped', isLoading: isLoading || !userId, siteCodes }
}
