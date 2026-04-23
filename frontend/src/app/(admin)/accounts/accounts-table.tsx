'use client'

import { useEffect, useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { useRouter } from 'next/navigation'
import { api } from '@/lib/api'
import { Input } from '@/components/ui/input'
import { DataTable } from '@/components/shared/data-table'
import { ErrorState } from '@/components/shared/error-state'
import { accountColumns } from './columns'
import { usePermissions } from '@/hooks/usePermissions'

/**
 * Client component that owns the data-fetching and table rendering for
 * the Accounts list. Separated from the page so the page itself can remain
 * a server component responsible for metadata and the page-level chrome.
 */
export function AccountsTable() {
  const router = useRouter()
  const [search, setSearch] = useState('')
  const { isSuperAdmin, userId } = usePermissions()

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['accounts'],
    queryFn: () => api.accounts.list(),
  })

  // For non-super-admins, fetch effective access so role-based and delegated
  // account scope is respected, not just direct user grants.
  const { data: myAccess, isLoading: accessLoading } = useQuery({
    queryKey: ['user-effective-access', userId],
    queryFn: () => api.users.effectiveAccess(userId!),
    enabled: !isSuperAdmin && !!userId,
  })

  // Account codes this user can reach via direct grants, role membership, or delegation.
  const allowedAccountCodes = useMemo(() => {
    if (isSuperAdmin) return null
    if (!myAccess) return new Set<string>()
    const codes = new Set(
      myAccess.items
        .filter(g => g.accessType === 'ACCOUNT' && g.accountCode)
        .map(g => g.accountCode)
    )
    return codes
  }, [isSuperAdmin, myAccess])

  const filtered = useMemo(() => {
    if (!data?.items) return []
    let items = data.items
    if (allowedAccountCodes !== null) {
      items = items.filter(a => allowedAccountCodes.has(a.accountCode))
    }
    const q = search.toLowerCase().trim()
    if (!q) return items
    return items.filter(
      (account) =>
        account.accountName.toLowerCase().includes(q) ||
        account.accountCode.toLowerCase().includes(q)
    )
  }, [data, search, allowedAccountCodes])

  // Auto-redirect Account Directors with a single account directly to that account
  const loadingComplete = !isLoading && (!(!isSuperAdmin && !!userId) || !accessLoading)
  useEffect(() => {
    if (!isSuperAdmin && loadingComplete && filtered.length === 1) {
      router.replace(`/accounts/${filtered[0].accountId}`)
    }
  }, [filtered, isSuperAdmin, loadingComplete, router])

  if (isError) {
    return (
      <ErrorState title="Failed to load accounts" error={error} />
    )
  }

  return (
    <div className="space-y-4">
      <Input
        placeholder="Search by account name or code…"
        value={search}
        onChange={(e) => setSearch(e.target.value)}
        className="max-w-sm"
      />
      <DataTable
        columns={accountColumns}
        data={filtered}
        isLoading={isLoading}
        onRowClick={(account) => router.push(`/accounts/${account.accountId}`)}
      />
    </div>
  )
}
