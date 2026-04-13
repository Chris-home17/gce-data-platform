'use client'

import { useState, useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import { useRouter } from 'next/navigation'
import type { ColumnDef } from '@tanstack/react-table'
import { Input } from '@/components/ui/input'
import { DataTable } from '@/components/shared/data-table'
import { StatusBadge } from '@/components/shared/status-badge'
import { RowActions } from '@/components/shared/row-actions'
import { api } from '@/lib/api'
import type { Role } from '@/types/api'

const columns: ColumnDef<Role, unknown>[] = [
  {
    accessorKey: 'roleCode',
    header: 'Code',
    cell: ({ row }) => (
      <span className="font-mono text-sm font-medium">{row.original.roleCode}</span>
    ),
    meta: { className: 'w-[180px]' },
  },
  {
    accessorKey: 'roleName',
    header: 'Name',
    cell: ({ row }) => <span className="font-medium">{row.original.roleName}</span>,
  },
  {
    accessorKey: 'description',
    header: 'Description',
    cell: ({ row }) => (
      <span className="text-sm text-muted-foreground">
        {row.original.description ?? '—'}
      </span>
    ),
  },
  {
    accessorKey: 'memberCount',
    header: 'Members',
    cell: ({ row }) => (
      <span className="tabular-nums text-muted-foreground">{row.original.memberCount}</span>
    ),
    meta: { className: 'w-[90px] text-right', headerClassName: 'text-right' },
  },
  {
    accessorKey: 'accessGrantCount',
    header: 'Access Grants',
    cell: ({ row }) => (
      <span className="tabular-nums text-muted-foreground">{row.original.accessGrantCount}</span>
    ),
    meta: { className: 'w-[120px] text-right', headerClassName: 'text-right' },
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
        onToggle={() => api.roles.setActive(row.original.roleId, !row.original.isActive)}
        invalidateKeys={[['roles']]}
      />
    ),
    meta: { className: 'w-[40px]' },
  },
]

export function RolesTable() {
  const router = useRouter()
  const [search, setSearch] = useState('')

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['roles'],
    queryFn: () => api.roles.list(),
  })

  const filtered = useMemo(() => {
    if (!data?.items) return []
    const q = search.toLowerCase()
    if (!q) return data.items
    return data.items.filter(
      (r) =>
        r.roleCode.toLowerCase().includes(q) ||
        r.roleName.toLowerCase().includes(q) ||
        (r.description ?? '').toLowerCase().includes(q)
    )
  }, [data, search])

  if (isError) {
    return (
      <div className="rounded-md border border-destructive/40 bg-destructive/5 p-6 text-center">
        <p className="text-sm font-medium text-destructive">Failed to load roles</p>
        <p className="mt-1 text-xs text-muted-foreground">
          {error instanceof Error ? error.message : 'An unexpected error occurred.'}
        </p>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      <Input
        placeholder="Search by code, name or description…"
        value={search}
        onChange={(e) => setSearch(e.target.value)}
        className="max-w-sm"
      />
      <DataTable
        columns={columns}
        data={filtered}
        isLoading={isLoading}
        onRowClick={(role) => router.push(`/roles/${role.roleId}`)}
      />
    </div>
  )
}
