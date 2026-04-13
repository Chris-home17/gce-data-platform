'use client'

import { useQuery } from '@tanstack/react-query'
import { useRouter } from 'next/navigation'
import type { ColumnDef } from '@tanstack/react-table'
import { Badge } from '@/components/ui/badge'
import { DataTable } from '@/components/shared/data-table'
import { StatusBadge } from '@/components/shared/status-badge'
import { RowActions } from '@/components/shared/row-actions'
import { api } from '@/lib/api'
import type { Package } from '@/types/api'

const columns: ColumnDef<Package, unknown>[] = [
  {
    accessorKey: 'packageCode',
    header: 'Code',
    cell: ({ row }) => (
      <span className="font-mono text-sm font-medium">{row.original.packageCode}</span>
    ),
    meta: { className: 'w-[160px]' },
  },
  {
    accessorKey: 'packageName',
    header: 'Name',
    cell: ({ row }) => <span className="font-medium">{row.original.packageName}</span>,
  },
  {
    accessorKey: 'packageGroup',
    header: 'Group',
    cell: ({ row }) =>
      row.original.packageGroup ? (
        <Badge variant="secondary" className="text-xs">{row.original.packageGroup}</Badge>
      ) : (
        <span className="text-muted-foreground/40">—</span>
      ),
    meta: { className: 'w-[160px]' },
  },
  {
    accessorKey: 'reportCount',
    header: 'Reports',
    cell: ({ row }) => (
      <span className="tabular-nums text-sm text-muted-foreground">{row.original.reportCount}</span>
    ),
    meta: { className: 'w-[90px] text-right', headerClassName: 'text-right' },
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
        onToggle={() => api.packages.setActive(row.original.packageId, !row.original.isActive)}
        invalidateKeys={[['packages']]}
      />
    ),
    meta: { className: 'w-[40px]' },
  },
]

export function PackagesTable() {
  const router = useRouter()

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['packages'],
    queryFn: () => api.packages.list(),
  })

  if (isError) {
    return (
      <div className="rounded-md border border-destructive/40 bg-destructive/5 p-6 text-center">
        <p className="text-sm font-medium text-destructive">Failed to load packages</p>
        <p className="mt-1 text-xs text-muted-foreground">
          {error instanceof Error ? error.message : 'An unexpected error occurred.'}
        </p>
      </div>
    )
  }

  return (
    <DataTable
      columns={columns}
      data={data?.items ?? []}
      isLoading={isLoading}
      onRowClick={(pkg) => router.push(`/packages/${pkg.packageId}`)}
    />
  )
}
