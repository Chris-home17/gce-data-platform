import type { Metadata } from 'next'
import { PageHeader } from '@/components/shared/page-header'
import { RolesTable } from './roles-table'
import { NewRoleDialog } from './new-role-dialog'

export const metadata: Metadata = { title: 'Roles' }

export default function RolesPage() {
  return (
    <div className="space-y-6">
      <PageHeader
        title="Roles"
        description="Define and manage RBAC roles and their policy bindings."
        actions={<NewRoleDialog />}
      />
      <RolesTable />
    </div>
  )
}
