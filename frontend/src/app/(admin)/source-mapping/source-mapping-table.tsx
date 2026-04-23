'use client'

import { useQuery } from '@tanstack/react-query'
import type { ColumnDef } from '@tanstack/react-table'
import { Badge } from '@/components/ui/badge'
import { DataTable } from '@/components/shared/data-table'
import { StatusBadge } from '@/components/shared/status-badge'
import { ErrorState } from '@/components/shared/error-state'
import { api } from '@/lib/api'
import type { SourceMapping } from '@/types/api'

const columns: ColumnDef<SourceMapping, unknown>[] = [
  {
    accessorKey: 'sourceSystem',
    header: 'Source System',
    cell: ({ row }) => (
      <Badge variant="secondary" className="font-mono text-xs">
        {row.original.sourceSystem}
      </Badge>
    ),
    meta: { className: 'w-[140px]' },
  },
  {
    accessorKey: 'sourceOrgUnitId',
    header: 'Source ID',
    cell: ({ row }) => (
      <span className="font-mono text-sm">{row.original.sourceOrgUnitId}</span>
    ),
    meta: { className: 'w-[160px]' },
  },
  {
    accessorKey: 'sourceOrgUnitName',
    header: 'Source Name',
    cell: ({ row }) => (
      <span className="text-sm text-muted-foreground">
        {row.original.sourceOrgUnitName ?? '—'}
      </span>
    ),
  },
  {
    accessorKey: 'orgUnitCode',
    header: 'Platform Unit',
    cell: ({ row }) => (
      <div className="flex flex-col gap-0.5">
        <span className="font-mono text-sm font-medium">{row.original.orgUnitCode}</span>
        <span className="text-xs text-muted-foreground">{row.original.orgUnitName}</span>
      </div>
    ),
  },
  {
    accessorKey: 'orgUnitType',
    header: 'Type',
    cell: ({ row }) => (
      <span className="font-mono text-xs text-muted-foreground">{row.original.orgUnitType}</span>
    ),
    meta: { className: 'w-[100px]' },
  },
  {
    accessorKey: 'accountCode',
    header: 'Account',
    cell: ({ row }) => (
      <span className="font-mono text-xs text-muted-foreground">{row.original.accountCode}</span>
    ),
    meta: { className: 'w-[120px]' },
  },
  {
    accessorKey: 'isActive',
    header: 'Status',
    cell: ({ row }) => (
      <StatusBadge status={row.original.isActive ? 'Active' : 'Inactive'} />
    ),
    meta: { className: 'w-[100px]' },
  },
]

export function SourceMappingTable() {
  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['source-mappings'],
    queryFn: () => api.sourceMappings.list(),
  })

  if (isError) {
    return (
      <ErrorState title="Failed to load source mappings" error={error} />
    )
  }

  return (
    <DataTable
      columns={columns}
      data={data?.items ?? []}
      isLoading={isLoading}
    />
  )
}
