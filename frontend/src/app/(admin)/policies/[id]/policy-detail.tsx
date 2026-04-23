'use client'

import { useQuery } from '@tanstack/react-query'
import { useRouter } from 'next/navigation'
import type { ColumnDef } from '@tanstack/react-table'
import { ArrowLeft, ShieldCheck } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { DataTable } from '@/components/shared/data-table'
import { StatusBadge } from '@/components/shared/status-badge'
import { ErrorState } from '@/components/shared/error-state'
import { api } from '@/lib/api'
import type { PolicyRole } from '@/types/api'

const roleColumns: ColumnDef<PolicyRole, unknown>[] = [
  {
    accessorKey: 'roleCode',
    header: 'Role',
    cell: ({ row }) => (
      <div>
        <p className="font-mono text-sm font-medium">{row.original.roleCode}</p>
        <p className="text-xs text-muted-foreground">{row.original.roleName}</p>
      </div>
    ),
  },
  {
    accessorKey: 'accountCode',
    header: 'Account',
    cell: ({ row }) => (
      <div>
        <p className="text-sm font-medium">{row.original.accountName}</p>
        <p className="font-mono text-xs text-muted-foreground">{row.original.accountCode}</p>
      </div>
    ),
  },
  {
    id: 'scope',
    header: 'Scope',
    cell: ({ row }) => {
      if (row.original.scopeType === 'NONE') {
        return <Badge variant="outline" className="text-xs">Global</Badge>
      }

      return (
        <div className="space-y-0.5">
          <span className="block text-sm">{row.original.orgUnitName ?? 'N/A'}</span>
          <span className="block font-mono text-xs text-muted-foreground">
            {row.original.orgUnitType ?? 'N/A'} / {row.original.orgUnitCode ?? 'N/A'}
          </span>
        </div>
      )
    },
  },
  {
    accessorKey: 'isActive',
    header: 'Status',
    cell: ({ row }) => <StatusBadge status={row.original.isActive ? 'Active' : 'Inactive'} />,
    meta: { className: 'w-[100px]' },
  },
]

export function PolicyDetail({ policyId }: { policyId: number }) {
  const router = useRouter()

  const { data: policy, isLoading: policyLoading } = useQuery({
    queryKey: ['policies', policyId],
    queryFn: () => api.policies.get(policyId),
  })

  const { data: rolesData, isLoading: rolesLoading } = useQuery({
    queryKey: ['policies', policyId, 'roles'],
    queryFn: () => api.policies.roles(policyId),
    enabled: !!policy,
  })

  if (policyLoading) {
    return (
      <div className="space-y-6">
        <div className="h-8 w-48 animate-pulse rounded bg-muted" />
        <div className="h-24 rounded-lg bg-muted animate-pulse" />
      </div>
    )
  }

  if (!policy) {
    return (
      <ErrorState title="Policy not found." />
    )
  }

  return (
    <div className="space-y-6">
      <div>
        <Button variant="ghost" size="sm" className="-ml-2 mb-3" onClick={() => router.push('/policies')}>
          <ArrowLeft className="mr-1.5 h-4 w-4" />
          Policies
        </Button>

        <div className="flex items-start justify-between gap-4">
          <div>
            <div className="flex items-center gap-2 flex-wrap">
              <h1 className="text-2xl font-semibold">{policy.policyName}</h1>
              <StatusBadge status={policy.isActive ? 'Active' : 'Inactive'} />
            </div>
            <div className="mt-2 flex flex-wrap items-center gap-2">
              <Badge variant="outline" className="font-mono text-xs">
                {policy.roleCodeTemplate}
              </Badge>
              <Badge variant={policy.scopeType === 'ORGUNIT' ? 'secondary' : 'outline'} className="text-xs">
                {policy.scopeType === 'ORGUNIT' ? 'Org Unit Scoped' : 'Global'}
              </Badge>
              {policy.scopeType === 'ORGUNIT' && (
                <Badge variant="outline" className="text-xs">
                  {policy.orgUnitType}/{policy.orgUnitCode ?? '*'}
                </Badge>
              )}
              {policy.expandPerOrgUnit && (
                <Badge variant="outline" className="text-xs">Per unit</Badge>
              )}
            </div>
            <p className="mt-2 text-sm text-muted-foreground">{policy.roleNameTemplate}</p>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-1 max-w-xs">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">Linked Roles</CardTitle>
            <ShieldCheck className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <p className="text-2xl font-semibold tabular-nums">{rolesData?.totalCount ?? 0}</p>
          </CardContent>
        </Card>
      </div>

      <div>
        <h2 className="mb-3 text-base font-semibold">Roles Materialized from this Policy</h2>
        <DataTable
          columns={roleColumns}
          data={rolesData?.items ?? []}
          isLoading={rolesLoading}
        />
      </div>
    </div>
  )
}
