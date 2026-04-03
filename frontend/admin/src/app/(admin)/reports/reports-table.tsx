'use client'

import { useQuery } from '@tanstack/react-query'
import type { ColumnDef } from '@tanstack/react-table'
import { Badge } from '@/components/ui/badge'
import { DataTable } from '@/components/shared/data-table'
import { StatusBadge } from '@/components/shared/status-badge'
import { RowActions } from '@/components/shared/row-actions'
import { api } from '@/lib/api'
import type { BiReport } from '@/types/api'

const columns: ColumnDef<BiReport, unknown>[] = [
  {
    accessorKey: 'reportCode',
    header: 'Code',
    cell: ({ row }) => (
      <span className="font-mono text-sm font-medium">{row.original.reportCode}</span>
    ),
    meta: { className: 'w-[160px]' },
  },
  {
    accessorKey: 'reportName',
    header: 'Name',
    cell: ({ row }) => <span className="font-medium">{row.original.reportName}</span>,
  },
  {
    accessorKey: 'reportUri',
    header: 'URI',
    cell: ({ row }) =>
      row.original.reportUri ? (
        <span className="font-mono text-xs text-muted-foreground truncate max-w-[260px] block">
          {row.original.reportUri}
        </span>
      ) : (
        <span className="text-muted-foreground/40 text-xs">—</span>
      ),
  },
  {
    accessorKey: 'packageList',
    header: 'Packages',
    cell: ({ row }) => {
      const list = row.original.packageList
      if (!list) return <span className="text-muted-foreground/40 text-xs">none</span>
      return (
        <div className="flex flex-wrap gap-1">
          {list.split(', ').map((code) => (
            <Badge key={code} variant="secondary" className="font-mono text-xs">{code}</Badge>
          ))}
        </div>
      )
    },
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
        onToggle={() => api.reports.setActive(row.original.biReportId, !row.original.isActive)}
        invalidateKeys={[['reports']]}
      />
    ),
    meta: { className: 'w-[40px]' },
  },
]

export function ReportsTable() {
  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['reports'],
    queryFn: () => api.reports.list(),
  })

  if (isError) {
    return (
      <div className="rounded-md border border-destructive/40 bg-destructive/5 p-6 text-center">
        <p className="text-sm font-medium text-destructive">Failed to load reports</p>
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
    />
  )
}
