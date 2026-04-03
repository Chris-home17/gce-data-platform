import type { Metadata } from 'next'
import { PageHeader } from '@/components/shared/page-header'
import { SitesTable } from './sites-table'
import { NewSiteDialog } from './new-site-dialog'

export const metadata: Metadata = { title: 'Sites' }

export default function SitesPage() {
  return (
    <div className="space-y-6">
      <PageHeader
        title="Sites"
        description="Org units and physical sites registered across all accounts."
        actions={<NewSiteDialog />}
      />
      <SitesTable />
    </div>
  )
}
