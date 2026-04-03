'use client'

import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { useRouter } from 'next/navigation'
import { api } from '@/lib/api'
import { Input } from '@/components/ui/input'
import { DataTable } from '@/components/shared/data-table'
import { accountColumns } from './columns'

/**
 * Client component that owns the data-fetching and table rendering for
 * the Accounts list. Separated from the page so the page itself can remain
 * a server component responsible for metadata and the page-level chrome.
 */
export function AccountsTable() {
  const router = useRouter()
  const [search, setSearch] = useState('')

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['accounts'],
    queryFn: () => api.accounts.list(),
  })

  const filtered = useMemo(() => {
    if (!data?.items) return []
    const q = search.toLowerCase().trim()
    if (!q) return data.items
    return data.items.filter(
      (account) =>
        account.accountName.toLowerCase().includes(q) ||
        account.accountCode.toLowerCase().includes(q)
    )
  }, [data, search])

  if (isError) {
    return (
      <div className="rounded-md border border-destructive/40 bg-destructive/5 p-6 text-center">
        <p className="text-sm font-medium text-destructive">Failed to load accounts</p>
        <p className="mt-1 text-xs text-muted-foreground">
          {error instanceof Error ? error.message : 'An unexpected error occurred.'}
        </p>
      </div>
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
