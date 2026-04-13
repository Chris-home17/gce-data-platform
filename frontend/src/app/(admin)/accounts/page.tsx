import type { Metadata } from 'next'
import { PageHeader } from '@/components/shared/page-header'
import { AccountsTable } from './accounts-table'
import { NewAccountDialog } from './new-account-dialog'

export const metadata: Metadata = {
  title: 'Accounts',
}

/**
 * A-01 — Accounts list
 *
 * Server component. Data fetching is delegated to the AccountsTable client
 * component via TanStack Query so the page shell renders immediately without
 * blocking on the API call.
 */
export default function AccountsPage() {
  return (
    <div className="space-y-6">
      <PageHeader
        title="Accounts"
        description="Manage platform accounts, their sites, and assigned users."
        actions={<NewAccountDialog />}
      />
      <AccountsTable />
    </div>
  )
}
