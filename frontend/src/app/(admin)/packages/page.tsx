import type { Metadata } from 'next'
import { PageHeader } from '@/components/shared/page-header'
import { PackagesTable } from './packages-table'
import { NewPackageDialog } from './new-package-dialog'

export const metadata: Metadata = { title: 'Packages' }

export default function PackagesPage() {
  return (
    <div className="space-y-6">
      <PageHeader
        title="Packages"
        description="Content packages that group BI reports for access control. Click a package to see its reports."
        actions={<NewPackageDialog />}
      />
      <PackagesTable />
    </div>
  )
}
