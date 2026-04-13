import type { Metadata } from 'next'
import { PageHeader } from '@/components/shared/page-header'
import { MonitoringView } from './monitoring-view'

export const metadata: Metadata = { title: 'Submission Monitoring' }

export default function KpiMonitoringPage() {
  return (
    <div className="space-y-6">
      <PageHeader
        title="Submission Monitoring"
        description="Track KPI submission completion and identify gaps across sites, by period."
      />
      <MonitoringView />
    </div>
  )
}
