import type { Metadata } from 'next'
import { PageHeader } from '@/components/shared/page-header'
import { DelegationsTable } from './delegations-table'
import { NewDelegationDialog } from './new-delegation-dialog'

export const metadata: Metadata = { title: 'Delegations' }

export default function DelegationsPage() {
  return (
    <div className="space-y-6">
      <PageHeader
        title="Delegations"
        description="Manage access delegations between users and roles."
        actions={<NewDelegationDialog />}
      />
      <DelegationsTable />
    </div>
  )
}
