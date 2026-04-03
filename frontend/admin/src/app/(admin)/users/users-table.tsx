'use client'

import { useState, useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import { useRouter } from 'next/navigation'
import type { ColumnDef } from '@tanstack/react-table'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { DataTable } from '@/components/shared/data-table'
import { StatusBadge } from '@/components/shared/status-badge'
import { RowActions } from '@/components/shared/row-actions'
import { api } from '@/lib/api'
import type { User } from '@/types/api'

function GapBadge({ status }: { status: string | null }) {
  if (!status || status === 'OK') return null
  return (
    <Badge variant="destructive" className="text-xs">
      {status}
    </Badge>
  )
}

const columns: ColumnDef<User, unknown>[] = [
  {
    accessorKey: 'displayName',
    header: 'Name',
    cell: ({ row }) => (
      <div>
        <p className="font-medium leading-tight">{row.original.displayName}</p>
        <p className="text-xs text-muted-foreground">{row.original.upn}</p>
      </div>
    ),
  },
  {
    accessorKey: 'roleList',
    header: 'Roles',
    cell: ({ row }) => {
      const { roleCount, roleList } = row.original
      if (roleCount === 0) return <span className="text-xs text-muted-foreground">None</span>
      return (
        <div className="flex items-center gap-1.5">
          <span className="tabular-nums text-sm font-medium">{roleCount}</span>
          {roleList && (
            <span className="text-xs text-muted-foreground truncate max-w-[160px]" title={roleList}>
              {roleList}
            </span>
          )}
        </div>
      )
    },
    meta: { className: 'w-[220px]' },
  },
  {
    accessorKey: 'siteCount',
    header: 'Sites',
    cell: ({ row }) => (
      <span className="tabular-nums text-muted-foreground">{row.original.siteCount}</span>
    ),
    meta: { className: 'w-[70px] text-right', headerClassName: 'text-right' },
  },
  {
    accessorKey: 'accountCount',
    header: 'Accounts',
    cell: ({ row }) => (
      <span className="tabular-nums text-muted-foreground">{row.original.accountCount}</span>
    ),
    meta: { className: 'w-[90px] text-right', headerClassName: 'text-right' },
  },
  {
    accessorKey: 'gapStatus',
    header: 'Gap',
    cell: ({ row }) => <GapBadge status={row.original.gapStatus} />,
    meta: { className: 'w-[90px]' },
  },
  {
    accessorKey: 'isActive',
    header: 'Status',
    cell: ({ row }) => (
      <StatusBadge status={row.original.isActive ? 'Active' : 'Inactive'} />
    ),
    meta: { className: 'w-[100px]' },
  },
  {
    id: 'actions',
    header: '',
    cell: ({ row }) => (
      <RowActions
        isActive={row.original.isActive}
        onToggle={() => api.users.setActive(row.original.userId, !row.original.isActive)}
        invalidateKeys={[['users']]}
      />
    ),
    meta: { className: 'w-[40px]' },
  },
]

interface UserTableContentProps {
  queryKey: readonly unknown[]
  queryFn: () => Promise<{ items: User[] }>
  invalidateKeys?: readonly unknown[][]
  searchPlaceholder?: string
}

export function UserTableContent({
  queryKey,
  queryFn,
  invalidateKeys = [['users']],
  searchPlaceholder = 'Search by name, email or role…',
}: UserTableContentProps) {
  const router = useRouter()
  const [search, setSearch] = useState('')

  const { data, isLoading, isError, error } = useQuery({
    queryKey: [...queryKey],
    queryFn,
  })

  const filtered = useMemo(() => {
    if (!data?.items) return []
    const q = search.toLowerCase()
    if (!q) return data.items
    return data.items.filter(
      (u) =>
        u.displayName.toLowerCase().includes(q) ||
        u.upn.toLowerCase().includes(q) ||
        (u.roleList ?? '').toLowerCase().includes(q)
    )
  }, [data, search])

  if (isError) {
    return (
      <div className="rounded-md border border-destructive/40 bg-destructive/5 p-6 text-center">
        <p className="text-sm font-medium text-destructive">Failed to load users</p>
        <p className="mt-1 text-xs text-muted-foreground">
          {error instanceof Error ? error.message : 'An unexpected error occurred.'}
        </p>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      <Input
        placeholder={searchPlaceholder}
        value={search}
        onChange={(e) => setSearch(e.target.value)}
        className="max-w-sm"
      />
      <DataTable
        columns={[
          ...columns.slice(0, -1),
          {
            id: 'actions',
            header: '',
            cell: ({ row }) => (
              <RowActions
                isActive={row.original.isActive}
                onToggle={() => api.users.setActive(row.original.userId, !row.original.isActive)}
                invalidateKeys={invalidateKeys.map((key) => [...key])}
              />
            ),
            meta: { className: 'w-[40px]' },
          },
        ]}
        data={filtered}
        isLoading={isLoading}
        onRowClick={(user) => router.push(`/users/${user.userId}`)}
      />
    </div>
  )
}

export function UsersTable() {
  return (
    <UserTableContent
      queryKey={['users']}
      queryFn={() => api.users.list()}
      invalidateKeys={[['users']]}
    />
  )
}

export function AccountUsersTable({ accountId }: { accountId: number }) {
  return (
    <UserTableContent
      queryKey={['accounts', accountId, 'users']}
      queryFn={() => api.accounts.users(accountId)}
      invalidateKeys={[['users'], ['accounts'], ['accounts', accountId], ['accounts', accountId, 'users']]}
    />
  )
}
