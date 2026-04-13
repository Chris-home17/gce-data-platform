import type { Metadata } from 'next'
import { KpiAssignmentsPageClient } from './page-client'

export const metadata: Metadata = { title: 'KPI Assignments' }

export default function KpiAssignmentsPage() {
  return <KpiAssignmentsPageClient />
}
