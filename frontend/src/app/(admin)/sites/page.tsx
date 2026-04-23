'use client'

import { PageHeader } from '@/components/shared/page-header'
import { SitesTable, AccountSitesTable } from './sites-table'
import { NewSiteDialog } from './new-site-dialog'
import { usePermissions } from '@/hooks/usePermissions'
import { useAccount } from '@/contexts/account-context'

export default function SitesPage() {
  const { isSuperAdmin } = usePermissions()
  const { selectedAccount } = useAccount()

  const description = isSuperAdmin
    ? 'Org units and physical sites registered across all accounts.'
    : selectedAccount
      ? `Org units and physical sites in ${selectedAccount.accountName}.`
      : 'Org units and physical sites in your account.'

  return (
    <div className="space-y-6">
      <PageHeader
        title="Sites"
        description={description}
        actions={<NewSiteDialog />}
      />
      {isSuperAdmin ? (
        <SitesTable />
      ) : selectedAccount ? (
        <AccountSitesTable accountId={selectedAccount.accountId} />
      ) : null}
    </div>
  )
}
