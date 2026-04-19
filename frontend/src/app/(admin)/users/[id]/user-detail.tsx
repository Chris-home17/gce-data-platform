'use client'

import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useRouter } from 'next/navigation'
import type { ColumnDef } from '@tanstack/react-table'
import {
  AlertTriangle,
  ArrowLeft,
  Building2,
  FileText,
  Globe,
  MapPin,
  Shield,
  ShieldCheck,
  ShieldPlus,
  Trash2,
  UserPlus,
} from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { DataTable } from '@/components/shared/data-table'
import { StatusBadge } from '@/components/shared/status-badge'
import { GrantAccessDialog } from '@/components/shared/grant-access-dialog'
import { api } from '@/lib/api'
import { usePermissions } from '@/hooks/usePermissions'
import { PERMISSIONS } from '@/types/api'
import type { Delegation, EffectiveAccessEntry, EffectiveSite, EffectiveReport, Grant, PackageGrant, Role } from '@/types/api'

// ---------------------------------------------------------------------------
// Column definitions
// ---------------------------------------------------------------------------

function roleColumns(
  onRemove: (roleId: number) => void,
  canRemove: boolean
): ColumnDef<Role, unknown>[] {
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
    ...(canRemove
      ? [{
          id: 'remove',
          header: '',
          cell: ({ row }: { row: { original: Role } }) => (
            <Button
              size="sm"
              variant="ghost"
              className="text-destructive hover:text-destructive hover:bg-destructive/10"
              onClick={() => onRemove(row.original.roleId)}
            >
              <Trash2 className="h-3.5 w-3.5" />
            </Button>
          ),
          meta: { className: 'w-[50px]' },
        } as ColumnDef<Role, unknown>]
      : []),
  ]
}

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
    id: 'source',
    header: 'Via',
    cell: ({ row }) => {
      if (row.original.grantSource === 'DIRECT') {
        return <Badge variant="secondary" className="text-xs">Direct</Badge>
      }
      return (
        <div className="flex items-center gap-1.5">
          <Badge variant="outline" className="bg-blue-50 text-xs text-blue-700 border-blue-300">Role</Badge>
          <span className="text-sm font-medium">{row.original.sourceName}</span>
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
]

const effectiveAccessColumns: ColumnDef<EffectiveAccessEntry, unknown>[] = [
  {
    id: 'account',
    header: 'Account',
    cell: ({ row }) => {
      const { accessType, accountCode, accountName } = row.original
      if (accessType === 'ALL')
        return <Badge variant="outline" className="text-xs">All Accounts</Badge>
      return (
        <div>
          <span className="text-sm font-medium">{accountName}</span>
          <span className="ml-2 font-mono text-xs text-muted-foreground">{accountCode}</span>
        </div>
      )
    },
  },
  {
    id: 'scope',
    header: 'Scope',
    cell: ({ row }) => {
      const { scopeType, scopeOrgUnitCode, scopeOrgUnitName, scopeOrgUnitType } = row.original
      if (scopeType === 'NONE')
        return <span className="text-sm text-muted-foreground">All sites</span>
      return (
        <div>
          <span className="text-sm">{scopeOrgUnitName}</span>
          <span className="ml-2 font-mono text-xs text-muted-foreground">{scopeOrgUnitType} / {scopeOrgUnitCode}</span>
        </div>
      )
    },
  },
  {
    id: 'source',
    header: 'Via',
    cell: ({ row }) => {
      const { grantSource, sourceCode, sourceName } = row.original
      if (grantSource === 'DIRECT')
        return <Badge variant="secondary" className="text-xs">Direct</Badge>
      if (grantSource === 'ROLE')
        return (
          <div className="flex items-center gap-1.5">
            <Badge variant="outline" className="text-xs border-blue-300 text-blue-700 bg-blue-50">Role</Badge>
            <span className="text-sm font-medium">{sourceName}</span>
            <span className="font-mono text-xs text-muted-foreground">{sourceCode}</span>
          </div>
        )
      return (
        <div className="flex items-center gap-1.5">
          <Badge variant="outline" className="text-xs border-amber-300 text-amber-700 bg-amber-50">Delegated</Badge>
          <span className="text-sm">{sourceName ?? sourceCode}</span>
        </div>
      )
    },
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
      if (delegation.accessType === 'ALL')
        return <Badge variant="outline" className="text-xs">All Accounts</Badge>
      if (delegation.scopeType === 'ORGUNIT')
        return (
          <div>
            <span className="block text-sm">{delegation.accountName}</span>
            <span className="block font-mono text-xs text-muted-foreground">
              {delegation.orgUnitType} / {delegation.orgUnitCode}
            </span>
          </div>
        )
      return <span className="text-sm">{delegation.accountName}</span>
    },
  },
  {
    id: 'validity',
    header: 'Validity',
    cell: ({ row }) => {
      const { validFromDate, validToDate } = row.original
      if (!validFromDate && !validToDate)
        return <span className="text-sm text-muted-foreground">Open-ended</span>
      return (
        <div>
          {validFromDate && <p className="text-sm">{validFromDate}</p>}
          {validToDate && <p className="text-xs text-muted-foreground">to {validToDate}</p>}
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

const effectiveSiteColumns: ColumnDef<EffectiveSite, unknown>[] = [
  {
    id: 'account',
    header: 'Account',
    cell: ({ row }) => (
      <div>
        <span className="text-sm font-medium">{row.original.accountName}</span>
        <span className="ml-2 font-mono text-xs text-muted-foreground">{row.original.accountCode}</span>
      </div>
    ),
  },
  {
    id: 'site',
    header: 'Site',
    cell: ({ row }) => (
      <div>
        <span className="text-sm font-medium">{row.original.siteName}</span>
        <span className="ml-2 font-mono text-xs text-muted-foreground">{row.original.siteCode}</span>
      </div>
    ),
  },
  {
    accessorKey: 'countryCode',
    header: 'Country',
    cell: ({ row }) => (
      <span className="font-mono text-sm text-muted-foreground">{row.original.countryCode ?? '—'}</span>
    ),
    meta: { className: 'w-[90px]' },
  },
  {
    accessorKey: 'sourceOrgUnitName',
    header: 'Org Unit',
    cell: ({ row }) => (
      <span className="text-sm text-muted-foreground">{row.original.sourceOrgUnitName ?? '—'}</span>
    ),
  },
]

const effectiveReportColumns: ColumnDef<EffectiveReport, unknown>[] = [
  {
    id: 'package',
    header: 'Package',
    cell: ({ row }) => (
      <div>
        <span className="text-sm font-medium">{row.original.packageName}</span>
        <span className="ml-2 font-mono text-xs text-muted-foreground">{row.original.packageCode}</span>
      </div>
    ),
  },
  {
    id: 'report',
    header: 'Report',
    cell: ({ row }) => (
      <div>
        <span className="text-sm font-medium">{row.original.reportName}</span>
        <span className="ml-2 font-mono text-xs text-muted-foreground">{row.original.reportCode}</span>
      </div>
    ),
  },
]

// ---------------------------------------------------------------------------
// Revoke buttons
// ---------------------------------------------------------------------------

function RevokeGrantButton({ grantId, userId }: { grantId: number; userId: number }) {
  const { can } = usePermissions()
  const queryClient = useQueryClient()
  const mutation = useMutation({
    mutationFn: () => api.grants.revoke(grantId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['user-grants', userId] })
      queryClient.invalidateQueries({ queryKey: ['user-effective-access', userId] })
      queryClient.invalidateQueries({ queryKey: ['users', userId] })
    },
  })
  if (!can(PERMISSIONS.GRANTS_MANAGE)) return null
  return (
    <Button
      size="sm"
      variant="ghost"
      className="text-destructive hover:text-destructive hover:bg-destructive/10"
      onClick={() => mutation.mutate()}
      disabled={mutation.isPending}
    >
      <Trash2 className="h-3.5 w-3.5" />
    </Button>
  )
}

const directGrantColumns: ColumnDef<Grant, unknown>[] = [
  {
    id: 'scope',
    header: 'Account',
    cell: ({ row }) => {
      const { accessType, accountName, accountCode } = row.original
      if (accessType === 'ALL') return <Badge variant="outline" className="text-xs">All Accounts</Badge>
      return (
        <div>
          <span className="text-sm font-medium">{accountName}</span>
          <span className="ml-2 font-mono text-xs text-muted-foreground">{accountCode}</span>
        </div>
      )
    },
  },
  {
    id: 'orgUnit',
    header: 'Org Unit',
    cell: ({ row }) => {
      if (row.original.scopeType !== 'ORGUNIT')
        return <span className="text-muted-foreground/40">—</span>
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
    cell: ({ row }) => (
      <RevokeGrantButton
        grantId={row.original.principalAccessGrantId}
        userId={row.original.principalId}
      />
    ),
    meta: { className: 'w-[50px]' },
  },
]

// ---------------------------------------------------------------------------
// Main component
// ---------------------------------------------------------------------------

export function UserDetail({ userId }: { userId: number }) {
  const router = useRouter()
  const queryClient = useQueryClient()
  const { can } = usePermissions()
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

  const { data: effectiveData, isLoading: effectiveLoading } = useQuery({
    queryKey: ['user-effective-access', userId],
    queryFn: () => api.users.effectiveAccess(userId),
    enabled: !!user,
  })

  const { data: resolvedData, isLoading: resolvedLoading } = useQuery({
    queryKey: ['user-resolved-access', userId],
    queryFn: () => api.users.resolvedAccess(userId),
    enabled: !!user,
  })

  const removeFromRole = useMutation({
    mutationFn: (roleId: number) => api.roles.removeMember(roleId, userId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['user-roles', userId] })
      queryClient.invalidateQueries({ queryKey: ['users', userId] })
    },
  })

  if (isError) {
    return (
      <div className="rounded-xl border border-destructive/40 bg-destructive/5 p-6 text-center">
        <p className="text-sm font-medium text-destructive">Failed to load user</p>
      </div>
    )
  }

  const hasGap = user?.gapStatus && user.gapStatus !== 'OK'

  return (
    <div className="space-y-6">
      <Button
        variant="ghost"
        size="sm"
        className="-ml-2 text-muted-foreground"
        onClick={() => router.push('/users')}
      >
        <ArrowLeft className="mr-1.5 h-4 w-4" />
        Users
      </Button>

      {/* User header */}
      {isLoading ? (
        <div className="space-y-2">
          <div className="h-7 w-48 animate-pulse rounded bg-muted" />
          <div className="h-4 w-64 animate-pulse rounded bg-muted" />
        </div>
      ) : user ? (
        <div className="space-y-3">
          <div className="flex items-start justify-between gap-4 flex-wrap">
            <div>
              <div className="flex items-center gap-3 flex-wrap">
                <h1 className="text-2xl font-bold tracking-tight">{user.displayName}</h1>
                <StatusBadge status={user.isActive ? 'Active' : 'Inactive'} />
              </div>
              <p className="mt-0.5 text-sm text-muted-foreground font-mono">{user.upn}</p>
            </div>
            <div className="flex items-center gap-2">
              {can(PERMISSIONS.GRANTS_MANAGE) && (
                <Button size="sm" variant="outline" onClick={() => setGrantDialogOpen(true)}>
                  <ShieldPlus className="mr-1.5 h-4 w-4" />
                  Grant Access
                </Button>
              )}
            </div>
          </div>

          {/* Coverage status — prominent banner */}
          {hasGap && (
            <div className="flex items-center gap-3 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 dark:bg-amber-950/20 dark:border-amber-800">
              <AlertTriangle className="h-5 w-5 shrink-0 text-amber-600" />
              <div>
                <p className="text-sm font-medium text-amber-800 dark:text-amber-400">
                  Coverage gap detected: <span className="font-semibold">{user.gapStatus}</span>
                </p>
                <p className="text-xs text-amber-700/80 dark:text-amber-500">
                  This user has sites without package access, or packages without site access.
                </p>
              </div>
            </div>
          )}
        </div>
      ) : null}

      {/* Stat cards */}
      <div className="grid grid-cols-3 gap-4">
        <Card className="rounded-xl">
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">Roles</CardTitle>
            <ShieldCheck className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold tabular-nums">{isLoading ? '—' : user?.roleCount ?? 0}</div>
          </CardContent>
        </Card>
        <Card className="rounded-xl">
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">Sites</CardTitle>
            <MapPin className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold tabular-nums">{isLoading ? '—' : user?.siteCount ?? 0}</div>
          </CardContent>
        </Card>
        <Card className="rounded-xl">
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">Accounts</CardTitle>
            <Building2 className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold tabular-nums">{isLoading ? '—' : user?.accountCount ?? 0}</div>
          </CardContent>
        </Card>
      </div>

      {/* Tabs — simplified to 3 */}
      <Tabs defaultValue="overview">
        <TabsList>
          <TabsTrigger value="overview">
            Overview
          </TabsTrigger>
          <TabsTrigger value="access">
            Access
            {!effectiveLoading && effectiveData ? ` (${effectiveData.totalCount})` : ''}
          </TabsTrigger>
          <TabsTrigger value="delegations">
            Delegations
            {!delegationsLoading && delegationsData ? ` (${delegationsData.totalCount})` : ''}
          </TabsTrigger>
          <TabsTrigger value="effective-access">
            Effective Access
            {!resolvedLoading && resolvedData
              ? ` (${resolvedData.sites.length + resolvedData.reports.length})`
              : ''}
          </TabsTrigger>
        </TabsList>

        {/* Overview: roles + packages combined */}
        <TabsContent value="overview" className="mt-5 space-y-6">
          {/* Roles section */}
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <h3 className="text-sm font-semibold flex items-center gap-2">
                <Shield className="h-4 w-4 text-muted-foreground" />
                Roles
                {!rolesLoading && rolesData && (
                  <Badge variant="secondary" className="text-xs font-normal">
                    {rolesData.totalCount}
                  </Badge>
                )}
              </h3>
            </div>
            {rolesData?.items.length === 0 && !rolesLoading ? (
              <div className="rounded-xl border border-dashed p-4 text-center text-sm text-muted-foreground">
                Not a member of any role.
              </div>
            ) : (
              <DataTable
                columns={roleColumns(
                  (roleId) => removeFromRole.mutate(roleId),
                  can(PERMISSIONS.GRANTS_MANAGE)
                )}
                data={rolesData?.items ?? []}
                isLoading={rolesLoading}
              />
            )}
          </div>

          {/* Direct grants section */}
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <h3 className="text-sm font-semibold flex items-center gap-2">
                <ShieldPlus className="h-4 w-4 text-muted-foreground" />
                Direct Access Grants
                {!grantsLoading && grantsData && (
                  <Badge variant="secondary" className="text-xs font-normal">
                    {grantsData.totalCount}
                  </Badge>
                )}
              </h3>
            </div>
            {grantsData?.items.length === 0 && !grantsLoading ? (
              <div className="rounded-xl border border-dashed p-4 text-center text-sm text-muted-foreground">
                No direct access grants.
              </div>
            ) : (
              <DataTable
                columns={directGrantColumns}
                data={grantsData?.items ?? []}
                isLoading={grantsLoading}
              />
            )}
          </div>

          {/* Package grants section */}
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <h3 className="text-sm font-semibold flex items-center gap-2">
                <UserPlus className="h-4 w-4 text-muted-foreground" />
                Package Access
                {!pkgGrantsLoading && pkgGrantsData && (
                  <Badge variant="secondary" className="text-xs font-normal">
                    {pkgGrantsData.totalCount}
                  </Badge>
                )}
              </h3>
            </div>
            {pkgGrantsData?.items.length === 0 && !pkgGrantsLoading ? (
              <div className="rounded-xl border border-dashed p-4 text-center text-sm text-muted-foreground">
                No package grants. Use &quot;Grant Access&quot; to add one.
              </div>
            ) : (
              <DataTable
                columns={packageGrantColumns}
                data={pkgGrantsData?.items ?? []}
                isLoading={pkgGrantsLoading}
              />
            )}
          </div>
        </TabsContent>

        {/* Access: effective access = all sources combined */}
        <TabsContent value="access" className="mt-5">
          <div className="mb-4">
            <p className="text-sm text-muted-foreground">
              All access this user has — via direct grants, role memberships, and active delegations.
            </p>
          </div>
          {effectiveData?.items.length === 0 && !effectiveLoading ? (
            <div className="rounded-xl border border-dashed p-6 text-center text-sm text-muted-foreground">
              No effective access found. Assign a role or add a direct grant.
            </div>
          ) : (
            <DataTable
              columns={effectiveAccessColumns}
              data={effectiveData?.items ?? []}
              isLoading={effectiveLoading}
            />
          )}
        </TabsContent>

        {/* Delegations */}
        <TabsContent value="delegations" className="mt-5">
          {delegationsData?.items.length === 0 && !delegationsLoading ? (
            <div className="rounded-xl border border-dashed p-6 text-center text-sm text-muted-foreground">
              No delegated access for this user.
            </div>
          ) : (
            <DataTable
              columns={delegationColumns}
              data={delegationsData?.items ?? []}
              isLoading={delegationsLoading}
            />
          )}
        </TabsContent>

        {/* Effective Access: resolved sites + reports from App.GetUserEffectiveAccess */}
        <TabsContent value="effective-access" className="mt-5 space-y-6">
          <p className="text-sm text-muted-foreground">
            The actual sites and reports this user can access, resolved from all grants, roles, and delegations.
          </p>

          {/* Sites */}
          <div className="space-y-3">
            <h3 className="text-sm font-semibold flex items-center gap-2">
              <Globe className="h-4 w-4 text-muted-foreground" />
              Sites
              {!resolvedLoading && resolvedData && (
                <Badge variant="secondary" className="text-xs font-normal">
                  {resolvedData.sites.length}
                </Badge>
              )}
            </h3>
            {!resolvedLoading && resolvedData?.sites.length === 0 ? (
              <div className="rounded-xl border border-dashed p-4 text-center text-sm text-muted-foreground">
                No site access.
              </div>
            ) : (
              <DataTable
                columns={effectiveSiteColumns}
                data={resolvedData?.sites ?? []}
                isLoading={resolvedLoading}
              />
            )}
          </div>

          {/* Reports */}
          <div className="space-y-3">
            <h3 className="text-sm font-semibold flex items-center gap-2">
              <FileText className="h-4 w-4 text-muted-foreground" />
              Reports
              {!resolvedLoading && resolvedData && (
                <Badge variant="secondary" className="text-xs font-normal">
                  {resolvedData.reports.length}
                </Badge>
              )}
            </h3>
            {!resolvedLoading && resolvedData?.reports.length === 0 ? (
              <div className="rounded-xl border border-dashed p-4 text-center text-sm text-muted-foreground">
                No report access.
              </div>
            ) : (
              <DataTable
                columns={effectiveReportColumns}
                data={resolvedData?.reports ?? []}
                isLoading={resolvedLoading}
              />
            )}
          </div>
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
            ['user-effective-access', userId],
          ]}
        />
      )}
    </div>
  )
}
