'use client'

import { useEffect, useMemo, useState } from 'react'
import { ChevronDown, Sparkles, RotateCcw, Info } from 'lucide-react'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import {
  buildBreakdown,
  simulateComposite,
  verifyAgainstServer,
  type CompositeBreakdown,
  type KpiContribution,
} from '@/lib/score-breakdown'
import type { SiteCategoryScore, SiteSubmissionDetail } from '@/types/api'

interface ScoreBreakdownCardProps {
  submissions: SiteSubmissionDetail[]
  categoryRows: SiteCategoryScore[]
  className?: string
}

function scoreColour(s: number | null): string {
  if (s === null) return 'bg-muted'
  if (s >= 80) return 'bg-success'
  if (s >= 50) return 'bg-warning'
  return 'bg-danger'
}

function compositeColour(s: number | null): string {
  if (s === null) return 'text-muted-foreground'
  if (s >= 80) return 'text-success'
  if (s >= 50) return 'text-warning'
  return 'text-danger'
}

export function ScoreBreakdownCard({ submissions, categoryRows, className }: ScoreBreakdownCardProps) {
  const breakdown: CompositeBreakdown = useMemo(
    () => buildBreakdown(submissions, categoryRows),
    [submissions, categoryRows],
  )

  const [overrides, setOverrides] = useState<Map<number, number>>(new Map())
  const [expanded, setExpanded] = useState<Set<string>>(() => new Set())

  // Reset what-if overrides whenever the underlying data changes — stale overrides
  // for KPIs that no longer exist would silently distort the simulated number.
  const dataKey = useMemo(
    () => submissions.map((s) => s.assignmentId).sort((a, b) => a - b).join(','),
    [submissions],
  )
  useEffect(() => {
    setOverrides(new Map())
  }, [dataKey])

  // Dev-mode drift check: warn loudly when our reconstructed composite disagrees
  // with the server. Catches SQL/JS divergence without needing a separate test run.
  useEffect(() => {
    if (process.env.NODE_ENV === 'production') return
    if (!verifyAgainstServer(breakdown)) {
      const reconstructed = breakdown.categories.reduce((s, c) => s + c.contributionPts, 0)
      // eslint-disable-next-line no-console
      console.warn(
        '[ScoreBreakdownCard] Composite drift detected — server says',
        breakdown.composite,
        'reconstructed',
        reconstructed,
        'breakdown:',
        breakdown,
      )
    }
  }, [breakdown])

  const simulating = overrides.size > 0
  const simulated = useMemo(() => simulateComposite(breakdown, overrides), [breakdown, overrides])
  const composite = breakdown.composite

  const totalGain =
    composite !== null && simulated !== null && simulating ? Math.max(0, simulated - composite) : 0

  const toggleSimulate = (k: KpiContribution) => {
    setOverrides((prev) => {
      const next = new Map(prev)
      if (next.has(k.assignmentId)) next.delete(k.assignmentId)
      else next.set(k.assignmentId, 100)
      return next
    })
  }

  const toggleExpand = (cat: string) =>
    setExpanded((prev) => {
      const next = new Set(prev)
      if (next.has(cat)) next.delete(cat)
      else next.add(cat)
      return next
    })

  const reset = () => setOverrides(new Map())

  if (breakdown.totalNormalisedWeight < 1e-9 && composite === null) {
    return (
      <div className={cn('rounded-lg border border-dashed bg-muted/20 px-4 py-6 text-center', className)}>
        <p className="text-sm text-muted-foreground">
          No scoreable KPIs yet — submit at least one Boolean, DropDown, or numeric KPI to see a breakdown.
        </p>
      </div>
    )
  }

  return (
    <div className={cn('rounded-lg border bg-background p-5', className)}>
      {/* Header */}
      <div className="flex items-start justify-between gap-4 flex-wrap">
        <div>
          <h2 className="text-sm font-semibold flex items-center gap-2">
            Score breakdown
            <span
              className="inline-flex items-center gap-1 text-[10px] font-normal uppercase tracking-wider text-muted-foreground"
              title="Click a row's “Fix to 100” chip to simulate fixing that KPI and see how the composite would move."
            >
              <Info className="h-3 w-3" /> What-if enabled
            </span>
          </h2>
          <p className="text-xs text-muted-foreground mt-0.5">
            Each KPI&apos;s normalised weight (KpiWeight ÷ category KpiWeight × CategoryWeight ÷ Σ active CategoryWeight) sums to 1.
          </p>
        </div>

        {/* Composite + simulated value */}
        <div className="flex items-center gap-4">
          <div className="text-right">
            <div className="text-[10px] uppercase tracking-wider text-muted-foreground">Composite</div>
            <div className={cn('text-2xl font-semibold tabular-nums leading-none', compositeColour(composite))}>
              {composite === null ? '—' : composite.toFixed(1)}
            </div>
          </div>
          {simulating && simulated !== null && (
            <>
              <ChevronDown className="h-5 w-5 -rotate-90 text-muted-foreground" />
              <div className="text-right">
                <div className="text-[10px] uppercase tracking-wider text-info">Simulated</div>
                <div className={cn('text-2xl font-semibold tabular-nums leading-none', compositeColour(simulated))}>
                  {simulated.toFixed(1)}
                </div>
                {totalGain > 0 && (
                  <div className="text-[11px] text-success font-medium tabular-nums">
                    +{totalGain.toFixed(1)} pts
                  </div>
                )}
              </div>
              <Button variant="ghost" size="sm" onClick={reset} className="text-xs">
                <RotateCcw className="mr-1 h-3 w-3" />
                Reset
              </Button>
            </>
          )}
        </div>
      </div>

      {/* Category contribution rows */}
      <div className="mt-5 space-y-3">
        {breakdown.categories.map((cat) => {
          const isExpanded = expanded.has(cat.category)
          const inactive = !cat.categoryActive
          const noScore = cat.categoryScore === null
          // Width of the category contribution bar relative to the composite ceiling (100 pts).
          // This is "share of composite" — lets you see at a glance which categories own the score.
          const ownedPct = cat.normalisedCategoryWeight * 100
          // Width of the filled portion: how much of the owned share is actually realised.
          const filledPct = cat.categoryScore === null ? 0 : (cat.categoryScore / 100) * ownedPct

          return (
            <div key={cat.category} className="rounded-md border bg-muted/10">
              <button
                type="button"
                className="flex w-full items-center gap-3 px-3 py-2 text-left hover:bg-muted/30 transition-colors"
                onClick={() => toggleExpand(cat.category)}
                aria-expanded={isExpanded}
              >
                <ChevronDown
                  className={cn(
                    'h-3.5 w-3.5 shrink-0 text-muted-foreground transition-transform',
                    isExpanded ? 'rotate-0' : '-rotate-90',
                  )}
                />
                <span
                  className={cn(
                    'w-28 shrink-0 text-xs font-medium truncate',
                    inactive && 'text-muted-foreground line-through',
                  )}
                  title={cat.category}
                >
                  {cat.category}
                </span>

                {/* Stacked contribution bar.
                    Outer track = 100 pts of composite (the universe).
                    Mid section = ownedPct (what this category gets to control).
                    Inner fill  = filledPct (what it has actually delivered). */}
                <div className="relative h-2.5 flex-1 overflow-hidden rounded-full bg-secondary/40">
                  <div
                    className="absolute inset-y-0 left-0 bg-secondary rounded-full"
                    style={{ width: `${ownedPct}%` }}
                    title={`Owns ${ownedPct.toFixed(1)} pts of the composite`}
                  />
                  <div
                    className={cn('absolute inset-y-0 left-0 rounded-full transition-all', scoreColour(cat.categoryScore))}
                    style={{ width: `${filledPct}%` }}
                  />
                </div>

                <div className="flex w-44 shrink-0 items-baseline justify-end gap-2 tabular-nums text-xs">
                  <span className={cn('font-semibold', noScore ? 'text-muted-foreground' : '')}>
                    {noScore ? '—' : cat.categoryScore?.toFixed(1)}
                  </span>
                  <span className="text-muted-foreground">×</span>
                  <span className="text-muted-foreground" title="Normalised category weight">
                    {(cat.normalisedCategoryWeight * 100).toFixed(0)}%
                  </span>
                  <span className="text-muted-foreground">=</span>
                  <span className="font-semibold">{cat.contributionPts.toFixed(1)}</span>
                  <span className="text-[10px] text-muted-foreground">pts</span>
                </div>
              </button>

              {/* Per-KPI rows */}
              {isExpanded && cat.kpis.length > 0 && (
                <div className="border-t bg-background">
                  {cat.kpis.map((k) => {
                    const isExcluded = k.normalisedWeight === 0
                    const overridden = overrides.has(k.assignmentId)
                    const effectiveScore = overridden ? overrides.get(k.assignmentId)! : k.score
                    const liveContribution = (effectiveScore ?? 0) * k.normalisedWeight
                    return (
                      <div
                        key={k.assignmentId}
                        className={cn(
                          'flex items-center gap-3 px-3 py-2 text-xs border-b last:border-b-0',
                          overridden && 'bg-info-muted/40',
                        )}
                      >
                        <span className="flex-1 min-w-0">
                          <span className="font-medium truncate inline-block max-w-full align-middle">
                            {k.kpiName}
                          </span>
                          <span className="ml-2 font-mono text-[10px] text-muted-foreground">
                            {k.kpiCode}
                          </span>
                          {isExcluded && (
                            <span
                              className="ml-2 text-[10px] text-muted-foreground"
                              title="Text KPIs and missing-not-penalised assignments don't affect the score."
                            >
                              · not scored
                            </span>
                          )}
                        </span>

                        <div className="flex w-72 shrink-0 items-center justify-end gap-2 tabular-nums">
                          {/* Current / simulated score */}
                          <span
                            className={cn(
                              'min-w-[2ch] text-right',
                              overridden && 'text-info-muted-foreground font-semibold',
                              !overridden && k.score === null && 'text-muted-foreground',
                            )}
                          >
                            {effectiveScore === null ? '—' : effectiveScore.toFixed(1)}
                          </span>
                          <span className="text-muted-foreground">×</span>
                          <span
                            className="min-w-[3ch] text-right text-muted-foreground"
                            title="Normalised weight in the composite"
                          >
                            {(k.normalisedWeight * 100).toFixed(1)}%
                          </span>
                          <span className="text-muted-foreground">=</span>
                          <span className="min-w-[3ch] text-right font-medium">
                            {liveContribution.toFixed(2)}
                          </span>
                          <span className="text-[10px] text-muted-foreground">pts</span>

                          {/* What-if toggle — disabled for excluded KPIs and KPIs already at 100. */}
                          {isExcluded ? (
                            <span className="w-24 shrink-0" />
                          ) : k.score === 100 && !overridden ? (
                            <span className="w-24 shrink-0 text-right text-[10px] text-success">
                              full points
                            </span>
                          ) : (
                            <button
                              type="button"
                              onClick={() => toggleSimulate(k)}
                              className={cn(
                                'inline-flex w-24 shrink-0 items-center justify-center gap-1 rounded-md border px-2 py-0.5 text-[11px] font-medium transition-colors',
                                overridden
                                  ? 'border-info-border bg-info-muted text-info-muted-foreground hover:bg-info-muted/70'
                                  : 'border-input bg-background hover:bg-muted',
                              )}
                              title={
                                overridden
                                  ? 'Stop simulating — restore the actual score'
                                  : `Simulate this KPI as 100. You would gain +${k.potentialGainPts.toFixed(1)} pts.`
                              }
                            >
                              {overridden ? (
                                <>Restore</>
                              ) : (
                                <>
                                  <Sparkles className="h-3 w-3" />+{k.potentialGainPts.toFixed(1)}
                                </>
                              )}
                            </button>
                          )}
                        </div>
                      </div>
                    )
                  })}
                </div>
              )}
            </div>
          )
        })}
      </div>
    </div>
  )
}
