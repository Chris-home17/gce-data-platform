// Shared composite-score decomposition.
//
// Mirrors `App.vSiteCompositeScore` (KpiScoringPhase2.Up.sql:571) so the
// breakdown UI shows the same numbers as the server. Single source of truth
// for the per-category and per-KPI contribution math, and for the what-if
// simulator. If the server formula ever changes, this file must change too —
// tests in `score-breakdown.test.ts` exercise both layers against fixtures.
//
// SQL reminder:
//   CategoryScore_c = Σ(Score_k × KpiWeight_k) / Σ(KpiWeight_k)
//                     where Score IS NOT NULL  (Text + missing-not-penalised excluded)
//   Composite       = Σ(CategoryScore_c × CategoryWeight_c) / Σ(CategoryWeight_c)
//                     where CategoryActive = 1 AND CategoryScore IS NOT NULL

import type { SiteCategoryScore, SiteSubmissionDetail } from '@/types/api'

export interface KpiContribution {
  /** Stable id for keying / re-mapping. */
  assignmentId: number
  externalId: string
  kpiCode: string
  kpiName: string
  category: string
  isRequired: boolean
  isSubmitted: boolean
  /** Current 0-100 score, or null if excluded from scoring. */
  score: number | null
  kpiWeight: number
  /** Normalised composite weight: Σ over all KPIs equals 1 (subject to NULL exclusions).
   *  Multiplying current `score` by this and summing reproduces the composite. */
  normalisedWeight: number
  /** Points this KPI currently contributes to the composite (= score × normalisedWeight). */
  contributionPts: number
  /** Points you would gain on the composite by lifting this KPI to 100. Always ≥ 0.
   *  Excluded (Text/missing-NULL) KPIs report 0 — they don't move the composite. */
  potentialGainPts: number
}

export interface CategoryContribution {
  category: string
  /** Live category score (0-100) per the SQL view. NULL when no scoreable KPIs exist. */
  categoryScore: number | null
  categoryWeight: number
  categoryActive: boolean
  scoredCount: number
  totalCount: number
  /** Weight of this category in the composite, normalised to sum=1 across active+scored cats. */
  normalisedCategoryWeight: number
  /** This category's current contribution to the composite (categoryScore × normalisedCategoryWeight). */
  contributionPts: number
  /** Points you would gain on the composite by lifting this category's score to 100. */
  potentialGainPts: number
  /** KPI rows belonging to this category, ordered by potentialGainPts desc. */
  kpis: KpiContribution[]
}

export interface CompositeBreakdown {
  /** Re-derived composite, computed from the same inputs the server uses. */
  composite: number | null
  /** Sum of all KPI normalisedWeights — should be 1.0 (or 0 if nothing scoreable). */
  totalNormalisedWeight: number
  categories: CategoryContribution[]
}

const EPSILON = 1e-9

/** Decompose the composite score for a single (Site × Period) into category and KPI
 *  contributions. Inputs are the two API payloads the monitoring screens already
 *  fetch: per-category rows from `SiteCategoryScore[]` and per-KPI rows from
 *  `SiteSubmissionDetail[]`. */
