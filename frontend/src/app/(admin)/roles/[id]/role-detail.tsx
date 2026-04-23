'use client'

import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useRouter } from 'next/navigation'
import type { ColumnDef } from '@tanstack/react-table'
import { ArrowLeft, Users, ShieldCheck, Package, Trash2, ShieldPlus } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter,
} from '@/components/ui/dialog'
import { Form, FormControl, FormField, FormItem, FormLabel, FormMessage } from '@/components/ui/form'
import { DataTable } from '@/components/shared/data-table'
import { StatusBadge } from '@/components/shared/status-badge'
import { GrantAccessDialog } from '@/components/shared/grant-access-dialog'
import { UserUpnTypeahead } from '@/components/shared/user-upn-typeahead'
import { ErrorState } from '@/components/shared/error-state'
import { api } from '@/lib/api'
import type { Grant, PackageGrant, RoleMember } from '@/types/api'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'

// ---------------------------------------------------------------------------
// Add Member Dialog
// ---------------------------------------------------------------------------
function AddMemberDialog({
  roleId,
  memberUpns,
  onSuccess,
}: {
  roleId: number
  memberUpns: string[]
  onSuccess: () => void
}) {
  const [open, setOpen] = useState(false)
  const form = useForm<{ upn: string }>({
    resolver: zodResolver(z.object({ upn: z.string().email('Enter a valid UPN / email') })),
    defaultValues: { upn: '' },
  })

  const mutation = useMutation({
    mutationFn: ({ upn }: { upn: string }) => api.roles.addMember(roleId, upn),
    onSuccess: () => { onSuccess(); setOpen(false); form.reset() },
  })

  return (
    <>
      <Button size="sm" variant="outline" onClick={() => setOpen(true)}>
        <Users className="mr-1.5 h-4 w-4" />
        Add Member
      </Button>
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader><DialogTitle>Add Member</DialogTitle></DialogHeader>
          <Form {...form}>
            <form onSubmit={form.handleSubmit((v) => mutation.mutate(v))} className="space-y-4">
              <FormField
                control={form.control}
                name="upn"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>User UPN</FormLabel>
                    <FormControl>
                      <UserUpnTypeahead
                        value={field.value}
                        onChange={field.onChange}
                        open={open}
                        disabled={mutation.isPending}
                        excludeUpns={memberUpns}
                        placeholder="Type a name or email"
                      />
                    </FormControl>
                    <p className="text-xs text-muted-foreground">
                      Start typing to search users by name or email.
                    </p>
                    <FormMessage />
                  </FormItem>
                )}
              />
              {mutation.isError && (
                <p className="text-sm text-destructive">
                  {mutation.error instanceof Error ? mutation.error.message : 'Failed to add member.'}
                </p>
              )}
              <DialogFooter>
                <Button type="button" variant="outline" onClick={() => setOpen(false)} disabled={mutation.isPending}>Cancel</Button>
                <Button type="submit" disabled={mutation.isPending}>{mutation.isPending ? 'Adding…' : 'Add'}</Button>
              </DialogFooter>
            </form>
          </Form>
        </DialogContent>
      </Dialog>
    </>
  )
}

// ---------------------------------------------------------------------------
// Column definitions
// ---------------------------------------------------------------------------
function memberColumns(onRemove: (userId: number) => void): ColumnDef<RoleMember, unknown>[] {
  return [
    {
      accessorKey: 'displayName',
      header: 'User',
      cell: ({ row }) => (
        <div>
          <p className="font-medium leading-tight">{row.original.displayName}</p>
          <p className="text-xs text-muted-foreground">{row.original.upn}</p>
        </div>
      ),
    },
    {
      accessorKey: 'addedOnUtc',
      header: 'Added',
      cell: ({ row }) => (
        <span className="text-sm text-muted-foreground">
          {new Date(row.original.addedOnUtc).toLocaleDateString()}
        </span>
      ),
      meta: { className: 'w-[130px]' },
    },
    {
      id: 'remove',
      header: '',
      cell: ({ row }) => (
        <Button
          size="sm"
          variant="ghost"
          className="text-destructive hover:text-destructive hover:bg-destructive/10"
          onClick={() => onRemove(row.original.memberPrincipalId)}
        >
          <Trash2 className="h-3.5 w-3.5" />
        </Button>
      ),
      meta: { className: 'w-[50px]' },
    },
  ]
}

