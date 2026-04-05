'use client'

import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { ColumnDef } from '@tanstack/react-table'
import { CheckCircle, MoreHorizontal, Pencil, RefreshCw, XCircle } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { DataTable } from '@/components/shared/data-table'
import { StatusBadge } from '@/components/shared/status-badge'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { api } from '@/lib/api'
import type { Policy } from '@/types/api'
import { EditPolicyDialog } from './edit-policy-dialog'

function PolicyRowActions({ policy, onEdit }: { policy: Policy; onEdit: () => void }) {
  const queryClient = useQueryClient()

  const toggleMutation = useMutation({
    mutationFn: () => api.policies.setActive(policy.accountRolePolicyId, !policy.isActive),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['policies'] })
    },
  })

  const refreshMutation = useMutation({
    mutationFn: () => api.policies.refresh(policy.accountRolePolicyId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['policies'] })
      queryClient.invalidateQueries({ queryKey: ['accounts'] })
      queryClient.invalidateQueries({ queryKey: ['users'] })
      queryClient.invalidateQueries({ queryKey: ['roles'] })
    },
  })

  const isPending = toggleMutation.isPending || refreshMutation.isPending

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          variant="ghost"
          size="sm"
          className="h-7 w-7 p-0 data-[state=open]:bg-muted"
          disabled={isPending}
          onClick={(e) => e.stopPropagation()}
        >
          <MoreHorizontal className="h-4 w-4" />
          <span className="sr-only">Actions</span>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuItem onClick={(e) => { e.stopPropagation(); onEdit() }}>
          <Pencil className="mr-2 h-4 w-4" />
          Edit
        </DropdownMenuItem>
        <DropdownMenuSeparator />
        <DropdownMenuItem onClick={(e) => { e.stopPropagation(); refreshMutation.mutate() }}>
          <RefreshCw className="mr-2 h-4 w-4" />
          Refresh policy
        </DropdownMenuItem>
        {policy.isActive ? (
          <DropdownMenuItem
            className="text-destructive focus:text-destructive"
            onClick={(e) => { e.stopPropagation(); toggleMutation.mutate() }}
          >
            <XCircle className="mr-2 h-4 w-4" />
            Deactivate
          </DropdownMenuItem>
        ) : (
          <DropdownMenuItem onClick={(e) => { e.stopPropagation(); toggleMutation.mutate() }}>
            <CheckCircle className="mr-2 h-4 w-4 text-emerald-600" />
            Activate
          </DropdownMenuItem>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

function makeColumns(onEdit: (policy: Policy) => void): ColumnDef<Policy, unknown>[] {
  return [
    {
      accessorKey: 'policyName',
      header: 'Policy Name',
      cell: ({ row }) => <span className="font-medium">{row.original.policyName}</span>,
    },
    {
      accessorKey: 'roleCodeTemplate',
      header: 'Role Code Template',
      cell: ({ row }) => (
        <span className="font-mono text-sm">{row.original.roleCodeTemplate}</span>
      ),
      meta: { className: 'w-[220px]' },
    },
    {
      accessorKey: 'roleNameTemplate',
      header: 'Role Name Template',
      cell: ({ row }) => (
        <span className="text-sm text-muted-foreground">{row.original.roleNameTemplate}</span>
      ),
    },
    {
      accessorKey: 'scopeType',
      header: 'Scope',
      cell: ({ row }) => {
        const { scopeType, orgUnitType, orgUnitCode, expandPerOrgUnit } = row.original
        if (scopeType === 'ORGUNIT') {
          return (
            <div className="flex items-center gap-1.5">
              <Badge variant="secondary" className="text-xs">Org Unit</Badge>
              <span className="font-mono text-xs text-muted-foreground">
                {orgUnitType}/{orgUnitCode ?? '*'}
              </span>
              {expandPerOrgUnit && <Badge variant="outline" className="text-xs">Per unit</Badge>}
            </div>
          )
        }
        return <Badge variant="outline" className="text-xs">Global</Badge>
      },
      meta: { className: 'w-[200px]' },
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
        <PolicyRowActions policy={row.original} onEdit={() => onEdit(row.original)} />
      ),
      meta: { className: 'w-[40px]' },
    },
  ]
}

export function PoliciesTable() {
  const [editingPolicy, setEditingPolicy] = useState<Policy | null>(null)

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['policies'],
    queryFn: () => api.policies.list(),
  })

  const columns = makeColumns(setEditingPolicy)

  if (isError) {
    return (
      <div className="rounded-md border border-destructive/40 bg-destructive/5 p-6 text-center">
        <p className="text-sm font-medium text-destructive">Failed to load policies</p>
        <p className="mt-1 text-xs text-muted-foreground">
          {error instanceof Error ? error.message : 'An unexpected error occurred.'}
        </p>
      </div>
    )
  }

  return (
    <>
      <DataTable
        columns={columns}
        data={data?.items ?? []}
        isLoading={isLoading}
      />
      <EditPolicyDialog
        policy={editingPolicy}
        open={!!editingPolicy}
        onOpenChange={(open) => { if (!open) setEditingPolicy(null) }}
      />
    </>
  )
}
