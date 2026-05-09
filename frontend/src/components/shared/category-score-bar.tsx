'use client'

import { cn } from '@/lib/utils'
import type { SiteCategoryScore } from '@/types/api'

interface CategoryScoreBarProps {
  /** All category rows from /kpi/site-scores. The component aggregates across rows
   *  with the same `category` so it can be passed either a single site's data
   *  or several sites pre-aggregated. */
  rows: SiteCategoryScore[]
  className?: string
}

/**
 * Horizontal bar list showing the per-category score breakdown that feeds
 * the composite. Mirrors the visual treatment of CompletionBar in the
 * monitoring view — same rounded track + status colour mapping.
 */
export function CategoryScoreBar({ rows, className }: CategoryScoreBarProps) {
  // When `rows` covers multiple sites, aggregate to one bar per category by
  // taking a weight-aware average of CategoryScore. Single-site usage falls
  // through the same code with one input row per category.
  const buckets = new Map<string, { score: number; weight: number; weightSum: number; active: boolean }>()
  for (const r of rows) {
    if (r.categoryScore === null) continue
    const cur = buckets.get(r.category)
    if (cur) {
      cur.score += r.categoryScore * r.categoryWeight
      cur.weightSum += r.categoryWeight
      cur.active = cur.active && r.categoryActive
    } else {
      buckets.set(r.category, {
        score: r.categoryScore * r.categoryWeight,
        weight: r.categoryWeight,
        weightSum: r.categoryWeight,
        active: r.categoryActive,
      })
    }
  }

  const aggregated = Array.from(buckets.entries())
    .map(([category, b]) => ({
      category,
      score: b.weightSum > 0 ? b.score / b.weightSum : null,
      active: b.active,
    }))
    .sort((a, b) => a.category.localeCompare(b.category))

  if (aggregated.length === 0) {
    return (
      <p className={cn('text-xs text-muted-foreground rounded-md border border-dashed px-3 py-2', className)}>
        No category scores yet for this selection.
      </p>
    )
  }

  return (
    <div className={cn('space-y-2', className)}>
      {aggregated.map(({ category, score, active }) => {
        const colour =
          score === null ? 'bg-muted'
          : score >= 80   ? 'bg-success'
          : score >= 50   ? 'bg-warning'
          : 'bg-danger'
        return (
          <div key={category} className="flex items-center gap-2">
            <span className={cn('w-32 text-xs', !active && 'text-muted-foreground line-through')}>
              {category}
            </span>
            <div className="h-2 flex-1 overflow-hidden rounded-full bg-secondary">
              <div
                className={cn('h-full rounded-full transition-all', colour)}
                style={{ width: `${score === null ? 0 : Math.min(score, 100)}%` }}
              />
            </div>
            <span className="w-12 text-right text-xs tabular-nums text-muted-foreground">
              {score === null ? '—' : score.toFixed(0)}
            </span>
          </div>
        )
      })}
    </div>
  )
}
