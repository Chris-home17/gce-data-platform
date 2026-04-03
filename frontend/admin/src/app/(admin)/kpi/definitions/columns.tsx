import type { ColumnDef } from '@tanstack/react-table'
import { StatusBadge } from '@/components/shared/status-badge'
import { RowActions } from '@/components/shared/row-actions'
import { api } from '@/lib/api'
import type { KpiDefinition } from '@/types/api'

export const definitionColumns: ColumnDef<KpiDefinition, unknown>[] = [
  {
    accessorKey: 'kpiCode',
    header: 'Code',
    cell: ({ row }) => (
      <span className="font-mono text-sm font-medium">{row.original.kpiCode}</span>
    ),
    meta: { className: 'w-24' },
  },
  {
    accessorKey: 'kpiName',
    header: 'Name',
    cell: ({ row }) => (
      <div>
        <p className="font-medium">{row.original.kpiName}</p>
      </div>
    ),
  },
  {
    accessorKey: 'category',
    header: 'Category',
    cell: ({ row }) => (
      <span className="text-sm">{row.original.category ?? '—'}</span>
    ),
    meta: { className: 'w-36' },
  },
  {
    accessorKey: 'dataType',
    header: 'Type',
    cell: ({ row }) => (
      <span className="text-sm text-muted-foreground">{row.original.dataType}</span>
    ),
    meta: { className: 'w-28' },
  },
  {
    accessorKey: 'unit',
    header: 'Unit',
    cell: ({ row }) => (
      <span className="text-sm text-muted-foreground">{row.original.unit ?? '—'}</span>
    ),
    meta: { className: 'w-28' },
  },
  {
    accessorKey: 'thresholdDirection',
    header: 'Direction',
    cell: ({ row }) => {
      const dir = row.original.thresholdDirection
      if (!dir) return <span className="text-muted-foreground">—</span>
      return (
        <span className={`text-sm font-medium ${dir === 'Higher' ? 'text-green-700' : 'text-blue-700'}`}>
          {dir === 'Higher' ? '↑ Higher' : '↓ Lower'}
        </span>
      )
    },
    meta: { className: 'w-28' },
  },
  {
    accessorKey: 'collectionType',
    header: 'Collection',
    cell: ({ row }) => (
      <span className="text-sm text-muted-foreground">{row.original.collectionType}</span>
    ),
    meta: { className: 'w-28' },
  },
  {
    accessorKey: 'assignmentCount',
    header: 'Assignments',
    cell: ({ row }) => (
      <span className="tabular-nums text-sm">{row.original.assignmentCount}</span>
    ),
    meta: { className: 'w-28 text-right', headerClassName: 'text-right' },
  },
  {
    accessorKey: 'isActive',
    header: 'Status',
    cell: ({ row }) => <StatusBadge status={row.original.isActive ? 'Active' : 'Inactive'} />,
    meta: { className: 'w-24' },
  },
  {
    id: 'actions',
    header: '',
    cell: ({ row }) => (
      <RowActions
        isActive={row.original.isActive}
        onToggle={() => api.kpi.definitions.setActive(row.original.kpiId, !row.original.isActive)}
        invalidateKeys={[['kpi', 'definitions']]}
      />
    ),
    meta: { className: 'w-[40px]' },
  },
]
