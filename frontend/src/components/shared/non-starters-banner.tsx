'use client'

import Link from 'next/link'
import { AlertTriangle } from 'lucide-react'
import { cn } from '@/lib/utils'
import type { SiteCompletion } from '@/types/api'

interface NonStartersBannerProps {
  /** Per-site completion summaries for the visible scope. */
  rows: SiteCompletion[]
  /** Current period — used to deep-link non-starter chips. */
  periodId: number
  /** How many chips to render inline before collapsing the rest into "+N more". */
  chipLimit?: number
  className?: string
}

/** Surfaces sites that haven't submitted anything for the current period.
 *  These never appear in TopDetractorsPanel because vSiteCompositeScore
 *  excludes them (no scoreable rows → no compositeScore). They are an
 *  engagement problem, not a KPI-quality one — handled separately. */
export function NonStartersBanner({
  rows,
  periodId,
  chipLimit = 5,
  className,
}: NonStartersBannerProps) {
  // Required-count guard: if a site has zero required KPIs for this period,
  // it's out of scope (e.g. waiting on assignment) and shouldn't be flagged.
  const nonStarters = rows.filter((r) => r.totalRequired > 0 && r.totalSubmitted === 0)

  if (nonStarters.length === 0) return null

  const visible = nonStarters.slice(0, chipLimit)
  const hidden = nonStarters.length - visible.length

  return (
    <div
      className={cn(
        'flex flex-wrap items-center gap-x-3 gap-y-2 rounded-md border border-warning-border bg-warning-muted px-3 py-2 text-warning-muted-foreground',
        className,
      )}
      role="status"
    >
      <span className="flex items-center gap-2 text-sm font-medium">
        <AlertTriangle className="h-4 w-4 shrink-0" />
        {nonStarters.length} {nonStarters.length === 1 ? 'site has' : 'sites have'}n&apos;t started this period
      </span>
      <span className="hidden text-warning-muted-foreground/60 lg:inline">—</span>
      <div className="flex flex-wrap items-center gap-1.5">
        {visible.map((s) => (
          <Link
            key={s.siteOrgUnitId}
            href={`/kpi/monitoring/${s.siteOrgUnitId}/${periodId}`}
            className="inline-flex items-center gap-1.5 rounded border border-warning-border/60 bg-background/60 px-2 py-0.5 text-xs font-medium hover:bg-background transition-colors"
            title={`${s.siteName} (${s.siteCode})`}
          >
            <span className="truncate max-w-[160px]">{s.siteName}</span>
            <span className="font-mono text-[10px] text-muted-foreground">{s.siteCode}</span>
          </Link>
        ))}
        {hidden > 0 && (
          <span
            className="inline-flex items-center rounded border border-dashed border-warning-border/60 bg-background/40 px-2 py-0.5 text-xs"
            title="Sort the site table below by completion to see all of them."
          >
            +{hidden} more
          </span>
        )}
      </div>
    </div>
  )
}
