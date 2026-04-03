'use client'

import { useQuery } from '@tanstack/react-query'
import type { ColumnDef } from '@tanstack/react-table'
import { Badge } from '@/components/ui/badge'
import { DataTable } from '@/components/shared/data-table'
import { StatusBadge } from '@/components/shared/status-badge'
import { RowActions } from '@/components/shared/row-actions'
import { api } from '@/lib/api'
import type { Delegation } from '@/types/api'

function PrincipalBadge({ name, type }: { name: string; type: string }) {
  return (
    <div className="flex items-center gap-1.5">
      <Badge variant="outline" className="text-[10px] uppercase tracking-wide px-1.5 py-0">
        {type}
      </Badge>
      <span className="text-sm font-medium">{name}</span>
    </div>
  )
}

function ScopeBadge({ delegation }: { delegation: Delegation }) {
  if (delegation.accessType === 'ALL') {
    return <Badge variant="secondary" className="text-xs">All Accounts</Badge>
  }
  if (delegation.scopeType === 'ORGUNIT') {
    return (
      <div className="space-y-0.5">
        <span className="block text-sm">{delegation.accountName}</span>
        <span className="block font-mono text-xs text-muted-foreground">
          {delegation.orgUnitType} / {delegation.orgUnitCode}
        </span>
      </div>
    )
  }
  return (
    <span className="text-sm">{delegation.accountName}</span>
  )
}

const columns: ColumnDef<Delegation, unknown>[] = [
  {
    accessorKey: 'delegatorName',
    header: 'Delegator',
    cell: ({ row }) => (
      <PrincipalBadge name={row.original.delegatorName} type={row.original.delegatorType} />
    ),
  },
  {
    accessorKey: 'delegateName',
    header: 'Delegate',
    cell: ({ row }) => (
      <PrincipalBadge name={row.original.delegateName} type={row.original.delegateType} />
    ),
  },
  {
    id: 'scope',
    header: 'Scope',
    cell: ({ row }) => <ScopeBadge delegation={row.original} />,
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
        onToggle={() =>
          row.original.isActive
            ? api.delegations.revoke(row.original.principalDelegationId)
            : Promise.resolve()
        }
        invalidateKeys={[['delegations']]}
        entityLabel="delegation"
      />
    ),
    meta: { className: 'w-[40px]' },
  },
]

export function DelegationsTable() {
  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['delegations'],
    queryFn: () => api.delegations.list(),
  })

  if (isError) {
    return (
      <div className="rounded-md border border-destructive/40 bg-destructive/5 p-6 text-center">
        <p className="text-sm font-medium text-destructive">Failed to load delegations</p>
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
