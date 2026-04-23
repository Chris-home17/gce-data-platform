'use client'

import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { useRouter } from 'next/navigation'
import type { ColumnDef } from '@tanstack/react-table'
import { Input } from '@/components/ui/input'
import { DataTable } from '@/components/shared/data-table'
import { StatusBadge } from '@/components/shared/status-badge'
import { RowActions } from '@/components/shared/row-actions'
import { ErrorState } from '@/components/shared/error-state'
import { api } from '@/lib/api'
import type { PlatformRole } from '@/types/api'
import { usePermissions } from '@/hooks/usePermissions'
import { PERMISSIONS } from '@/types/api'

export function PlatformRolesTable() {
  const router = useRouter()
  const [search, setSearch] = useState('')
  const { can } = usePermissions()
  const canManage = can(PERMISSIONS.PLATFORM_ROLES_MANAGE)

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['platform-roles'],
    queryFn: () => api.platformRoles.list(),
  })

  const columns: ColumnDef<PlatformRole, unknown>[] = useMemo(() => [
    {
      accessorKey: 'roleCode',
      header: 'Code',
      cell: ({ row }) => (
        <span className="font-mono text-sm font-medium">{row.original.roleCode}</span>
      ),
      meta: { className: 'w-[200px]' },
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
      accessorKey: 'permissionCount',
      header: 'Permissions',
      cell: ({ row }) => (
        <span className="tabular-nums text-muted-foreground">{row.original.permissionCount}</span>
      ),
      meta: { className: 'w-[110px] text-right', headerClassName: 'text-right' },
    },
    {
      accessorKey: 'isActive',
      header: 'Status',
      cell: ({ row }) => (
        <StatusBadge status={row.original.isActive ? 'Active' : 'Inactive'} />
      ),
      meta: { className: 'w-[100px]' },
    },
    ...(canManage ? [{
      id: 'actions',
      header: '',
      cell: ({ row }: { row: { original: PlatformRole } }) => (
        <RowActions
          isActive={row.original.isActive}
          onToggle={() => api.platformRoles.setActive(row.original.platformRoleId, !row.original.isActive)}
          invalidateKeys={[['platform-roles']]}
        />
      ),
      meta: { className: 'w-[40px]' },
    } as ColumnDef<PlatformRole, unknown>] : []),
  ], [canManage])

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
      <ErrorState title="Failed to load platform roles" error={error} />
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
        onRowClick={(role) => router.push(`/platform-roles/${role.platformRoleId}`)}
      />
    </div>
  )
}
