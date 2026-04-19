import type { Metadata } from 'next'
import { PageHeader } from '@/components/shared/page-header'
import { TagsTable } from './tags-table'
import { NewTagDialog } from './new-tag-dialog'

export const metadata: Metadata = { title: 'Tags' }

export default function TagsPage() {
  return (
    <div className="space-y-6">
      <PageHeader
        title="Tags"
        description="Reusable labels that can be applied to KPIs for filtering and organisation."
        actions={<NewTagDialog />}
      />
      <TagsTable />
    </div>
  )
}
