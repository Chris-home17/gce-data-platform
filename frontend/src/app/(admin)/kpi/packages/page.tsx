import type { Metadata } from 'next'
import { PageHeader } from '@/components/shared/page-header'
import { PackagesTable } from './packages-table'
import { NewPackageDialog } from './new-package-dialog'

export const metadata: Metadata = { title: 'KPI Packages' }

export default function KpiPackagesPage() {
  return (
    <div className="space-y-6">
      <PageHeader
        title="KPI Packages"
        description="Named bundles of KPIs that can be assigned to sites together."
        actions={<NewPackageDialog />}
      />
      <PackagesTable />
    </div>
  )
}
