'use client'

import { useState, useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import { AlertCircle, CheckCircle2, Lock, AlertTriangle } from 'lucide-react'
import { api } from '@/lib/api'
import { cn, formatPercent } from '@/lib/utils'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { DataTable } from '@/components/shared/data-table'
import type { ColumnDef } from '@tanstack/react-table'
import type { SiteCompletion } from '@/types/api'

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
    pct >= 100 ? 'bg-green-500' : pct >= 75 ? 'bg-amber-400' : 'bg-red-500'

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
// Column definitions
// ---------------------------------------------------------------------------

const monitoringColumns: ColumnDef<SiteCompletion, unknown>[] = [
  {
    accessorKey: 'accountCode',
    header: 'Account',
    cell: ({ row }) => (
      <span className="font-mono text-sm font-medium">{row.original.accountCode}</span>
    ),
    meta: { className: 'w-24' },
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
    accessorKey: 'totalRequired',
    header: 'Required',
    cell: ({ row }) => <span className="tabular-nums text-sm">{row.original.totalRequired}</span>,
    meta: { className: 'w-20 text-right', headerClassName: 'text-right' },
  },
  {
    accessorKey: 'totalSubmitted',
    header: 'Submitted',
    cell: ({ row }) => (
      <span className="tabular-nums text-sm text-green-700 dark:text-green-400 font-medium">
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
        <span className={cn('tabular-nums text-sm font-medium', n > 0 ? 'text-red-600 dark:text-red-400' : 'text-muted-foreground')}>
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
        reminderLevel >= 3 ? 'text-red-600' : reminderLevel === 2 ? 'text-amber-600' : 'text-muted-foreground'
      return <span className={cn('text-xs font-medium', colour)}>{label}</span>
    },
    meta: { className: 'w-24' },
  },
]

// ---------------------------------------------------------------------------
// Main component
// ---------------------------------------------------------------------------

export function MonitoringView() {
  const [selectedPeriodLabel, setSelectedPeriodLabel] = useState<string>('')
  const [selectedAccountCode, setSelectedAccountCode] = useState<string>('all')

  const { data: periodsData } = useQuery({
    queryKey: ['kpi', 'periods'],
    queryFn: () => api.kpi.periods.list(),
  })

  const { data: accountsData } = useQuery({
    queryKey: ['accounts'],
    queryFn: () => api.accounts.list(),
  })

  // Default to the first Open period when data loads
  const sortedPeriods = useMemo(() => {
    const periods = [...(periodsData?.items ?? [])].sort((a, b) => {
      const priority = { Open: 0, Draft: 1, Closed: 2, Distributed: 3 }
      return (priority[a.status] ?? 4) - (priority[b.status] ?? 4)
        || (b.periodYear * 100 + b.periodMonth) - (a.periodYear * 100 + a.periodMonth)
    })
    // Auto-select first period
    if (periods.length > 0 && !selectedPeriodLabel) {
      // eslint-disable-next-line react-hooks/exhaustive-deps
      setTimeout(() => setSelectedPeriodLabel(periods[0].periodLabel), 0)
    }
    return periods
  }, [periodsData, selectedPeriodLabel])

  const selectedPeriod = sortedPeriods.find((p) => p.periodLabel === selectedPeriodLabel)
  const selectedAccount = accountsData?.items.find((account) => account.accountCode === selectedAccountCode)

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['kpi', 'monitoring', selectedPeriod?.periodId, selectedAccount?.accountId ?? 'all'],
    queryFn: () =>
      selectedPeriod
        ? api.kpi.monitoring.list({
            periodId: selectedPeriod.periodId,
            accountId: selectedAccount?.accountId,
          })
        : Promise.resolve({ items: [], totalCount: 0 }),
    enabled: !!selectedPeriod,
  })

  // Aggregate stats across all sites in the selected period
  const stats = useMemo(() => {
    const items = data?.items ?? []
    const totalRequired = items.reduce((s, i) => s + i.totalRequired, 0)
    const totalSubmitted = items.reduce((s, i) => s + i.totalSubmitted, 0)
    const totalLocked = items.reduce((s, i) => s + i.totalLocked, 0)
    const totalMissing = items.reduce((s, i) => s + i.totalMissing, 0)
    const overallPct = totalRequired > 0 ? (totalSubmitted / totalRequired) * 100 : 0
    return { totalRequired, totalSubmitted, totalLocked, totalMissing, overallPct, siteCount: items.length }
  }, [data])

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
      {/* Period selector */}
      <div className="flex flex-wrap items-center gap-3">
        <span className="text-sm font-medium">Period</span>
        <Select value={selectedPeriodLabel} onValueChange={setSelectedPeriodLabel}>
          <SelectTrigger className="w-52">
            <SelectValue placeholder="Select a period" />
          </SelectTrigger>
          <SelectContent>
            {sortedPeriods.map((p) => (
              <SelectItem key={p.periodId} value={p.periodLabel}>
                {p.periodLabel}
                <span className="ml-2 text-xs text-muted-foreground">({p.status})</span>
              </SelectItem>
            ))}
          </SelectContent>
        </Select>

        <span className="text-sm font-medium">Account</span>
        <Select value={selectedAccountCode} onValueChange={setSelectedAccountCode}>
          <SelectTrigger className="w-48">
            <SelectValue placeholder="All accounts" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All accounts</SelectItem>
            {(accountsData?.items ?? []).map((account) => (
              <SelectItem key={account.accountId} value={account.accountCode}>
                {account.accountCode}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>

        {selectedPeriod?.status === 'Open' && selectedPeriod.daysRemaining !== null && (
          <span className={cn(
            'text-sm',
            (selectedPeriod.daysRemaining ?? 0) <= 3 ? 'text-red-600 font-medium' : 'text-muted-foreground'
          )}>
            {selectedPeriod.daysRemaining}d remaining
          </span>
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
            colour={stats.overallPct >= 100 ? 'text-green-600' : stats.overallPct >= 75 ? 'text-amber-600' : 'text-red-600'}
          />
          <StatCard
            label="Submitted"
            value={stats.totalSubmitted}
            sub={`of ${stats.totalRequired} required`}
            icon={CheckCircle2}
            colour="text-green-600"
          />
          <StatCard
            label="Locked"
            value={stats.totalLocked}
            sub="confirmed"
            icon={Lock}
            colour="text-blue-600"
          />
          <StatCard
            label="Missing"
            value={stats.totalMissing}
            sub={stats.totalMissing > 0 ? 'not yet submitted' : 'all submitted'}
            icon={stats.totalMissing > 0 ? AlertTriangle : AlertCircle}
            colour={stats.totalMissing > 0 ? 'text-red-600' : 'text-muted-foreground'}
          />
        </div>
      )}

      {/* Site table */}
      <DataTable
        columns={monitoringColumns}
        data={data?.items ?? []}
        isLoading={isLoading || !selectedPeriod}
        pageSize={25}
        skeletonRowCount={10}
      />
    </div>
  )
}
