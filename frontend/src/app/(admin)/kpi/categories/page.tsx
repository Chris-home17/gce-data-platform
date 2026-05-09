import type { Metadata } from 'next'
import { PageHeader } from '@/components/shared/page-header'
import { CategoriesTable } from './categories-table'
import { NewCategoryDialog } from './new-category-dialog'

export const metadata: Metadata = { title: 'KPI Categories' }

export default function KpiCategoriesPage() {
  return (
    <div className="space-y-6">
      <PageHeader
        title="KPI Categories"
        description="Global lookup of KPI categories shared across all accounts. Code is locked once created — auto-generated KPI codes use it as a prefix."
        actions={<NewCategoryDialog />}
      />
      <CategoriesTable />
    </div>
  )
}
