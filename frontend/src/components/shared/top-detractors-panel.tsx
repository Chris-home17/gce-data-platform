'use client'

import { useState } from 'react'
import Link from 'next/link'
import { ArrowUpRight, ChevronDown, ChevronUp, TrendingDown } from 'lucide-react'
import { cn } from '@/lib/utils'
import type { SiteCategoryScore } from '@/types/api'

interface TopDetractorsPanelProps {
  /** Per-category × per-site rows for the visible scope. */
  rows: SiteCategoryScore[]
  /** Map siteOrgUnitId → display name, used to render the deep link target. */
  siteNamesById: Map<number, { name: string; code: string }>
  /** Current period — used to build deep-links into the site×period detail page. */
  periodId: number
  /** How many to show. Defaults to 5. */
  limit?: number
  className?: string
}

interface DetractorRow {
  siteOrgUnitId: number
  category: string
  categoryScore: number
  /** Composite points that would be gained if this category went to 100.
   *  Computed per-site: (100 − categoryScore) × normalised category weight at the site. */
  potentialGainPts: number
  /** Composite this site currently sits at (constant across the site's category rows). */
  siteComposite: number | null
}

/** Computes which (site, category) tuples are dragging the visible composite
 *  down the most. Same formula as `score-breakdown.ts`, but applied at site×
 *  category granularity so it can rank across many sites without per-KPI data.
 *
 *  potentialGainPts := (100 − categoryScore) × (categoryWeight / Σ active categoryWeight at site)
 */
function rankDetractors(rows: SiteCategoryScore[]): DetractorRow[] {
  // Sum of active+scored CategoryWeights per site, so we can normalise.
  const totalWeightBySite = new Map<number, number>()
  for (const r of rows) {
    if (!r.categoryActive || r.categoryScore === null) continue
    totalWeightBySite.set(r.siteOrgUnitId, (totalWeightBySite.get(r.siteOrgUnitId) ?? 0) + r.categoryWeight)
  }

  const out: DetractorRow[] = []
  for (const r of rows) {
    if (!r.categoryActive || r.categoryScore === null) continue
    if (r.categoryScore >= 100) continue
    const totalW = totalWeightBySite.get(r.siteOrgUnitId) ?? 0
    if (totalW <= 0) continue
    const normalisedW = r.categoryWeight / totalW
    const potentialGainPts = (100 - r.categoryScore) * normalisedW
    if (potentialGainPts < 0.5) continue // skip the rounding noise
    out.push({
      siteOrgUnitId: r.siteOrgUnitId,
      category: r.category,
      categoryScore: r.categoryScore,
      potentialGainPts,
      siteComposite: r.compositeScore,
    })
  }
  out.sort((a, b) => b.potentialGainPts - a.potentialGainPts)
  return out
}

function impactColour(pts: number): string {
  if (pts >= 20) return 'bg-danger-muted text-danger-muted-foreground'
  if (pts >= 10) return 'bg-warning-muted text-warning-muted-foreground'
  return 'bg-muted text-muted-foreground'
}

export function TopDetractorsPanel({
  rows,
  siteNamesById,
  periodId,
  limit = 5,
  className,
}: TopDetractorsPanelProps) {
  const ranked = rankDetractors(rows)
  const [expanded, setExpanded] = useState(false)
  const visible = expanded ? ranked : ranked.slice(0, limit)
  const hasMore = ranked.length > limit

  if (ranked.length === 0) {
    return (
      <div className={cn('rounded-lg border border-dashed bg-muted/20 px-4 py-6 text-center', className)}>
        <p className="text-sm text-muted-foreground">
          No score detractors in the visible scope — every active category is at full points.
        </p>
      </div>
    )
  }

  return (
    <div className={cn('rounded-lg border bg-background p-4', className)}>
      <div className="flex items-baseline justify-between gap-2 mb-3">
        <h2 className="text-sm font-semibold flex items-center gap-2">
          <TrendingDown className="h-4 w-4 text-danger" />
          Top score detractors
        </h2>
        <span className="text-[11px] text-muted-foreground">
          Sorted by composite points you&apos;d gain at each site
        </span>
      </div>

      {/* Expanded mode wraps the list in a scroll container so the panel stays
          balanced beside "Score by category" in the 2-column grid on lg+. */}
      <ul className={cn('space-y-1.5', expanded && 'max-h-[400px] overflow-y-auto pr-1')}>
        {visible.map((r, i) => {
          const site = siteNamesById.get(r.siteOrgUnitId)
          // Deep-link without the `group` query param so the detail page shows the
          // full site composite (matches the breakdown the rank was computed against).
          const href = `/kpi/monitoring/${r.siteOrgUnitId}/${periodId}`
          return (
            <li key={`${r.siteOrgUnitId}-${r.category}`}>
              <Link
                href={href}
                className="flex items-center gap-3 rounded-md border bg-muted/10 px-3 py-2 text-xs hover:bg-muted/30 transition-colors"
              >
                <span className="w-5 text-right tabular-nums text-[10px] text-muted-foreground">
                  #{i + 1}
                </span>
                <span className="flex-1 min-w-0 truncate">
                  <span className="font-medium">{site?.name ?? `Site ${r.siteOrgUnitId}`}</span>
                  {site?.code && (
                    <span className="ml-2 font-mono text-[10px] text-muted-foreground">{site.code}</span>
                  )}
                  <span className="mx-2 text-muted-foreground">·</span>
                  <span className="text-muted-foreground">{r.category}</span>
                </span>

                <span className="tabular-nums text-muted-foreground" title="Current category score">
                  {r.categoryScore.toFixed(1)}/100
                </span>

                <span
                  className={cn('tabular-nums rounded px-1.5 py-0.5 font-semibold', impactColour(r.potentialGainPts))}
                  title="Composite points gained if this category reached 100"
                >
                  +{r.potentialGainPts.toFixed(1)} pts
                </span>

                <ArrowUpRight className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
              </Link>
            </li>
          )
        })}
      </ul>

      {hasMore && (
        <button
          type="button"
          onClick={() => setExpanded((v) => !v)}
          className="mt-2 inline-flex items-center gap-1 text-[11px] font-medium text-muted-foreground hover:text-foreground transition-colors"
          aria-expanded={expanded}
        >
          {expanded ? (
            <>
              <ChevronUp className="h-3 w-3" />
              Show top {limit}
            </>
          ) : (
            <>
              <ChevronDown className="h-3 w-3" />
              Show all ({ranked.length})
            </>
          )}
        </button>
      )}
    </div>
  )
}
