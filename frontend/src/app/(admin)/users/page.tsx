'use client'

import { useState } from 'react'
import { UserPlus } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { PageHeader } from '@/components/shared/page-header'
import { UsersTable } from './users-table'
import { OnboardUserWizard } from '@/components/shared/onboard-user-wizard'
import { usePermissions } from '@/hooks/usePermissions'
import { PERMISSIONS } from '@/types/api'

export default function UsersPage() {
  const { can } = usePermissions()
  const [onboardOpen, setOnboardOpen] = useState(false)

  return (
    <div className="space-y-6">
      <PageHeader
        title="Users"
        description="View and manage platform users, their roles and site access."
        actions={
          can(PERMISSIONS.USERS_MANAGE) ? (
            <Button size="sm" onClick={() => setOnboardOpen(true)}>
              <UserPlus className="mr-1.5 h-4 w-4" />
              Onboard User
            </Button>
          ) : undefined
        }
      />
      <UsersTable />
      <OnboardUserWizard open={onboardOpen} onOpenChange={setOnboardOpen} />
    </div>
  )
}
