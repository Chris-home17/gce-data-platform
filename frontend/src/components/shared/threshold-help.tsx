import { Info } from 'lucide-react'

export interface ThresholdHelpProps {
  direction: 'Higher' | 'Lower' | null
  /** When true, illustrate with HH:MM:SS values; otherwise plain numbers. */
  isTime?: boolean
}

// Inline help card that explains the Green/Amber/Red threshold semantics, dynamic
// to the user's chosen direction. Lives above the threshold inputs in every form
// that touches them (new assignment, edit assignment, multi-KPI wizard) because
// users — including the one who designed this model — keep getting the bands
// inverted. Keep the copy concrete: name the band, name the comparison.
export function ThresholdHelp({ direction, isTime = false }: ThresholdHelpProps) {
  const ex = (label: string, op: '<=' | '>=', segment: string) =>
    isTime
      ? `${label} when value ${op} ${segment} threshold`
      : `${label} when value ${op} ${segment} threshold`

  let body: React.ReactNode

  if (direction === 'Lower') {
    body = (
      <>
        <p>
          With <strong>Lower is better</strong> (e.g.&nbsp;response time, defect rate), each
          threshold marks the <em>upper bound</em> of its band:
        </p>
        <ul className="mt-1.5 space-y-0.5 list-disc pl-5">
          <li><span className="font-semibold text-success-foreground">Green</span> — value ≤ Green threshold</li>
          <li><span className="font-semibold text-warning-foreground">Amber</span> — between Green and Amber thresholds</li>
          <li><span className="font-semibold text-danger-foreground">Red</span> — above Amber threshold</li>
        </ul>
      </>
    )
  } else if (direction === 'Higher') {
    body = (
      <>
        <p>
          With <strong>Higher is better</strong> (e.g.&nbsp;completion rate, on-time delivery),
          each threshold marks the <em>lower bound</em> of its band:
        </p>
        <ul className="mt-1.5 space-y-0.5 list-disc pl-5">
          <li><span className="font-semibold text-success-foreground">Green</span> — value ≥ Green threshold</li>
          <li><span className="font-semibold text-warning-foreground">Amber</span> — between Amber and Green thresholds</li>
          <li><span className="font-semibold text-danger-foreground">Red</span> — below Amber threshold</li>
        </ul>
      </>
    )
  } else {
    body = (
      <p>
        Pick a <strong>Direction</strong> above to see how Green / Amber / Red bands are computed.
        For "Lower is better" KPIs (response time, defect count) Green is the lowest band; for
        "Higher is better" KPIs (completion rate) Green is the highest.
      </p>
    )
  }

  return (
    <div className="rounded-md border border-dashed bg-muted/40 px-3 py-2.5 text-xs text-muted-foreground">
      <div className="flex items-center gap-1.5 font-semibold text-foreground mb-1">
        <Info className="h-3.5 w-3.5" />
        How thresholds work
      </div>
      {body}
      <p className="mt-1.5 text-[11px] italic">
        The Red threshold is informational only — the dot is computed from Green and Amber.
      </p>
    </div>
  )
}
