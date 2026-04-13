import type { Metadata } from 'next'
import { PageHeader } from '@/components/shared/page-header'
import { PeriodsTable } from './periods-table'
import { PeriodSchedulesTable } from './period-schedules-table'
import { NewPeriodDialog } from './new-period-dialog'

export const metadata: Metadata = { title: 'KPI Periods' }

export default function KpiPeriodsPage() {
  return (
    <div className="space-y-6">
      <PageHeader
        title="Periods"
        description="Define cadence schedules once, then let the platform generate the reporting periods used operationally below."
        actions={<NewPeriodDialog />}
      />
      <section className="space-y-3">
        <div>
          <h2 className="text-base font-semibold">Period schedules</h2>
          <p className="text-sm text-muted-foreground">
            A schedule defines how often reporting recurs, when the submission window opens and closes, and how far ahead periods should be generated.
          </p>
        </div>
        <PeriodSchedulesTable />
      </section>

      <section className="space-y-3">
        <div>
          <h2 className="text-base font-semibold">Generated periods</h2>
          <p className="text-sm text-muted-foreground">
            These period instances are generated from the active cadence schedules and are used operationally for submissions.
          </p>
        </div>
        <PeriodsTable />
      </section>
    </div>
  )
}