export function buildBreakdown(
  submissions: SiteSubmissionDetail[],
  categoryRows: SiteCategoryScore[],
): CompositeBreakdown {
  // Group KPI rows by category for quick lookup.
  const byCategory = new Map<string, SiteSubmissionDetail[]>()
  for (const s of submissions) {
    const cat = s.category ?? 'General'
    const bucket = byCategory.get(cat)
    if (bucket) bucket.push(s)
    else byCategory.set(cat, [s])
  }

  // Build the per-category row set. We use the server-supplied categoryScore
  // (authoritative) and only use KPI rows for the contribution decomposition.
  // This avoids drift from any subtle SQL behaviour we'd otherwise re-implement.
  const activeCategoryWeightSum = categoryRows
    .filter((c) => c.categoryActive && c.categoryScore !== null)
    .reduce((s, c) => s + c.categoryWeight, 0)

  const categories: CategoryContribution[] = categoryRows.map((cat) => {
    const kpiRows = byCategory.get(cat.category) ?? []

    // Within the category, normalise KpiWeights across rows whose Score IS NOT NULL.
    const scoredKpis = kpiRows.filter((k) => k.score !== null && k.kpiWeight !== null)
    const inCategoryWeightSum = scoredKpis.reduce((s, k) => s + (k.kpiWeight ?? 0), 0)

    const normalisedCategoryWeight =
      cat.categoryActive && cat.categoryScore !== null && activeCategoryWeightSum > EPSILON
        ? cat.categoryWeight / activeCategoryWeightSum
        : 0

    const kpis: KpiContribution[] = kpiRows.map((k) => {
      const kpiWeight = k.kpiWeight ?? 0
      const isScored = k.score !== null && kpiWeight > 0 && inCategoryWeightSum > EPSILON

      // Per-KPI normalised weight in the composite = (kpiWeight / Σ kpiWeight in cat)
      // × (categoryWeight / Σ active categoryWeight). Excluded rows get 0.
      const normalisedWeight = isScored
        ? (kpiWeight / inCategoryWeightSum) * normalisedCategoryWeight
        : 0

      const score = k.score ?? 0
      const contributionPts = isScored ? score * normalisedWeight : 0
      const potentialGainPts = isScored ? Math.max(0, (100 - score)) * normalisedWeight : 0

      return {
        assignmentId: k.assignmentId,
        externalId: k.externalId,
        kpiCode: k.kpiCode,
        kpiName: k.effectiveKpiName,
        category: cat.category,
        isRequired: k.isRequired,
        isSubmitted: k.isSubmitted,
        score: k.score,
        kpiWeight,
        normalisedWeight,
        contributionPts,
        potentialGainPts,
      }
    })

    kpis.sort((a, b) => b.potentialGainPts - a.potentialGainPts)

    const contributionPts =
      cat.categoryScore !== null ? cat.categoryScore * normalisedCategoryWeight : 0
    const potentialGainPts =
      cat.categoryScore !== null
        ? Math.max(0, 100 - cat.categoryScore) * normalisedCategoryWeight
        : 0

    return {
      category: cat.category,
      categoryScore: cat.categoryScore,
      categoryWeight: cat.categoryWeight,
      categoryActive: cat.categoryActive,
      scoredCount: cat.scoredCount,
      totalCount: cat.totalCount,
      normalisedCategoryWeight,
      contributionPts,
      potentialGainPts,
      kpis,
    }
  })

  // Sort categories by their drag on the composite: biggest opportunity first.
  categories.sort((a, b) => b.potentialGainPts - a.potentialGainPts)

  const composite = categoryRows[0]?.compositeScore ?? null
  const totalNormalisedWeight = categories.reduce(
    (s, c) => s + c.kpis.reduce((cs, k) => cs + k.normalisedWeight, 0),
    0,
  )

  return { composite, totalNormalisedWeight, categories }
}

/** Compute the composite that would result if `overrides` (assignmentId → score 0-100)
 *  were applied. Used by the what-if simulator. Excluded KPIs (Text, etc.) are
 *  not overridable — the server ignores them and so do we. */
export function simulateComposite(
  breakdown: CompositeBreakdown,
  overrides: ReadonlyMap<number, number>,
): number | null {
  if (breakdown.totalNormalisedWeight < EPSILON) return null
  let total = 0
  for (const cat of breakdown.categories) {
    for (const k of cat.kpis) {
      if (k.normalisedWeight === 0) continue
      const override = overrides.get(k.assignmentId)
      const score = override !== undefined ? clamp(override, 0, 100) : k.score ?? 0
      total += score * k.normalisedWeight
    }
  }
  return total
}

function clamp(n: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, n))
}

/** Sanity check — returns true when our re-derived composite agrees with the
 *  server's `compositeScore` field within `tolerance`. The breakdown UI calls
 *  this in dev mode and warns to the console on mismatch, so silent SQL/JS
 *  drift surfaces immediately. */
export function verifyAgainstServer(breakdown: CompositeBreakdown, tolerance = 0.5): boolean {
  if (breakdown.composite === null) return true
  const reconstructed = breakdown.categories.reduce((s, c) => s + c.contributionPts, 0)
  return Math.abs(reconstructed - breakdown.composite) <= tolerance
}
