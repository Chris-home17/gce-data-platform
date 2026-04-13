import type { Metadata } from 'next'
import { PageHeader } from '@/components/shared/page-header'
import { SourceMappingTable } from './source-mapping-table'
import { NewSourceMappingDialog } from './new-source-mapping-dialog'

export const metadata: Metadata = { title: 'Source Mapping' }

export default function SourceMappingPage() {
  return (
    <div className="space-y-6">
      <PageHeader
        title="Source Mapping"
        description="Links platform org units to identifiers in external source systems (SAP, Salesforce, etc.)."
        actions={<NewSourceMappingDialog />}
      />
      <SourceMappingTable />
    </div>
  )
}
