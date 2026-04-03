import { redirect } from 'next/navigation'

/**
 * /kpi — redirect to the default KPI screen (Periods).
 */
export default function KpiRootPage() {
  redirect('/kpi/periods')
}
