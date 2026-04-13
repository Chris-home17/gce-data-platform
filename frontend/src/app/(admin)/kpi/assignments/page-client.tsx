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
import { NewAssignmentSheet } from './new-assignment-sheet'

const ALL_FILTER = 'all'
const ACCOUNT_WIDE_FILTER = '__account_wide__'

type FilterableAssignmentScope = Pick<KpiAssignment, 'accountCode' | 'siteCode' | 'siteName' | 'isAccountWide'>
type FilterableTemplateScope = Pick<KpiAssignmentTemplate, 'accountCode' | 'siteCode' | 'siteName' | 'isAccountWide'>

function matchesSharedFilters<T extends FilterableAssignmentScope | FilterableTemplateScope>(
  item: T,
  accountFilter: string,
  scopeFilter: string,
) {
  const matchesAccount = accountFilter === ALL_FILTER || item.accountCode === accountFilter
  const matchesScope = scopeFilter === ALL_FILTER
    || (scopeFilter === ACCOUNT_WIDE_FILTER && item.isAccountWide)
    || item.siteCode === scopeFilter

  return matchesAccount && matchesScope
}

export function KpiAssignmentsPageClient() {
  const [accountFilter, setAccountFilter] = useState<string>(ALL_FILTER)
  const [scopeFilter, setScopeFilter] = useState<string>(ALL_FILTER)

  const accountsQuery = useQuery({
    queryKey: ['accounts'],
    queryFn: () => api.accounts.list(),
  })

  const periodsQuery = useQuery({
    queryKey: ['kpi', 'periods'],
    queryFn: () => api.kpi.periods.list(),
  })

  const templatesQuery = useQuery({
    queryKey: ['kpi', 'assignment-templates'],
    queryFn: () => api.kpi.assignments.templates.list(),
  })

  const assignmentsQuery = useQuery({
    queryKey: ['kpi', 'assignments'],
    queryFn: () => api.kpi.assignments.list(),
  })

  const availableScopes = useMemo(() => {
    const items = [
      ...(templatesQuery.data?.items ?? []),
      ...(assignmentsQuery.data?.items ?? []),
    ]

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
  }, [accountFilter, assignmentsQuery.data?.items, templatesQuery.data?.items])

  useEffect(() => {
    if (scopeFilter === ALL_FILTER) return
    if (scopeFilter === ACCOUNT_WIDE_FILTER && availableScopes.hasAccountWide) return
    if (availableScopes.sites.some(([siteCode]) => siteCode === scopeFilter)) return
    setScopeFilter(ALL_FILTER)
  }, [availableScopes, scopeFilter])

  const filteredTemplates = useMemo(
    () => (templatesQuery.data?.items ?? []).filter((item) => matchesSharedFilters(item, accountFilter, scopeFilter)),
    [accountFilter, scopeFilter, templatesQuery.data?.items],
  )

  const filteredAssignments = useMemo(
    () => (assignmentsQuery.data?.items ?? []).filter((item) => matchesSharedFilters(item, accountFilter, scopeFilter)),
    [accountFilter, assignmentsQuery.data?.items, scopeFilter],
  )

  return (
    <div className="space-y-6">
      <PageHeader
        title="Assignments"
        description="Assign KPIs to cadence schedules once, then monitor the generated reporting instances below."
        actions={<NewAssignmentSheet />}
      />

      <section className="space-y-3">
        <div className="flex flex-wrap items-center gap-2">
          <div className="flex items-center gap-2">
            <span className="text-sm text-muted-foreground">Account:</span>
            <Select
              value={accountFilter}
              onValueChange={(value) => {
                setAccountFilter(value)
                setScopeFilter(ALL_FILTER)
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
