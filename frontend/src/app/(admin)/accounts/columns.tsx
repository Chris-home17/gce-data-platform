'use client'

import type { ColumnDef } from '@tanstack/react-table'
import type { Account } from '@/types/api'
import { StatusBadge } from '@/components/shared/status-badge'
import { RowActions } from '@/components/shared/row-actions'
import { api } from '@/lib/api'

export const accountColumns: ColumnDef<Account, unknown>[] = [
  {
    accessorKey: 'accountCode',
    header: 'Account Code',
    cell: ({ row }) => (
      <span className="font-mono text-sm font-medium">{row.original.accountCode}</span>
    ),
    meta: { className: 'w-[160px]' },
  },
  {
    accessorKey: 'accountName',
    header: 'Account Name',
    cell: ({ row }) => <span className="font-medium">{row.original.accountName}</span>,
  },
  {
    accessorKey: 'siteCount',
    header: 'Sites',
    cell: ({ row }) => (
      <span className="tabular-nums text-muted-foreground">{row.original.siteCount}</span>
    ),
    meta: { className: 'w-[80px] text-right', headerClassName: 'text-right' },
  },
  {
    accessorKey: 'userCount',
    header: 'Users',
    cell: ({ row }) => (
      <span className="tabular-nums text-muted-foreground">{row.original.userCount}</span>
    ),
    meta: { className: 'w-[80px] text-right', headerClassName: 'text-right' },
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
        onToggle={() => api.accounts.setActive(row.original.accountId, !row.original.isActive)}
        invalidateKeys={[['accounts']]}
      />
    ),
    meta: { className: 'w-[40px]' },
  },
]
