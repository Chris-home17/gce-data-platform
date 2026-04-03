import type { Metadata } from 'next'
import { PageHeader } from '@/components/shared/page-header'
import { NewSharedGeoDialog } from './new-shared-geo-dialog'
import { SharedGeoTable } from './shared-geo-table'

export const metadata: Metadata = { title: 'Shared Geography' }

export default function SharedGeographyPage() {
  return (
    <div className="space-y-6">
      <PageHeader
        title="Shared Geography"
        description="Canonical region, sub-region, cluster, and country hierarchy used across all accounts."
        actions={<NewSharedGeoDialog />}
      />
      <SharedGeoTable />
    </div>
  )
}
