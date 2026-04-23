'use client'

import { useState } from 'react'
import { UserPlus } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { PageHeader } from '@/components/shared/page-header'
import { UsersTable, AccountUsersTable } from './users-table'
import { OnboardUserWizard } from '@/components/shared/onboard-user-wizard'
import { usePermissions } from '@/hooks/usePermissions'
import { useAccount } from '@/contexts/account-context'
import { PERMISSIONS } from '@/types/api'

export default function UsersPage() {
  const { can, isSuperAdmin } = usePermissions()
  const { selectedAccount } = useAccount()
  const [onboardOpen, setOnboardOpen] = useState(false)

  // Tenant admins see only the users in their selected account. Super admins
  // see the platform-wide user list. This is the main entry-point where a
  // missing gate used to leak every tenant's users to every tenant admin.
  const description = isSuperAdmin
    ? 'View and manage platform users, their roles and site access.'
    : selectedAccount
      ? `View and manage users in ${selectedAccount.accountName}, their roles and site access.`
      : 'View and manage users in your account.'

  return (
    <div className="space-y-6">
      <PageHeader
        title="Users"
        description={description}
        actions={
          can(PERMISSIONS.USERS_MANAGE) ? (
            <Button size="sm" onClick={() => setOnboardOpen(true)}>
              <UserPlus className="mr-1.5 h-4 w-4" />
              Onboard User
            </Button>
          ) : undefined
        }
      />
      {isSuperAdmin ? (
        <UsersTable />
      ) : selectedAccount ? (
        <AccountUsersTable accountId={selectedAccount.accountId} />
      ) : null}
      <OnboardUserWizard open={onboardOpen} onOpenChange={setOnboardOpen} />
    </div>
  )
}
