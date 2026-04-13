import type { Metadata } from 'next'
import { PageHeader } from '@/components/shared/page-header'
import { DefinitionsTable } from './definitions-table'
import { NewDefinitionDialog } from './new-definition-dialog'

export const metadata: Metadata = { title: 'KPI Library' }

export default function KpiDefinitionsPage() {
  return (
    <div className="space-y-6">
      <PageHeader
        title="KPI Library"
        description="Master catalogue of measurable KPIs. Thresholds and targets are set per assignment, not here."
        actions={<NewDefinitionDialog />}
      />
      <DefinitionsTable />
    </div>
  )
}
