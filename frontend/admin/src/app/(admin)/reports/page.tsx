import type { Metadata } from 'next'
import { PageHeader } from '@/components/shared/page-header'
import { ReportsTable } from './reports-table'
import { NewReportDialog } from './new-report-dialog'
import { AssignPackageDialog } from './assign-package-dialog'

export const metadata: Metadata = { title: 'BI Reports' }

export default function ReportsPage() {
  return (
    <div className="space-y-6">
      <PageHeader
        title="BI Reports"
        description="Power BI report definitions and their package assignments."
        actions={
          <div className="flex items-center gap-2">
            <AssignPackageDialog />
            <NewReportDialog />
          </div>
        }
      />
      <ReportsTable />
    </div>
  )
}