function grantColumns(roleId: number): ColumnDef<Grant, unknown>[] {
  return [
    {
      accessorKey: 'accessType',
      header: 'Scope',
      cell: ({ row }) => {
        const { accessType, scopeType, accountName, orgUnitCode } = row.original
        if (accessType === 'ALL') return <Badge variant="outline" className="text-xs">All Accounts</Badge>
        if (scopeType === 'ORGUNIT')
          return (
            <div className="flex flex-col gap-0.5">
              <span className="text-sm font-medium">{accountName}</span>
              <span className="font-mono text-xs text-muted-foreground">{orgUnitCode}</span>
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
      cell: ({ row }) => (
        <RevokeGrantButton grantId={row.original.principalAccessGrantId} roleId={roleId} />
      ),
      meta: { className: 'w-[50px]' },
    },
  ]
}

function packageGrantColumns(roleId: number): ColumnDef<PackageGrant, unknown>[] {
  return [
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
      cell: ({ row }) => (
        <RevokePackageGrantButton grantId={row.original.principalPackageGrantId} roleId={roleId} />
      ),
      meta: { className: 'w-[50px]' },
    },
  ]
}

function RevokeGrantButton({ grantId, roleId }: { grantId: number; roleId: number }) {
  const queryClient = useQueryClient()
  const mutation = useMutation({
    mutationFn: () => api.grants.revoke(grantId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['role-grants', roleId] })
      queryClient.invalidateQueries({ queryKey: ['roles', roleId] })
      queryClient.invalidateQueries({ queryKey: ['roles'] })
    },
  })
  return (
    <Button size="sm" variant="ghost" className="text-destructive hover:text-destructive hover:bg-destructive/10" onClick={() => mutation.mutate()} disabled={mutation.isPending}>
      <Trash2 className="h-3.5 w-3.5" />
    </Button>
  )
}

