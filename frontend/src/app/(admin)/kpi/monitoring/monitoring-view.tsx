'use client'

import { useState, useMemo, useEffect } from 'react'
import { useQuery, useMutation } from '@tanstack/react-query'
import { useRouter } from 'next/navigation'
import { AlertCircle, CheckCircle2, Lock, AlertTriangle, MoreHorizontal, Link2 } from 'lucide-react'
import { toast } from 'sonner'
import { api } from '@/lib/api'
import { cn, formatPercent } from '@/lib/utils'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { DataTable } from '@/components/shared/data-table'
import type { ColumnDef } from '@tanstack/react-table'
import type { KpiPeriod, SiteCompletion } from '@/types/api'
import { useAccount } from '@/contexts/account-context'
import { usePermissions } from '@/hooks/usePermissions'
import { useAccessibleSites } from '@/hooks/useAccessibleSites'

const KPI_MONITORING_REFRESH_EVENT = 'gce:kpi-monitoring-refresh'

function formatScheduleRef(periodScheduleId: number) {
  return `SCH-${periodScheduleId}`
}

function toPeriodSortValue(period: KpiPeriod) {
  return period.periodYear * 100 + period.periodMonth
}

function selectCurrentPeriod(periods: KpiPeriod[]) {
  if (periods.length === 0) return null

  const today = new Date()
  const currentMonthPeriods = periods.filter(
    (period) =>
      period.periodYear === today.getFullYear()
      && period.periodMonth === today.getMonth() + 1,
  )

  if (currentMonthPeriods.length > 0) {
    return [...currentMonthPeriods].sort((a, b) => {
      const priority = { Open: 0, Draft: 1, Closed: 2, Distributed: 3 }
      return (priority[a.status] ?? 4) - (priority[b.status] ?? 4)
        || a.periodScheduleId - b.periodScheduleId
    })[0]
  }

  const activeWindow = periods.find((period) => {
    const openDate = new Date(`${period.submissionOpenDate}T00:00:00`)
    const closeDate = new Date(`${period.submissionCloseDate}T23:59:59`)
    return today >= openDate && today <= closeDate
  })

  if (activeWindow) return activeWindow

  const nextUpcoming = [...periods]
    .filter((period) => new Date(`${period.submissionOpenDate}T00:00:00`) >= today)
    .sort((a, b) => new Date(a.submissionOpenDate).getTime() - new Date(b.submissionOpenDate).getTime())[0]

  if (nextUpcoming) return nextUpcoming

  return [...periods].sort((a, b) => toPeriodSortValue(b) - toPeriodSortValue(a))[0]
}

// ---------------------------------------------------------------------------
// Stat card
// ---------------------------------------------------------------------------

