import type { ColumnDef } from '@tanstack/react-table'
import { StatusBadge } from '@/components/shared/status-badge'
import { RowActions } from '@/components/shared/row-actions'
import { api } from '@/lib/api'
import type { KpiAssignment } from '@/types/api'

export const assignmentColumns: ColumnDef<KpiAssignment, unknown>[] = [
  {
    accessorKey: 'kpiCode',
    header: 'KPI',
    cell: ({ row }) => (
      <div>
        <p className="font-mono text-sm font-medium">{row.original.kpiCode}</p>
        <p className="text-xs text-muted-foreground">{row.original.kpiName}</p>
        {row.original.category && (
          <p className="text-[11px] text-muted-foreground/80">{row.original.category}</p>
        )}
      </div>
    ),
  },
  {
    accessorKey: 'accountCode',
    header: 'Account',
    cell: ({ row }) => (
      <div>
        <p className="text-sm font-medium">{row.original.accountCode}</p>
        <p className="text-xs text-muted-foreground">{row.original.accountName}</p>
      </div>
    ),
    meta: { className: 'w-36' },
  },
  {
    id: 'scope',
    header: 'Scope',
    cell: ({ row }) => {
      const { isAccountWide, siteCode, siteName } = row.original
      if (isAccountWide) {
        return (
          <span className="inline-flex items-center rounded-full border border-blue-200 bg-blue-50 px-2 py-0.5 text-xs font-medium text-blue-700 dark:border-blue-800 dark:bg-blue-900/30 dark:text-blue-400">
            Account-wide
          </span>
        )
      }
      return (
        <div>
          <p className="font-mono text-sm">{siteCode}</p>
          <p className="text-xs text-muted-foreground">{siteName}</p>
        </div>
      )
    },
  },
  {
    accessorKey: 'periodLabel',
    header: 'Period',
    cell: ({ row }) => (
      <span className="font-mono text-sm">{row.original.periodLabel}</span>
    ),
    meta: { className: 'w-24' },
  },
  {
    accessorKey: 'isRequired',
    header: 'Required',
    cell: ({ row }) => (
      <span className={`text-sm font-medium ${row.original.isRequired ? 'text-foreground' : 'text-muted-foreground'}`}>
        {row.original.isRequired ? 'Yes' : 'No'}
      </span>
    ),
    meta: { className: 'w-20' },
  },
  {
    id: 'thresholds',
    header: 'Green / Amber',
    cell: ({ row }) => {
      const { dataType, thresholdGreen, thresholdAmber, effectiveThresholdDirection } = row.original
      const supportsThresholds = ['Numeric', 'Percentage', 'Currency'].includes(dataType)
      if (!supportsThresholds) {
        return <span className="text-muted-foreground text-xs">N/A</span>
      }
      if (thresholdGreen === null && thresholdAmber === null) {
        return <span className="text-muted-foreground text-sm">—</span>
      }
      const dir = effectiveThresholdDirection === 'Higher' ? '↑' : effectiveThresholdDirection === 'Lower' ? '↓' : ''
      return (
        <span className="tabular-nums text-sm">
          {dir} {thresholdGreen ?? '—'} / {thresholdAmber ?? '—'}
        </span>
      )
    },
    meta: { className: 'w-32 tabular-nums' },
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
        onToggle={() => api.kpi.assignments.setActive(row.original.assignmentId, !row.original.isActive)}
        invalidateKeys={[['kpi', 'assignments']]}
      />
    ),
    meta: { className: 'w-[40px]' },
  },
]
