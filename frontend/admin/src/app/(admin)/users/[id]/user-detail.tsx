'use client'

import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useRouter } from 'next/navigation'
import type { ColumnDef } from '@tanstack/react-table'
import { ArrowLeft, ShieldCheck, MapPin, Building2, AlertTriangle, Trash2, ShieldPlus } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { DataTable } from '@/components/shared/data-table'
import { StatusBadge } from '@/components/shared/status-badge'
import { GrantAccessDialog } from '@/components/shared/grant-access-dialog'
import { api } from '@/lib/api'
import type { Delegation, Grant, PackageGrant, Role } from '@/types/api'

// ---------------------------------------------------------------------------
// Column definitions
// ---------------------------------------------------------------------------
function roleColumns(onRemove: (roleId: number, roleCode: string, upn: string) => void, upn: string): ColumnDef<Role, unknown>[] {
  return [
    {
      accessorKey: 'roleCode',
      header: 'Code',
      cell: ({ row }) => (
        <span className="font-mono text-sm font-medium">{row.original.roleCode}</span>
      ),
      meta: { className: 'w-[180px]' },
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
        <span className="text-sm text-muted-foreground">{row.original.description ?? '—'}</span>
      ),
    },
    {
      id: 'remove',
      header: '',
      cell: ({ row }) => (
        <Button
          size="sm"
          variant="ghost"
          className="text-destructive hover:text-destructive hover:bg-destructive/10"
          onClick={() => onRemove(row.original.roleId, row.original.roleCode, upn)}
        >
          <Trash2 className="h-3.5 w-3.5" />
        </Button>
      ),
      meta: { className: 'w-[50px]' },
    },
  ]
}

const grantColumns: ColumnDef<Grant, unknown>[] = [
  {
    accessorKey: 'accessType',
    header: 'Scope',
    cell: ({ row }) => {
      const { accessType, accountName, scopeType } = row.original
      if (accessType === 'ALL') return <Badge variant="outline" className="text-xs">All Accounts</Badge>
      if (scopeType === 'ORGUNIT')
        return (
          <div className="flex flex-col gap-0.5">
            <span className="text-sm font-medium">{accountName}</span>
            <span className="font-mono text-xs text-muted-foreground">{row.original.orgUnitCode}</span>
          </div>
        )
      return <span className="text-sm">{accountName}</span>
    },
  },
  {
    accessorKey: 'orgUnitName',
    header: 'Org Unit',
    cell: ({ row }) => {
      if (row.original.scopeType !== 'ORGUNIT') return <span className="text-muted-foreground/40">—</span>
      return (
        <div>
          <span className="text-sm">{row.original.orgUnitName}</span>
          <span className="ml-2 font-mono text-xs text-muted-foreground">{row.original.orgUnitType}</span>
        </div>
      )
    },
  },
  {
    accessorKey: 'grantedOnUtc',
    header: 'Granted',
    cell: ({ row }) => (
      <span className="text-sm text-muted-foreground">
        {new Date(row.original.grantedOnUtc).toLocaleDateString()}
      </span>
    ),
    meta: { className: 'w-[120px]' },
  },
  {
    id: 'revoke',
    header: '',
    cell: ({ row }) => <RevokeGrantButton grantId={row.original.principalAccessGrantId} userId={row.original.principalId} />,
    meta: { className: 'w-[50px]' },
  },
]

const packageGrantColumns: ColumnDef<PackageGrant, unknown>[] = [
  {
    accessorKey: 'packageCode',
    header: 'Package',
    cell: ({ row }) => {
      if (row.original.grantScope === 'ALL_PACKAGES')
        return <Badge variant="outline" className="text-xs">All Packages</Badge>
      return (
        <div>
          <span className="font-mono text-sm font-medium">{row.original.packageCode}</span>
          <span className="ml-2 text-sm text-muted-foreground">{row.original.packageName}</span>
        </div>
      )
    },
  },
  {
    accessorKey: 'grantedOnUtc',
    header: 'Granted',
    cell: ({ row }) => (
      <span className="text-sm text-muted-foreground">
        {new Date(row.original.grantedOnUtc).toLocaleDateString()}
      </span>
    ),
    meta: { className: 'w-[120px]' },
  },
  {
    id: 'revoke',
    header: '',
    cell: ({ row }) => <RevokePackageGrantButton grantId={row.original.principalPackageGrantId} userId={row.original.principalId} />,
    meta: { className: 'w-[50px]' },
  },
]