function StatCard({
  label,
  value,
  sub,
  icon: Icon,
  colour,
}: {
  label: string
  value: string | number
  sub?: string
  icon: React.ElementType
  colour: string
}) {
  return (
    <div className="rounded-lg border bg-card p-4 shadow-sm">
      <div className="flex items-start justify-between">
        <div>
          <p className="text-sm text-muted-foreground">{label}</p>
          <p className={`mt-1 text-2xl font-semibold tabular-nums ${colour}`}>{value}</p>
          {sub && <p className="mt-0.5 text-xs text-muted-foreground">{sub}</p>}
        </div>
        <Icon className={`h-5 w-5 ${colour} opacity-70`} />
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Progress bar cell
// ---------------------------------------------------------------------------

function CompletionBar({ pct }: { pct: number }) {
  const colour =
    pct >= 100 ? 'bg-success' : pct >= 75 ? 'bg-warning' : 'bg-danger'

  return (
    <div className="flex items-center gap-2">
      <div className="h-2 flex-1 overflow-hidden rounded-full bg-secondary">
        <div
          className={cn('h-full rounded-full transition-all', colour)}
          style={{ width: `${Math.min(pct, 100)}%` }}
        />
      </div>
      <span className="w-12 text-right text-xs tabular-nums text-muted-foreground">
        {formatPercent(pct)}
      </span>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Row actions — 3-dot menu
// ---------------------------------------------------------------------------

function SiteActions({ row }: { row: SiteCompletion }) {
  const mutation = useMutation({
    mutationFn: () =>
      api.kpi.submissionTokens.create({
        siteOrgUnitId:       row.siteOrgUnitId,
        periodId:            row.periodId,
        assignmentGroupName: row.groupName ?? null,
      }),
    onSuccess: (token) => {
      const url = `${window.location.origin}/kpi/complete?token=${token.tokenId}`
      const desc = row.groupName
        ? `${row.siteName} · ${row.periodLabel} · ${row.groupName}`
        : `${row.siteName} · ${row.periodLabel}`
      navigator.clipboard.writeText(url).then(
        () => toast.success('Link copied to clipboard', { description: desc }),
        () => toast.error('Could not copy', { description: url }),
      )
    },
    onError: (err: Error) => toast.error('Could not generate link', { description: err.message }),
  })

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          variant="ghost"
          size="sm"
          className="h-7 w-7 p-0 data-[state=open]:bg-muted"
          onClick={(e) => e.stopPropagation()}
        >
          <MoreHorizontal className="h-4 w-4" />
          <span className="sr-only">Actions</span>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuItem
          onClick={(e) => { e.stopPropagation(); mutation.mutate() }}
          disabled={mutation.isPending}
        >
          <Link2 className="mr-2 h-4 w-4" />
          {mutation.isPending ? 'Generating…' : 'Copy submission link'}
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

// ---------------------------------------------------------------------------
// Column definitions
// ---------------------------------------------------------------------------

const monitoringColumns: ColumnDef<SiteCompletion, unknown>[] = [
  {
    accessorKey: 'accountCode',
    header: 'Account',
    cell: ({ row }) => (
      <div>
        <p className="text-sm font-medium">{row.original.accountCode}</p>
        <p className="text-xs text-muted-foreground">{row.original.accountName}</p>
      </div>
    ),
    meta: { className: 'w-36' },
  },
  {
    accessorKey: 'siteCode',
    header: 'Site',
    cell: ({ row }) => (
      <div>
        <p className="font-mono text-sm">{row.original.siteCode}</p>
        <p className="text-xs text-muted-foreground">{row.original.siteName}</p>
      </div>
    ),
  },
  {
    accessorKey: 'groupName',
    header: 'Group',
    cell: ({ row }) => {
      const g = row.original.groupName
      return g
        ? <Badge variant="outline" className="text-xs font-normal">{g}</Badge>
        : <span className="text-xs text-muted-foreground">(No group)</span>
    },
    meta: { className: 'w-32' },
  },
  {
    accessorKey: 'totalRequired',
    header: 'Required',
    cell: ({ row }) => <span className="tabular-nums text-sm">{row.original.totalRequired}</span>,
    meta: { className: 'w-20 text-right', headerClassName: 'text-right' },
  },
  {
    accessorKey: 'totalSubmitted',
    header: 'Submitted',
    cell: ({ row }) => (
      <span className="tabular-nums text-sm text-success-muted-foreground font-medium">
        {row.original.totalSubmitted}
      </span>
    ),
    meta: { className: 'w-20 text-right', headerClassName: 'text-right' },
  },
  {
    accessorKey: 'totalMissing',
    header: 'Missing',
    cell: ({ row }) => {
      const n = row.original.totalMissing
      return (
        <span className={cn('tabular-nums text-sm font-medium', n > 0 ? 'text-danger' : 'text-muted-foreground')}>
          {n}
        </span>
      )
    },
    meta: { className: 'w-20 text-right', headerClassName: 'text-right' },
  },
  {
    accessorKey: 'completionPct',
    header: 'Completion',
    cell: ({ row }) => <CompletionBar pct={row.original.completionPct} />,
    meta: { className: 'min-w-[160px]' },
  },
  {
    id: 'reminder',
    header: 'Reminder',
    cell: ({ row }) => {
      const { reminderLevel, reminderResolved } = row.original
      if (reminderResolved) return <span className="text-xs text-muted-foreground">Resolved</span>
      if (reminderLevel === null || reminderLevel === undefined)
        return <span className="text-xs text-muted-foreground">—</span>
      const label = `Level ${reminderLevel}`
      const colour =
        reminderLevel >= 3 ? 'text-danger' : reminderLevel === 2 ? 'text-warning' : 'text-muted-foreground'
      return <span className={cn('text-xs font-medium', colour)}>{label}</span>
    },
    meta: { className: 'w-24' },
  },
  {
    id: 'actions',
    cell: ({ row }) => <SiteActions row={row.original} />,
    meta: { className: 'w-10' },
  },
]

// ---------------------------------------------------------------------------
// Main component
// ---------------------------------------------------------------------------

export function MonitoringView() {
  const router = useRouter()
  const [selectedPeriodLabel, setSelectedPeriodLabel] = useState<string>('')
  const { selectedAccount: sidebarAccount } = useAccount()
  const { isSuperAdmin } = usePermissions()

  const [selectedScheduleId, setSelectedScheduleId] = useState<string>('all')
  // Non-super-admins are pinned to their sidebar account. Super admins default
  // to the sidebar account but can opt into "All accounts" via the filter.
  const [selectedAccountCode, setSelectedAccountCode] = useState<string>(
    sidebarAccount?.accountCode ?? 'all',
  )
  const [selectedGroupFilter, setSelectedGroupFilter] = useState<string>('all')

  // Keep the monitoring filter in sync with the sidebar account switcher.
  useEffect(() => {
    if (!sidebarAccount) return
    if (!isSuperAdmin) {
      setSelectedAccountCode(sidebarAccount.accountCode)
      return
    }
    setSelectedAccountCode((prev) =>
      prev === 'all' ? 'all' : sidebarAccount.accountCode,
    )
  }, [sidebarAccount, isSuperAdmin])

  const { data: periodsData } = useQuery({
    queryKey: ['kpi', 'periods'],
    queryFn: () => api.kpi.periods.list(),
  })

  // Super admins see the cross-account dropdown; tenant admins don't need the
  // full accounts list at all. `selectedAccount` below is resolved from the
  // sidebar account for tenant admins.
  const { data: accountsData } = useQuery({
    queryKey: ['accounts'],
    queryFn: () => api.accounts.list(),
    enabled: isSuperAdmin,
  })

  const sortedPeriods = useMemo(() => {
    const periods = [...(periodsData?.items ?? [])].sort((a, b) => {
      const priority = { Open: 0, Draft: 1, Closed: 2, Distributed: 3 }
      return (priority[a.status] ?? 4) - (priority[b.status] ?? 4)
        || toPeriodSortValue(b) - toPeriodSortValue(a)
    })
    return periods
  }, [periodsData])

  const scheduleOptions = useMemo(() => {
    const scheduleMap = new Map<number, { periodScheduleId: number; scheduleName: string }>()
    sortedPeriods.forEach((period) => {
      if (!scheduleMap.has(period.periodScheduleId)) {
        scheduleMap.set(period.periodScheduleId, {
          periodScheduleId: period.periodScheduleId,
          scheduleName: period.scheduleName,
        })
      }
    })

    return Array.from(scheduleMap.values()).sort((a, b) => a.scheduleName.localeCompare(b.scheduleName))
  }, [sortedPeriods])

  const periodOptions = useMemo(() => {
    const filteredPeriods = selectedScheduleId === 'all'
      ? sortedPeriods
      : sortedPeriods.filter((period) => String(period.periodScheduleId) === selectedScheduleId)

    const firstPeriodByLabel = new Map<string, KpiPeriod>()
    filteredPeriods.forEach((period) => {
      if (!firstPeriodByLabel.has(period.periodLabel)) {
        firstPeriodByLabel.set(period.periodLabel, period)
      }
    })

    return Array.from(firstPeriodByLabel.values()).sort((a, b) => toPeriodSortValue(a) - toPeriodSortValue(b))
  }, [selectedScheduleId, sortedPeriods])

  useEffect(() => {
    if (periodOptions.length === 0) return

    // Selection is still valid — keep it
    if (selectedPeriodLabel && periodOptions.some((p) => p.periodLabel === selectedPeriodLabel)) return

    // Try to default to the current calendar month
    const today = new Date()
    const currentMonthOption = periodOptions.find(
      (p) => p.periodYear === today.getFullYear() && p.periodMonth === today.getMonth() + 1,
    )
    if (currentMonthOption) {
      setSelectedPeriodLabel(currentMonthOption.periodLabel)
      return
    }

    // Fallback: most recent available period (last in ascending list)
    setSelectedPeriodLabel(periodOptions[periodOptions.length - 1].periodLabel)
  }, [selectedPeriodLabel, periodOptions])

  const selectedPeriod = useMemo(() => {
    const matching = sortedPeriods.filter(
      (period) =>
        period.periodLabel === selectedPeriodLabel
        && (selectedScheduleId === 'all' || String(period.periodScheduleId) === selectedScheduleId),
    )

    if (matching.length === 0) return null

    return selectCurrentPeriod(matching)
      ?? [...matching].sort((a, b) => {
        const priority = { Open: 0, Draft: 1, Closed: 2, Distributed: 3 }
        return (priority[a.status] ?? 4) - (priority[b.status] ?? 4)
          || a.periodScheduleId - b.periodScheduleId
      })[0]
  }, [selectedPeriodLabel, selectedScheduleId, sortedPeriods])
  // Super admins pick an account from the cross-tenant dropdown (`accountsData`);
  // tenant admins are pinned to their sidebar account via `sidebarAccount`.
  const selectedAccount = isSuperAdmin
    ? accountsData?.items.find((a) => a.accountCode === selectedAccountCode)
    : sidebarAccount

  const { data, isLoading, isError, error, refetch } = useQuery({
    queryKey: ['kpi', 'monitoring', selectedPeriod?.periodId ?? 'none', selectedAccount?.accountId ?? 'all'],
    queryFn: () =>
      selectedPeriod
        ? api.kpi.monitoring.list({
            periodId: selectedPeriod.periodId,
            accountId: selectedAccount?.accountId,
          })
        : Promise.resolve({ items: [], totalCount: 0 }),
    enabled: selectedPeriod !== null,
    refetchOnWindowFocus: true,
  })

  useEffect(() => {
    if (selectedPeriod === null) return

    function handleRefreshSignal() {
      void refetch()
    }

    function handleStorage(event: StorageEvent) {
      if (event.key !== KPI_MONITORING_REFRESH_EVENT) return
      void refetch()
    }

    window.addEventListener(KPI_MONITORING_REFRESH_EVENT, handleRefreshSignal)
    window.addEventListener('storage', handleStorage)

    return () => {
      window.removeEventListener(KPI_MONITORING_REFRESH_EVENT, handleRefreshSignal)
      window.removeEventListener('storage', handleStorage)
    }
  }, [selectedPeriod, refetch])

  // Distinct group names found in the monitoring data (used for filter dropdown)
  const groupOptions = useMemo(() => {
    const all = data?.items ?? []
    const names = new Set<string | null>()
    all.forEach((i) => names.add(i.groupName))
    return Array.from(names).sort((a, b) => {
      if (a === null) return 1   // "(No group)" last
      if (b === null) return -1
      return a.localeCompare(b)
    })
  }, [data])

  const accessible = useAccessibleSites()

  const filteredItems = useMemo(() => {
    let all = data?.items ?? []

    // Narrow to the user's accessible sites when they're role-scoped. Account
    // admins and super-admins pass through unchanged. While resolvedAccess is
    // still fetching, render an empty table rather than the full account list
    // so a site-scoped user never flashes data they shouldn't see.
    if (accessible.mode === 'scoped') {
      if (accessible.isLoading) return []
      all = all.filter((row) => accessible.siteCodes.has(row.siteCode))
    }

    if (selectedGroupFilter === 'all') return all
    if (selectedGroupFilter === '__nogroup__') return all.filter((i) => i.groupName === null)
    return all.filter((i) => i.groupName === selectedGroupFilter)
  }, [data, selectedGroupFilter, accessible])

  // Aggregate stats across filtered items
  const stats = useMemo(() => {
    const items = filteredItems
    const totalRequired = items.reduce((s, i) => s + i.totalRequired, 0)
    const totalSubmitted = items.reduce((s, i) => s + i.totalSubmitted, 0)
    const totalLocked = items.reduce((s, i) => s + i.totalLocked, 0)
    const totalMissing = items.reduce((s, i) => s + i.totalMissing, 0)
    const overallPct = totalRequired > 0 ? (totalSubmitted / totalRequired) * 100 : 0
    return { totalRequired, totalSubmitted, totalLocked, totalMissing, overallPct, siteCount: items.length }
  }, [filteredItems])

  if (isError) {
    return (
      <div className="rounded-md border border-destructive/40 bg-destructive/5 p-6 text-center">
        <p className="text-sm font-medium text-destructive">Failed to load monitoring data</p>
        <p className="mt-1 text-xs text-muted-foreground">
          {error instanceof Error ? error.message : 'An unexpected error occurred.'}
        </p>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center gap-2">
        <div className="flex items-center gap-2">
          <span className="text-sm text-muted-foreground">Period:</span>
          <Select value={selectedPeriodLabel} onValueChange={setSelectedPeriodLabel}>
            <SelectTrigger className="h-8 w-40 text-sm">
              <SelectValue placeholder="Select a period">{selectedPeriodLabel || 'Select a period'}</SelectValue>
            </SelectTrigger>
            <SelectContent>
              {periodOptions.map((p) => (
                <SelectItem key={`${p.periodScheduleId}-${p.periodLabel}`} value={p.periodLabel} textValue={p.periodLabel}>
                  {p.periodLabel}
                  <span className="ml-2 text-xs text-muted-foreground">({p.status})</span>
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>

        <div className="flex items-center gap-2">
          <span className="text-sm text-muted-foreground">Schedule:</span>
          <Select value={selectedScheduleId} onValueChange={setSelectedScheduleId}>
            <SelectTrigger className="h-8 w-72 text-sm">
              <SelectValue placeholder="All schedules">
                {selectedScheduleId === 'all'
                  ? 'All schedules'
                  : (scheduleOptions.find((s) => String(s.periodScheduleId) === selectedScheduleId)?.scheduleName ?? 'All schedules')}
              </SelectValue>
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All schedules</SelectItem>
              {scheduleOptions.map((schedule) => (
                <SelectItem key={schedule.periodScheduleId} value={String(schedule.periodScheduleId)} textValue={schedule.scheduleName}>
                  {schedule.scheduleName}
                  <span className="ml-2 text-xs text-muted-foreground">
                    {formatScheduleRef(schedule.periodScheduleId)}
                  </span>
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>

        {isSuperAdmin && (
          <div className="flex items-center gap-2">
            <span className="text-sm text-muted-foreground">Account:</span>
            <Select value={selectedAccountCode} onValueChange={setSelectedAccountCode}>
              <SelectTrigger className="h-8 w-48 text-sm">
                <SelectValue placeholder="All accounts" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All accounts</SelectItem>
                {(accountsData?.items ?? []).map((account) => (
                  <SelectItem key={account.accountId} value={account.accountCode}>
                    {account.accountName}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        )}

        {groupOptions.length > 1 && (
          <div className="flex items-center gap-2">
            <span className="text-sm text-muted-foreground">Group:</span>
            <Select value={selectedGroupFilter} onValueChange={setSelectedGroupFilter}>
              <SelectTrigger className="h-8 w-40 text-sm">
                <SelectValue placeholder="All groups">
                  {selectedGroupFilter === 'all'
                    ? 'All groups'
                    : selectedGroupFilter === '__nogroup__'
                      ? '(No group)'
                      : selectedGroupFilter}
                </SelectValue>
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All groups</SelectItem>
                {groupOptions.map((g) =>
                  g === null ? (
                    <SelectItem key="__nogroup__" value="__nogroup__">(No group)</SelectItem>
                  ) : (
                    <SelectItem key={g} value={g}>{g}</SelectItem>
                  )
                )}
              </SelectContent>
            </Select>
          </div>
        )}

        {selectedPeriod?.status === 'Open' && selectedPeriod.daysRemaining !== null && (
          <div className="ml-auto rounded-md border bg-muted/40 px-3 py-1.5 text-sm">
            <span className="text-muted-foreground">Window</span>{' '}
            <span className={cn(
              (selectedPeriod.daysRemaining ?? 0) <= 3 ? 'font-medium text-danger' : 'font-medium'
            )}>
              {selectedPeriod.daysRemaining}d remaining
            </span>
          </div>
        )}
      </div>

      {/* Stat cards */}
      {selectedPeriod && (
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <StatCard
            label="Overall Completion"
            value={formatPercent(stats.overallPct)}
            sub={`${stats.siteCount} sites`}
            icon={CheckCircle2}
            colour={stats.overallPct >= 100 ? 'text-success' : stats.overallPct >= 75 ? 'text-warning' : 'text-danger'}
          />
          <StatCard
            label="Submitted"
            value={stats.totalSubmitted}
            sub={`of ${stats.totalRequired} required`}
            icon={CheckCircle2}
            colour="text-success"
          />
          <StatCard
            label="Locked"
            value={stats.totalLocked}
            sub="confirmed"
            icon={Lock}
            colour="text-info"
          />
          <StatCard
            label="Missing"
            value={stats.totalMissing}
            sub={stats.totalMissing > 0 ? 'not yet submitted' : 'all submitted'}
            icon={stats.totalMissing > 0 ? AlertTriangle : AlertCircle}
            colour={stats.totalMissing > 0 ? 'text-danger' : 'text-muted-foreground'}
          />
        </div>
      )}

      {/* Site table */}
      <DataTable
        columns={monitoringColumns}
        data={filteredItems}
        isLoading={isLoading || !selectedPeriod}
        pageSize={25}
        skeletonRowCount={10}
        onRowClick={(row) => {
          const groupParam = row.groupName
            ? `?group=${encodeURIComponent(row.groupName)}`
            : '?group=__nogroup__'
          router.push(`/kpi/monitoring/${row.siteOrgUnitId}/${row.periodId}${groupParam}`)
        }}
      />
    </div>
  )
}
