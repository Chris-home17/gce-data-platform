'use client'

import { useEffect } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useRouter } from 'next/navigation'
import { toast } from 'sonner'
import {
  ArrowLeft,
  CheckCircle2,
  Lock,
  LockOpen,
  MoreHorizontal,
  AlertTriangle,
  Loader2,
  User,
  Clock,
  Link2,
  Building2,
  Calendar,
  AlertCircle,
} from 'lucide-react'
import { api } from '@/lib/api'
import { cn, formatPercent } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { Skeleton } from '@/components/ui/skeleton'
import { Separator } from '@/components/ui/separator'
import type { SiteSubmissionDetail } from '@/types/api'

const KPI_MONITORING_REFRESH_EVENT = 'gce:kpi-monitoring-refresh'

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function formatDate(iso: string | null | undefined) {
  if (!iso) return null
  return new Date(iso).toLocaleDateString('en-GB', {
    day: 'numeric', month: 'short', year: 'numeric',
    hour: '2-digit', minute: '2-digit',
  })
}

function ragDot(rag: string | null | undefined) {
  if (!rag) return null
  const colour = rag === 'Green' ? 'bg-green-500' : rag === 'Amber' ? 'bg-amber-400' : 'bg-red-500'
  return <span className={cn('inline-block h-2.5 w-2.5 rounded-full shrink-0', colour)} title={rag} />
}

function displayValue(row: SiteSubmissionDetail): string {
  if (!row.isSubmitted) return '—'
  if (row.dataType === 'Boolean') return row.submissionBoolean === true ? 'Yes' : row.submissionBoolean === false ? 'No' : '—'
  if (row.dataType === 'Text' || row.dataType === 'DropDown') return row.submissionText ?? '—'
  return row.submissionValue != null ? String(row.submissionValue) : '—'
}

function LockBadge({ lockState }: { lockState: SiteSubmissionDetail['lockState'] }) {
  if (!lockState || lockState === 'Unlocked') return null
  if (lockState === 'LockedByPeriodClose')
    return <Badge variant="secondary" className="text-xs gap-1"><Lock className="h-3 w-3" />Period closed</Badge>
  if (lockState === 'LockedByAuto')
    return <Badge variant="secondary" className="text-xs gap-1"><Lock className="h-3 w-3" />Auto-locked</Badge>
  return <Badge variant="outline" className="text-xs gap-1 border-amber-300 text-amber-700"><Lock className="h-3 w-3" />Locked</Badge>
}

// ---------------------------------------------------------------------------
// KPI submission row
// ---------------------------------------------------------------------------

interface SubmissionRowProps {
  row: SiteSubmissionDetail
  periodStatus: string
  onUnlocked: () => void
}

