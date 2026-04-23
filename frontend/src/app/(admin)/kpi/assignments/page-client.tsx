'use client'

import { useEffect, useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { PageHeader } from '@/components/shared/page-header'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { api } from '@/lib/api'
import type { KpiAssignment, KpiAssignmentTemplate } from '@/types/api'
import { AssignmentsTable } from './assignments-table'
import { AssignmentTemplatesTable } from './assignment-templates-table'
import { AssignKpisWizard } from './assign-kpis-wizard'
import { useAccount } from '@/contexts/account-context'
import { usePermissions } from '@/hooks/usePermissions'
import { useAccessibleSites } from '@/hooks/useAccessibleSites'

const ALL_FILTER = 'all'
const ACCOUNT_WIDE_FILTER = '__account_wide__'
const NO_GROUP_FILTER = '__nogroup__'

type FilterableAssignmentScope = Pick<KpiAssignment, 'accountCode' | 'siteCode' | 'siteName' | 'isAccountWide' | 'assignmentGroupName'>
type FilterableTemplateScope = Pick<KpiAssignmentTemplate, 'accountCode' | 'siteCode' | 'siteName' | 'isAccountWide' | 'assignmentGroupName'>

function matchesSharedFilters<T extends FilterableAssignmentScope | FilterableTemplateScope>(
  item: T,
  accountFilter: string,
  scopeFilter: string,
  groupFilter: string,
) {
  const matchesAccount = accountFilter === ALL_FILTER || item.accountCode === accountFilter
  const matchesScope = scopeFilter === ALL_FILTER
    || (scopeFilter === ACCOUNT_WIDE_FILTER && item.isAccountWide)
    || item.siteCode === scopeFilter
  const matchesGroup = groupFilter === ALL_FILTER
    || (groupFilter === NO_GROUP_FILTER && item.assignmentGroupName === null)
    || item.assignmentGroupName === groupFilter

  return matchesAccount && matchesScope && matchesGroup
}

export function KpiAssignmentsPageClient() {
  const { selectedAccount } = useAccount()
  const { isSuperAdmin } = usePermissions()
  const accessible = useAccessibleSites()
  const accountId = selectedAccount?.accountId

  // Backend scopes to account-level; narrow further to sites the caller can
  // actually reach. Account-wide rows (item.siteCode === null / isAccountWide)
  // always stay — they implicitly apply to every site in the account.
  const isSiteAccessible = useMemo(() => {
    if (accessible.mode === 'all') return () => true
    const { siteCodes } = accessible
    return (siteCode: string | null | undefined, isAccountWide: boolean) =>
      isAccountWide || !siteCode || siteCodes.has(siteCode)
  }, [accessible])

  // Non-super-admins are pinned to their selected account. Super admins default
  // to the selected account but can opt into the cross-account "All accounts"
  // view via the filter dropdown below.
  const [accountFilter, setAccountFilter] = useState<string>(
    selectedAccount?.accountCode ?? ALL_FILTER,
  )
  const [scopeFilter, setScopeFilter] = useState<string>(ALL_FILTER)
  const [groupFilter, setGroupFilter] = useState<string>(ALL_FILTER)

  // Keep the filter in sync with the sidebar account switcher.
  useEffect(() => {
    if (!selectedAccount) return
    if (!isSuperAdmin) {
      setAccountFilter(selectedAccount.accountCode)
      return
    }
    // Super admins: respect an explicit "All accounts" selection,
    // otherwise follow the sidebar selection.
    setAccountFilter((prev) =>
      prev === ALL_FILTER ? ALL_FILTER : selectedAccount.accountCode,
    )
  }, [selectedAccount, isSuperAdmin])

  // Super admins can fetch the cross-account accounts list for the filter
  // dropdown. Tenant admins don't need it — their filter is locked.
  const accountsQuery = useQuery({
    queryKey: ['accounts'],
    queryFn: () => api.accounts.list(),
    enabled: isSuperAdmin,
  })

  const periodsQuery = useQuery({
    queryKey: ['kpi', 'periods'],
    queryFn: () => api.kpi.periods.list(),
  })

  // Resolve which accountId to send to the API:
  //   - super admin + "All accounts" filter → undefined (cross-account fetch)
  //   - otherwise → the selectedAccount.accountId (narrow scope)
  const apiAccountId = useMemo(() => {
    if (isSuperAdmin && accountFilter === ALL_FILTER) return undefined
    return accountId
  }, [isSuperAdmin, accountFilter, accountId])

  const templatesQuery = useQuery({
    queryKey: ['kpi', 'assignment-templates', apiAccountId ?? 'all'],
    queryFn: () => api.kpi.assignments.templates.list({ accountId: apiAccountId }),
    enabled: isSuperAdmin || !!accountId,
  })

  const assignmentsQuery = useQuery({
    queryKey: ['kpi', 'assignments', apiAccountId ?? 'all'],
    queryFn: () => api.kpi.assignments.list({ accountId: apiAccountId }),
    enabled: isSuperAdmin || !!accountId,
  })

  // Distinct group names across templates + assignments for the current account filter
  const availableGroups = useMemo(() => {
    const items = [
      ...(templatesQuery.data?.items ?? []),
      ...(assignmentsQuery.data?.items ?? []),
    ].filter((item) => accountFilter === ALL_FILTER || item.accountCode === accountFilter)

    const names = new Set<string | null>()
    items.forEach((item) => names.add(item.assignmentGroupName))
    // Only show the dropdown when there's at least one named group
    if (!Array.from(names).some((n) => n !== null)) return []
    return Array.from(names).sort((a, b) => {
      if (a === null) return 1
      if (b === null) return -1
      return a.localeCompare(b)
    })
  }, [accountFilter, templatesQuery.data?.items, assignmentsQuery.data?.items])

  const availableScopes = useMemo(() => {
    const items = [
      ...(templatesQuery.data?.items ?? []),
      ...(assignmentsQuery.data?.items ?? []),
    ].filter((item) => isSiteAccessible(item.siteCode, item.isAccountWide))

    const scopedItems = accountFilter === ALL_FILTER
      ? items
      : items.filter((item) => item.accountCode === accountFilter)

    const hasAccountWide = scopedItems.some((item) => item.isAccountWide)
    const siteMap = new Map<string, string>()

    scopedItems.forEach((item) => {
      if (item.siteCode) {
        siteMap.set(item.siteCode, item.siteName ?? item.siteCode)
      }
    })

    return {
      hasAccountWide,
      sites: Array.from(siteMap.entries()).sort((a, b) => a[0].localeCompare(b[0])),
    }
  }, [accountFilter, assignmentsQuery.data?.items, templatesQuery.data?.items, isSiteAccessible])

  useEffect(() => {
    if (scopeFilter === ALL_FILTER) return
    if (scopeFilter === ACCOUNT_WIDE_FILTER && availableScopes.hasAccountWide) return
    if (availableScopes.sites.some(([siteCode]) => siteCode === scopeFilter)) return
    setScopeFilter(ALL_FILTER)
  }, [availableScopes, scopeFilter])

  const filteredTemplates = useMemo(
    () =>
      (templatesQuery.data?.items ?? [])
        .filter((item) => isSiteAccessible(item.siteCode, item.isAccountWide))
        .filter((item) => matchesSharedFilters(item, accountFilter, scopeFilter, groupFilter)),
    [accountFilter, scopeFilter, groupFilter, templatesQuery.data?.items, isSiteAccessible],
  )

  const filteredAssignments = useMemo(
    () =>
      (assignmentsQuery.data?.items ?? [])
        .filter((item) => isSiteAccessible(item.siteCode, item.isAccountWide))
        .filter((item) => matchesSharedFilters(item, accountFilter, scopeFilter, groupFilter)),
    [accountFilter, assignmentsQuery.data?.items, scopeFilter, groupFilter, isSiteAccessible],
  )

  return (
    <div className="space-y-6">
      <PageHeader
        title="Assignments"
        description="Assign KPIs to cadence schedules once, then monitor the generated reporting instances below."
        actions={<AssignKpisWizard />}
      />

      <section className="space-y-3">
        <div className="flex flex-wrap items-center gap-2">
          {isSuperAdmin && (
            <div className="flex items-center gap-2">
              <span className="text-sm text-muted-foreground">Account:</span>
              <Select
                value={accountFilter}
                onValueChange={(value) => {
                  setAccountFilter(value)
                  setScopeFilter(ALL_FILTER)
                  setGroupFilter(ALL_FILTER)
                }}
              >
                <SelectTrigger className="h-8 w-44 text-sm">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value={ALL_FILTER}>All accounts</SelectItem>
                  {(accountsQuery.data?.items ?? []).map((account) => (
                    <SelectItem key={account.accountCode} value={account.accountCode}>
                      {account.accountName}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          )}

          <div className="flex items-center gap-2">
            <span className="text-sm text-muted-foreground">Scope:</span>
            <Select value={scopeFilter} onValueChange={setScopeFilter}>
              <SelectTrigger className="h-8 w-44 text-sm">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value={ALL_FILTER}>All scopes</SelectItem>
                {availableScopes.hasAccountWide ? (
                  <SelectItem value={ACCOUNT_WIDE_FILTER}>Account-wide only</SelectItem>
                ) : null}
                {availableScopes.sites.map(([siteCode, siteName]) => (
                  <SelectItem key={siteCode} value={siteCode}>
                    {siteCode} {siteName !== siteCode ? `· ${siteName}` : ''}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {availableGroups.length > 0 && (
            <div className="flex items-center gap-2">
              <span className="text-sm text-muted-foreground">Group:</span>
              <Select value={groupFilter} onValueChange={setGroupFilter}>
                <SelectTrigger className="h-8 w-44 text-sm">
                  <SelectValue>
                    {groupFilter === ALL_FILTER
                      ? 'All groups'
                      : groupFilter === NO_GROUP_FILTER
                        ? '(No group)'
                        : groupFilter}
                  </SelectValue>
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value={ALL_FILTER}>All groups</SelectItem>
                  {availableGroups.map((g) =>
                    g === null ? (
                      <SelectItem key={NO_GROUP_FILTER} value={NO_GROUP_FILTER}>(No group)</SelectItem>
                    ) : (
                      <SelectItem key={g} value={g}>{g}</SelectItem>
                    )
                  )}
                </SelectContent>
              </Select>
            </div>
          )}
        </div>
      </section>

      <section className="space-y-3">
        <div>
          <h2 className="text-base font-semibold">Recurring templates</h2>
          <p className="text-sm text-muted-foreground">
            Define which KPI applies to which account or site, and which cadence schedule should drive its recurrence.
          </p>
        </div>
        <AssignmentTemplatesTable
          data={filteredTemplates}
          isLoading={templatesQuery.isLoading}
          isError={templatesQuery.isError}
          error={templatesQuery.error}
        />
      </section>

      <section className="space-y-3">
        <div>
          <h2 className="text-base font-semibold">Generated assignment instances</h2>
          <p className="text-sm text-muted-foreground">
            These are the generated reporting instances produced from the schedule-linked templates and current period calendar.
          </p>
        </div>
        <AssignmentsTable
          data={filteredAssignments}
          periods={periodsQuery.data?.items ?? []}
          isLoading={assignmentsQuery.isLoading || periodsQuery.isLoading}
          isError={assignmentsQuery.isError || periodsQuery.isError}
          error={assignmentsQuery.error ?? periodsQuery.error}
        />
      </section>
    </div>
  )
}
