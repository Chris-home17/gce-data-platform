import type { Metadata } from 'next'
import { PageHeader } from '@/components/shared/page-header'
import { UsersTable } from './users-table'
import { NewUserDialog } from './new-user-dialog'

export const metadata: Metadata = { title: 'Users' }

export default function UsersPage() {
  return (
    <div className="space-y-6">
      <PageHeader
        title="Users"
        description="View and manage platform users, their roles and site access."
        actions={<NewUserDialog />}
      />
      <UsersTable />
    </div>
  )
}
