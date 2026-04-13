import type { Metadata } from 'next'
import { PageHeader } from '@/components/shared/page-header'
import { PlatformRolesTable } from './platform-roles-table'
import { NewPlatformRoleButton } from './new-platform-role-button'

export const metadata: Metadata = { title: 'Platform Roles' }

export default function PlatformRolesPage() {
  return (
    <div className="space-y-6">
      <PageHeader
        title="Platform Roles"
        description="Define functional roles that control what users can do in the admin portal."
        actions={<NewPlatformRoleButton />}
      />
      <PlatformRolesTable />
    </div>
  )
}