function RevokePackageGrantButton({ grantId, roleId }: { grantId: number; roleId: number }) {
  const queryClient = useQueryClient()
  const mutation = useMutation({
    mutationFn: () => api.grants.revokePackage(grantId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['role-package-grants', roleId] })
      queryClient.invalidateQueries({ queryKey: ['roles', roleId] })
      queryClient.invalidateQueries({ queryKey: ['roles'] })
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
export function RoleDetail({ roleId }: { roleId: number }) {
  const router = useRouter()
  const queryClient = useQueryClient()
  const [grantDialogOpen, setGrantDialogOpen] = useState(false)

  const { data: role, isLoading: roleLoading, isError } = useQuery({
    queryKey: ['roles', roleId],
    queryFn: () => api.roles.get(roleId),
  })

  const { data: membersData, isLoading: membersLoading } = useQuery({
    queryKey: ['roles', roleId, 'members'],
    queryFn: () => api.roles.members(roleId),
    enabled: !!role,
  })

  const { data: grantsData, isLoading: grantsLoading } = useQuery({
    queryKey: ['role-grants', roleId],
    queryFn: () => api.roles.grants(roleId),
    enabled: !!role,
  })

  const { data: pkgGrantsData, isLoading: pkgGrantsLoading } = useQuery({
    queryKey: ['role-package-grants', roleId],
    queryFn: () => api.roles.packageGrants(roleId),
    enabled: !!role,
  })

  const removeMember = useMutation({
    mutationFn: (userId: number) => api.roles.removeMember(roleId, userId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['roles', roleId, 'members'] })
      queryClient.invalidateQueries({ queryKey: ['roles', roleId] })
      queryClient.invalidateQueries({ queryKey: ['roles'] })
      queryClient.invalidateQueries({ queryKey: ['users'] })
      queryClient.invalidateQueries({ queryKey: ['accounts'] })
      queryClient.invalidateQueries({ queryKey: ['coverage'] })
    },
  })

  if (isError) {
    return (
      <ErrorState title="Failed to load role" />
    )
  }

  return (
    <div className="space-y-6">
      <Button variant="ghost" size="sm" className="-ml-2 text-muted-foreground" onClick={() => router.push('/roles')}>
        <ArrowLeft className="mr-1.5 h-4 w-4" />
        Roles
      </Button>

      {roleLoading ? (
        <div className="space-y-2">
          <div className="h-7 w-48 animate-pulse rounded bg-muted" />
          <div className="h-4 w-64 animate-pulse rounded bg-muted" />
        </div>
      ) : role ? (
        <div className="flex items-start justify-between">
          <div>
            <div className="flex items-center gap-3 flex-wrap">
              <h1 className="text-2xl font-semibold tracking-tight">{role.roleName}</h1>
              <span className="font-mono text-sm text-muted-foreground bg-muted px-2 py-0.5 rounded">{role.roleCode}</span>
            </div>
            {role.description && <p className="mt-1 text-sm text-muted-foreground">{role.description}</p>}
          </div>
          <div className="flex items-center gap-2">
            <Button size="sm" variant="outline" onClick={() => setGrantDialogOpen(true)}>
              <ShieldPlus className="mr-1.5 h-4 w-4" />
              Grant Access
            </Button>
            <StatusBadge status={role.isActive ? 'Active' : 'Inactive'} />
          </div>
        </div>
      ) : null}

      <div className="grid grid-cols-3 gap-4">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">Members</CardTitle>
            <Users className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold tabular-nums">{roleLoading ? '—' : role?.memberCount ?? 0}</div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">Access Grants</CardTitle>
            <ShieldCheck className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold tabular-nums">{roleLoading ? '—' : role?.accessGrantCount ?? 0}</div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">Package Grants</CardTitle>
            <Package className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold tabular-nums">{roleLoading ? '—' : role?.packageGrantCount ?? 0}</div>
          </CardContent>
        </Card>
      </div>

      <Tabs defaultValue="members">
        <div className="flex items-center justify-between">
          <TabsList>
            <TabsTrigger value="members">
              Members {!membersLoading && membersData ? `(${membersData.totalCount})` : ''}
            </TabsTrigger>
            <TabsTrigger value="grants">
              Access Grants {!grantsLoading && grantsData ? `(${grantsData.totalCount})` : ''}
            </TabsTrigger>
            <TabsTrigger value="packages">
              Package Grants {!pkgGrantsLoading && pkgGrantsData ? `(${pkgGrantsData.totalCount})` : ''}
            </TabsTrigger>
          </TabsList>
        </div>

        <TabsContent value="members" className="mt-4">
          <div className="flex justify-end mb-3">
            <AddMemberDialog
              roleId={roleId}
              memberUpns={(membersData?.items ?? []).map((member) => member.upn)}
              onSuccess={() => {
                queryClient.invalidateQueries({ queryKey: ['roles', roleId, 'members'] })
                queryClient.invalidateQueries({ queryKey: ['roles', roleId] })
                queryClient.invalidateQueries({ queryKey: ['roles'] })
                queryClient.invalidateQueries({ queryKey: ['users'] })
                queryClient.invalidateQueries({ queryKey: ['accounts'] })
                queryClient.invalidateQueries({ queryKey: ['coverage'] })
              }}
            />
          </div>
          <DataTable
            columns={memberColumns((userId) => removeMember.mutate(userId))}
            data={membersData?.items ?? []}
            isLoading={membersLoading}
          />
        </TabsContent>

        <TabsContent value="grants" className="mt-4">
          <DataTable columns={grantColumns(roleId)} data={grantsData?.items ?? []} isLoading={grantsLoading} />
        </TabsContent>

        <TabsContent value="packages" className="mt-4">
          <DataTable columns={packageGrantColumns(roleId)} data={pkgGrantsData?.items ?? []} isLoading={pkgGrantsLoading} />
        </TabsContent>
      </Tabs>

      {role && (
        <GrantAccessDialog
          open={grantDialogOpen}
          onOpenChange={setGrantDialogOpen}
          principalType="ROLE"
          principalIdentifier={role.roleCode}
          invalidateKeys={[
            ['roles'],
            ['roles', roleId],
            ['role-grants', roleId],
            ['role-package-grants', roleId],
          ]}
        />
      )}
    </div>
  )
}