const delegationColumns: ColumnDef<Delegation, unknown>[] = [
  {
    accessorKey: 'delegatorName',
    header: 'Delegated By',
    cell: ({ row }) => (
      <div>
        <p className="font-medium leading-tight">{row.original.delegatorName}</p>
        <p className="text-xs text-muted-foreground">{row.original.delegatorType}</p>
      </div>
    ),
  },
  {
    id: 'delegatedScope',
    header: 'Scope',
    cell: ({ row }) => {
      const delegation = row.original
      if (delegation.accessType === 'ALL') {
        return <Badge variant="outline" className="text-xs">All Accounts</Badge>
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
      return <span className="text-sm">{delegation.accountName}</span>
    },
  },
  {
    id: 'delegationValidity',
    header: 'Validity',
    cell: ({ row }) => {
      const delegation = row.original
      if (!delegation.validFromDate && !delegation.validToDate) {
        return <span className="text-sm text-muted-foreground">Open-ended</span>
      }
      if (delegation.validFromDate && delegation.validToDate) {
        return (
          <div className="space-y-0.5">
            <span className="block text-sm">{delegation.validFromDate}</span>
            <span className="block text-xs text-muted-foreground">to {delegation.validToDate}</span>
          </div>
        )
      }
      if (delegation.validFromDate) {
        return (
          <div className="space-y-0.5">
            <span className="block text-sm">{delegation.validFromDate}</span>
            <span className="block text-xs text-muted-foreground">start</span>
          </div>
        )
      }
      return (
        <div className="space-y-0.5">
          <span className="block text-sm">{delegation.validToDate}</span>
          <span className="block text-xs text-muted-foreground">end</span>
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

function RevokeGrantButton({ grantId, userId }: { grantId: number; userId: number }) {
  const queryClient = useQueryClient()
  const mutation = useMutation({
    mutationFn: () => api.grants.revoke(grantId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['user-grants', userId] })
      queryClient.invalidateQueries({ queryKey: ['users', userId] })
      queryClient.invalidateQueries({ queryKey: ['users'] })
    },
  })
  return (
    <Button size="sm" variant="ghost" className="text-destructive hover:text-destructive hover:bg-destructive/10" onClick={() => mutation.mutate()} disabled={mutation.isPending}>
      <Trash2 className="h-3.5 w-3.5" />
    </Button>
  )
}

function RevokePackageGrantButton({ grantId, userId }: { grantId: number; userId: number }) {
  const queryClient = useQueryClient()
  const mutation = useMutation({
    mutationFn: () => api.grants.revokePackage(grantId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['user-package-grants', userId] })
      queryClient.invalidateQueries({ queryKey: ['users', userId] })
      queryClient.invalidateQueries({ queryKey: ['users'] })
    },
  })
  return (
    <Button size="sm" variant="ghost" className="text-destructive hover:text-destructive hover:bg-destructive/10" onClick={() => mutation.mutate()} disabled={mutation.isPending}>
      <Trash2 className="h-3.5 w-3.5" />
    </Button>
  )
}

// ---------------------------------------------------------------------------
// Main component
// ---------------------------------------------------------------------------
export function UserDetail({ userId }: { userId: number }) {
  const router = useRouter()
  const queryClient = useQueryClient()
  const [grantDialogOpen, setGrantDialogOpen] = useState(false)

  const { data: user, isLoading, isError } = useQuery({
    queryKey: ['users', userId],
    queryFn: () => api.users.get(userId),
  })

  const { data: rolesData, isLoading: rolesLoading } = useQuery({
    queryKey: ['user-roles', userId],
    queryFn: () => api.users.roles(userId),
    enabled: !!user,
  })

  const { data: grantsData, isLoading: grantsLoading } = useQuery({
    queryKey: ['user-grants', userId],
    queryFn: () => api.users.grants(userId),
    enabled: !!user,
  })

  const { data: pkgGrantsData, isLoading: pkgGrantsLoading } = useQuery({
    queryKey: ['user-package-grants', userId],
    queryFn: () => api.users.packageGrants(userId),
    enabled: !!user,
  })

  const { data: delegationsData, isLoading: delegationsLoading } = useQuery({
    queryKey: ['user-delegations', userId],
    queryFn: () => api.users.delegations(userId),
    enabled: !!user,
  })

  const removeFromRole = useMutation({
    mutationFn: ({ roleId }: { roleId: number; roleCode: string; upn: string }) =>
      api.roles.removeMember(roleId, userId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['user-roles', userId] })
      queryClient.invalidateQueries({ queryKey: ['users', userId] })
      queryClient.invalidateQueries({ queryKey: ['users'] })
    },
  })

  if (isError) {
    return (
      <div className="rounded-md border border-destructive/40 bg-destructive/5 p-6 text-center">
        <p className="text-sm font-medium text-destructive">Failed to load user</p>
      </div>
    )
  }

  const hasGap = user?.gapStatus && user.gapStatus !== 'OK'

  return (
    <div className="space-y-6">
      <Button variant="ghost" size="sm" className="-ml-2 text-muted-foreground" onClick={() => router.push('/users')}>
        <ArrowLeft className="mr-1.5 h-4 w-4" />
        Users
      </Button>

      {isLoading ? (
        <div className="space-y-2">
          <div className="h-7 w-48 animate-pulse rounded bg-muted" />
          <div className="h-4 w-64 animate-pulse rounded bg-muted" />
        </div>
      ) : user ? (
        <div className="flex items-start justify-between gap-4">
          <div>
            <div className="flex items-center gap-3 flex-wrap">
              <h1 className="text-2xl font-semibold tracking-tight">{user.displayName}</h1>
              {hasGap && (
                <Badge variant="destructive" className="flex items-center gap-1">
                  <AlertTriangle className="h-3 w-3" />
                  {user.gapStatus}
                </Badge>
              )}
            </div>
            <p className="mt-0.5 text-sm text-muted-foreground">{user.upn}</p>
          </div>
          <div className="flex items-center gap-2">
            <Button size="sm" variant="outline" onClick={() => setGrantDialogOpen(true)}>
              <ShieldPlus className="mr-1.5 h-4 w-4" />
              Grant Access
            </Button>
            <StatusBadge status={user.isActive ? 'Active' : 'Inactive'} />
          </div>
        </div>
      ) : null}

      <div className="grid grid-cols-3 gap-4">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">Roles</CardTitle>
            <ShieldCheck className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold tabular-nums">{isLoading ? '—' : user?.roleCount ?? 0}</div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">Sites</CardTitle>
            <MapPin className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold tabular-nums">{isLoading ? '—' : user?.siteCount ?? 0}</div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">Accounts</CardTitle>
            <Building2 className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold tabular-nums">{isLoading ? '—' : user?.accountCount ?? 0}</div>
          </CardContent>
        </Card>
      </div>

      <Tabs defaultValue="roles">
        <TabsList>
          <TabsTrigger value="roles">
            Roles {!rolesLoading && rolesData ? `(${rolesData.totalCount})` : ''}
          </TabsTrigger>
          <TabsTrigger value="grants">
            Access Grants {!grantsLoading && grantsData ? `(${grantsData.totalCount})` : ''}
          </TabsTrigger>
          <TabsTrigger value="packages">
            Package Grants {!pkgGrantsLoading && pkgGrantsData ? `(${pkgGrantsData.totalCount})` : ''}
          </TabsTrigger>
          <TabsTrigger value="delegations">
            Delegations {!delegationsLoading && delegationsData ? `(${delegationsData.totalCount})` : ''}
          </TabsTrigger>
        </TabsList>

        <TabsContent value="roles" className="mt-4">
          {rolesData?.items.length === 0 && !rolesLoading ? (
            <div className="rounded-md border border-dashed p-6 text-center text-sm text-muted-foreground">
              Not a member of any role.
            </div>
          ) : (
            <DataTable
              columns={roleColumns(
                (roleId, roleCode, upn) => removeFromRole.mutate({ roleId, roleCode, upn }),
                user?.upn ?? '',
              )}
              data={rolesData?.items ?? []}
              isLoading={rolesLoading}
            />
          )}
        </TabsContent>

        <TabsContent value="grants" className="mt-4">
          {grantsData?.items.length === 0 && !grantsLoading ? (
            <div className="rounded-md border border-dashed p-6 text-center text-sm text-muted-foreground">
              No access grants. Use "Grant Access" to add one.
            </div>
          ) : (
            <DataTable columns={grantColumns} data={grantsData?.items ?? []} isLoading={grantsLoading} />
          )}
        </TabsContent>

        <TabsContent value="packages" className="mt-4">
          {pkgGrantsData?.items.length === 0 && !pkgGrantsLoading ? (
            <div className="rounded-md border border-dashed p-6 text-center text-sm text-muted-foreground">
              No package grants. Use "Grant Access" to add one.
            </div>
          ) : (
            <DataTable columns={packageGrantColumns} data={pkgGrantsData?.items ?? []} isLoading={pkgGrantsLoading} />
          )}
        </TabsContent>

        <TabsContent value="delegations" className="mt-4">
          {delegationsData?.items.length === 0 && !delegationsLoading ? (
            <div className="rounded-md border border-dashed p-6 text-center text-sm text-muted-foreground">
              No delegated access found for this user.
            </div>
          ) : (
            <DataTable columns={delegationColumns} data={delegationsData?.items ?? []} isLoading={delegationsLoading} />
          )}
        </TabsContent>
      </Tabs>

      {user && (
        <GrantAccessDialog
          open={grantDialogOpen}
          onOpenChange={setGrantDialogOpen}
          principalType="USER"
          principalIdentifier={user.upn}
          invalidateKeys={[
            ['users', userId],
            ['user-grants', userId],
            ['user-package-grants', userId],
          ]}
        />
      )}
    </div>
  )
}