function SubmissionRow({ row, periodStatus, onUnlocked }: SubmissionRowProps) {
  const canUnlock = periodStatus === 'Open' && row.lockState === 'Locked'

  const mutation = useMutation({
    mutationFn: () => api.kpi.submissions.unlock(row.externalId),
    onSuccess: () => {
      toast.success(`${row.effectiveKpiName} unlocked`, {
        description: 'The submitter can now update this response.',
      })
      onUnlocked()
    },
    onError: (err: Error) => toast.error('Could not unlock', { description: err.message }),
  })

  return (
    <div className={cn(
      'rounded-lg border px-4 py-3 text-sm transition-colors',
      !row.isSubmitted ? 'border-dashed bg-muted/20' : 'bg-background hover:bg-muted/20',
    )}>
      <div className="flex items-start justify-between gap-4">
        {/* Left: KPI name + value */}
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            {row.isRequired && (
              <span className="text-[10px] font-semibold uppercase tracking-wider text-red-500 bg-red-50 dark:bg-red-950/30 px-1.5 py-0.5 rounded">
                Required
              </span>
            )}
            <span className="font-medium">{row.effectiveKpiName}</span>
            <span className="font-mono text-[11px] text-muted-foreground">{row.kpiCode}</span>
            {ragDot(row.ragStatus)}
          </div>

          {row.isSubmitted ? (
            <div className="mt-2 space-y-1">
              <p className="font-mono text-base font-semibold text-foreground">
                {displayValue(row)}
              </p>
              {row.submissionNotes && (
                <p className="text-xs text-muted-foreground italic">&ldquo;{row.submissionNotes}&rdquo;</p>
              )}
              <div className="flex items-center gap-4 text-xs text-muted-foreground">
                {row.submittedByUpn && (
                  <span className="flex items-center gap-1">
                    <User className="h-3 w-3" />{row.submittedByUpn}
                  </span>
                )}
                {row.submittedAt && (
                  <span className="flex items-center gap-1">
                    <Clock className="h-3 w-3" />{formatDate(row.submittedAt)}
                  </span>
                )}
              </div>
            </div>
          ) : (
            <p className="text-xs text-muted-foreground mt-1.5 flex items-center gap-1">
              <AlertTriangle className="h-3 w-3 text-amber-400" />
              Not yet submitted
            </p>
          )}
        </div>

        {/* Right: lock + actions */}
        <div className="flex items-center gap-2 shrink-0 pt-0.5">
          <LockBadge lockState={row.lockState} />
          {canUnlock && (
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button
                  variant="ghost"
                  size="sm"
                  className="h-7 w-7 p-0 data-[state=open]:bg-muted"
                  disabled={mutation.isPending}
                >
                  {mutation.isPending ? (
                    <Loader2 className="h-4 w-4 animate-spin" />
                  ) : (
                    <MoreHorizontal className="h-4 w-4" />
                  )}
                  <span className="sr-only">Actions</span>
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end">
                <DropdownMenuItem
                  onClick={() => mutation.mutate()}
                  className="text-amber-700 focus:text-amber-700"
                >
                  <LockOpen className="mr-2 h-4 w-4" />
                  Unlock
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          )}
          {row.isSubmitted && (!row.lockState || row.lockState === 'Unlocked') && (
            <CheckCircle2 className="h-4 w-4 text-green-500 shrink-0" />
          )}
        </div>
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Copy link button
// ---------------------------------------------------------------------------

function CopyLinkButton({ siteOrgUnitId, periodId, disabled }: { siteOrgUnitId: number; periodId: number; disabled?: boolean }) {
  const mutation = useMutation({
    mutationFn: () => api.kpi.submissionTokens.create({ siteOrgUnitId, periodId }),
    onSuccess: (token) => {
      const url = `${window.location.origin}/kpi/complete?token=${token.tokenId}`
      navigator.clipboard.writeText(url).then(
        () => toast.success('Submission link copied to clipboard'),
        () => toast.error('Could not copy', { description: url }),
      )
    },
    onError: (err: Error) => toast.error('Could not generate link', { description: err.message }),
  })

  return (
    <Button
      variant="outline"
      size="sm"
      onClick={() => mutation.mutate()}
      disabled={mutation.isPending || disabled}
    >
      {mutation.isPending ? <Loader2 className="mr-1.5 h-4 w-4 animate-spin" /> : <Link2 className="mr-1.5 h-4 w-4" />}
      Copy submission link
    </Button>
  )
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
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm font-medium text-muted-foreground">{label}</CardTitle>
        <Icon className={cn('h-4 w-4', colour, 'opacity-70')} />
      </CardHeader>
      <CardContent>
        <div className={cn('text-2xl font-bold tabular-nums', colour)}>{value}</div>
        {sub && <p className="mt-0.5 text-xs text-muted-foreground">{sub}</p>}
      </CardContent>
    </Card>
  )
}

// ---------------------------------------------------------------------------
// Period status badge
// ---------------------------------------------------------------------------

function PeriodStatusBadge({ status }: { status: string }) {
  const variants: Record<string, string> = {
    Open: 'border-green-300 bg-green-50 text-green-700 dark:bg-green-950/30 dark:text-green-400',
    Closed: 'border-gray-300 text-gray-600',
    Draft: 'border-blue-300 bg-blue-50 text-blue-700 dark:bg-blue-950/30 dark:text-blue-400',
    Distributed: 'border-purple-300 bg-purple-50 text-purple-700',
  }
  return (
    <Badge variant="outline" className={cn('text-xs', variants[status])}>
      {status}
    </Badge>
  )
}

// ---------------------------------------------------------------------------
// Main component
// ---------------------------------------------------------------------------

interface SitePeriodDetailProps {
  siteOrgUnitId: number
  periodId: number
}

export function SitePeriodDetail({ siteOrgUnitId, periodId }: SitePeriodDetailProps) {
  const router = useRouter()
  const queryClient = useQueryClient()

  // Fetch the monitoring summary row (site + period + completion stats)
  const { data: monitoringData, isLoading: summaryLoading, refetch: refetchMonitoring } = useQuery({
    queryKey: ['kpi', 'monitoring', periodId, 'all', siteOrgUnitId],
    queryFn: () => api.kpi.monitoring.list({ periodId, siteOrgUnitId }),
    refetchOnWindowFocus: true,
  })

  // Fetch the period to get status
  const { data: period } = useQuery({
    queryKey: ['kpi', 'periods', periodId],
    queryFn: () => api.kpi.periods.get(periodId),
    refetchOnWindowFocus: true,
  })

  // Fetch individual KPI submission details
  const { data, isLoading: detailLoading, isError, refetch: refetchDetails } = useQuery({
    queryKey: ['kpi', 'site-submissions', siteOrgUnitId, periodId],
    queryFn: () => api.kpi.submissions.listForSite({ siteOrgUnitId, periodId }),
    refetchOnWindowFocus: true,
  })

  useEffect(() => {
    function handleRefreshSignal() {
      void refetchMonitoring()
      void refetchDetails()
    }

    function handleStorage(event: StorageEvent) {
      if (event.key !== KPI_MONITORING_REFRESH_EVENT) return
      void refetchMonitoring()
      void refetchDetails()
    }

    window.addEventListener(KPI_MONITORING_REFRESH_EVENT, handleRefreshSignal)
    window.addEventListener('storage', handleStorage)

    return () => {
      window.removeEventListener(KPI_MONITORING_REFRESH_EVENT, handleRefreshSignal)
      window.removeEventListener('storage', handleStorage)
    }
  }, [refetchDetails, refetchMonitoring])

  function handleUnlocked() {
    queryClient.invalidateQueries({ queryKey: ['kpi', 'site-submissions', siteOrgUnitId, periodId] })
    queryClient.invalidateQueries({ queryKey: ['kpi', 'monitoring'] })
  }

  const summary = monitoringData?.items[0] ?? null
  const periodStatus = period?.status ?? ''

  const isLoading = summaryLoading || detailLoading

  // Group by category
  const grouped = (data?.items ?? []).reduce<Record<string, SiteSubmissionDetail[]>>((acc, item) => {
    const cat = item.category ?? 'General'
    if (!acc[cat]) acc[cat] = []
    acc[cat].push(item)
    return acc
  }, {})

  const completionPct = summary?.completionPct ?? 0
  const totalRequired = summary?.totalRequired ?? 0
  const totalSubmitted = summary?.totalSubmitted ?? 0
  const totalLocked = summary?.totalLocked ?? 0
  const totalMissing = summary?.totalMissing ?? 0

  if (isError) {
    return (
      <div className="rounded-md border border-destructive/40 bg-destructive/5 p-6 text-center">
        <AlertCircle className="mx-auto mb-2 h-5 w-5 text-destructive" />
        <p className="text-sm font-medium text-destructive">Failed to load submission data</p>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Back button */}
      <Button
        variant="ghost"
        size="sm"
        className="-ml-2 text-muted-foreground"
        onClick={() => router.push('/kpi/monitoring')}
      >
        <ArrowLeft className="mr-1.5 h-4 w-4" />
        Monitoring
      </Button>

      {/* Header */}
      {summaryLoading ? (
        <div className="space-y-2">
          <div className="h-7 w-64 animate-pulse rounded bg-muted" />
          <div className="h-4 w-48 animate-pulse rounded bg-muted" />
        </div>
      ) : summary ? (
        <div className="flex items-start justify-between flex-wrap gap-4">
          <div>
            <div className="flex items-center gap-3 flex-wrap">
              <h1 className="text-2xl font-semibold tracking-tight">{summary.siteName}</h1>
              <span className="font-mono text-sm text-muted-foreground bg-muted px-2 py-0.5 rounded">
                {summary.siteCode}
              </span>
              {period && <PeriodStatusBadge status={period.status} />}
            </div>
            <div className="mt-1.5 flex items-center gap-4 text-sm text-muted-foreground flex-wrap">
              <span className="flex items-center gap-1.5">
                <Building2 className="h-3.5 w-3.5" />
                {summary.accountName}
              </span>
              <span className="flex items-center gap-1.5">
                <Calendar className="h-3.5 w-3.5" />
                {summary.periodLabel}
              </span>
              {period?.daysRemaining !== null && period?.status === 'Open' && (
                <span className={cn(
                  'flex items-center gap-1.5',
                  (period.daysRemaining ?? 0) <= 3 ? 'text-red-600 font-medium' : '',
                )}>
                  <Clock className="h-3.5 w-3.5" />
                  {period.daysRemaining}d remaining
                </span>
              )}
            </div>
          </div>
          <CopyLinkButton siteOrgUnitId={siteOrgUnitId} periodId={periodId} />
        </div>
      ) : null}

      {/* Stat cards */}
      <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
        <StatCard
          label="Completion"
          value={formatPercent(completionPct)}
          sub={isLoading ? undefined : `${summary?.siteCode ?? ''}`}
          icon={CheckCircle2}
          colour={completionPct >= 100 ? 'text-green-600' : completionPct >= 75 ? 'text-amber-600' : 'text-red-600'}
        />
        <StatCard
          label="Submitted"
          value={isLoading ? '—' : totalSubmitted}
          sub={`of ${totalRequired} required`}
          icon={CheckCircle2}
          colour="text-green-600"
        />
        <StatCard
          label="Locked"
          value={isLoading ? '—' : totalLocked}
          sub="confirmed"
          icon={Lock}
          colour="text-blue-600"
        />
        <StatCard
          label="Missing"
          value={isLoading ? '—' : totalMissing}
          sub={totalMissing > 0 ? 'not yet submitted' : 'all submitted'}
          icon={totalMissing > 0 ? AlertTriangle : AlertCircle}
          colour={totalMissing > 0 ? 'text-red-600' : 'text-muted-foreground'}
        />
      </div>

      {/* Progress bar */}
      <div className="space-y-1.5">
        <div className="flex items-center justify-between text-sm">
          <span className="text-muted-foreground">Overall progress</span>
          <span className="font-medium tabular-nums">{totalSubmitted} / {totalRequired}</span>
        </div>
        <div className="h-2 w-full overflow-hidden rounded-full bg-secondary">
          <div
            className={cn(
              'h-full rounded-full transition-all',
              completionPct >= 100 ? 'bg-green-500' : completionPct >= 75 ? 'bg-amber-400' : 'bg-red-500',
            )}
            style={{ width: `${Math.min(completionPct, 100)}%` }}
          />
        </div>
      </div>

      {/* KPI list */}
      <div className="space-y-6">
        {detailLoading
          ? Array.from({ length: 3 }).map((_, i) => (
              <div key={i} className="space-y-2">
                <Skeleton className="h-4 w-32" />
                <Skeleton className="h-16 w-full rounded-lg" />
                <Skeleton className="h-16 w-full rounded-lg" />
              </div>
            ))
          : Object.entries(grouped).map(([category, items]) => {
              const catSubmitted = items.filter((i) => i.isSubmitted).length
              return (
                <div key={category}>
                  <div className="flex items-center gap-3 mb-3">
                    <span className="text-[11px] font-semibold uppercase tracking-wider text-muted-foreground">
                      {category}
                    </span>
                    <Separator className="flex-1" />
                    <span className={cn(
                      'text-[11px] font-mono font-medium',
                      catSubmitted === items.length ? 'text-green-600' : 'text-muted-foreground',
                    )}>
                      {catSubmitted}/{items.length}
                    </span>
                  </div>
                  <div className="space-y-2">
                    {items.map((item) => (
                      <SubmissionRow
                        key={item.assignmentId}
                        row={item}
                        periodStatus={periodStatus}
                        onUnlocked={handleUnlocked}
                      />
                    ))}
                  </div>
                </div>
              )
            })
        }
      </div>

      {/* Unlock hint for Open periods */}
      {periodStatus === 'Open' && !detailLoading && (data?.items ?? []).some((i) => i.lockState === 'Locked') && (
        <p className="text-xs text-muted-foreground text-center">
          <LockOpen className="inline h-3 w-3 mr-1" />
          Click Unlock on any manually-locked response to allow the submitter to update it.
        </p>
      )}
    </div>
  )
}
