'use client'

import { useState, useEffect, useMemo } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useRouter } from 'next/navigation'
import type { ColumnDef } from '@tanstack/react-table'
import { ArrowLeft, Users, ShieldCheck, Trash2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog'
import { Form, FormControl, FormField, FormItem, FormLabel, FormMessage } from '@/components/ui/form'
import { Skeleton } from '@/components/ui/skeleton'
import { DataTable } from '@/components/shared/data-table'
import { StatusBadge } from '@/components/shared/status-badge'
import { PermissionGate } from '@/components/shared/permission-gate'
import { UserUpnTypeahead } from '@/components/shared/user-upn-typeahead'
import { api } from '@/lib/api'
import type { PlatformPermission, PlatformRoleMember } from '@/types/api'
import { PERMISSIONS } from '@/types/api'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { toast } from 'sonner'

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
    resolver: zodResolver(z.object({ upn: z.string().min(1, 'UPN is required') })),
    defaultValues: { upn: '' },
  })

  const mutation = useMutation({
    mutationFn: ({ upn }: { upn: string }) =>
      api.platformRoles.addMember(roleId, { userUpn: upn }),
    onSuccess: () => {
      onSuccess()
      setOpen(false)
      form.reset()
      toast.success('Member added')
    },
    onError: (err) => {
      toast.error(err instanceof Error ? err.message : 'Failed to add member.')
    },
  })

  return (
    <>
      <Button size="sm" variant="outline" onClick={() => setOpen(true)}>
        <Users className="mr-1.5 h-4 w-4" />
        Add Member
      </Button>
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader>
            <DialogTitle>Add Member</DialogTitle>
          </DialogHeader>
          <Form {...form}>
            <form
              onSubmit={form.handleSubmit((v) => mutation.mutate(v))}
              className="space-y-4"
            >
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
              <DialogFooter>
                <Button
                  type="button"
                  variant="outline"
                  onClick={() => setOpen(false)}
                  disabled={mutation.isPending}
                >
                  Cancel
                </Button>
                <Button type="submit" disabled={mutation.isPending}>
                  {mutation.isPending ? 'Adding…' : 'Add'}
                </Button>
              </DialogFooter>
            </form>
          </Form>
        </DialogContent>
      </Dialog>
    </>
  )
}

// ---------------------------------------------------------------------------
// Permissions Tab
// ---------------------------------------------------------------------------
function PermissionsTab({
  roleId,
  currentPermissions,
  allPermissions,
  isLoading,
}: {
  roleId: number
  currentPermissions: PlatformPermission[]
  allPermissions: PlatformPermission[]
  isLoading: boolean
}) {
  const queryClient = useQueryClient()
  const [selected, setSelected] = useState<Set<string>>(new Set())

  // Initialise from current permissions
  useEffect(() => {
    setSelected(new Set(currentPermissions.map((p) => p.permissionCode)))
  }, [currentPermissions])

  const mutation = useMutation({
    mutationFn: () =>
      api.platformRoles.setPermissions(roleId, { permissionCodes: Array.from(selected) }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['platform-roles', roleId] })
      queryClient.invalidateQueries({ queryKey: ['platform-roles'] })
      toast.success('Permissions saved')
    },
    onError: (err) => {
      toast.error(err instanceof Error ? err.message : 'Failed to save permissions.')
    },
  })

  // Group by category
  const grouped = useMemo(() => {
    const map = new Map<string, PlatformPermission[]>()
    for (const p of allPermissions) {
      if (!map.has(p.category)) map.set(p.category, [])
      map.get(p.category)!.push(p)
    }
    return map
  }, [allPermissions])

  if (isLoading) {
    return (
      <div className="space-y-4 pt-4">
        {[1, 2, 3].map((i) => (
          <Skeleton key={i} className="h-10 w-full" />
        ))}
      </div>
    )
  }

  const toggle = (code: string) => {
    setSelected((prev) => {
      const next = new Set(prev)
      if (next.has(code)) next.delete(code)
      else next.add(code)
      return next
    })
  }

  const isDirty =
    selected.size !== currentPermissions.length ||
    Array.from(selected).some((c) => !currentPermissions.find((p) => p.permissionCode === c))

  return (
    <div className="space-y-6 pt-4">
      {Array.from(grouped.entries()).map(([category, perms]) => (
        <div key={category}>
          <p className="mb-2 text-xs font-semibold uppercase tracking-widest text-muted-foreground/70">
            {category}
          </p>
          <Card>
            <CardContent className="divide-y p-0">
              {perms.map((perm) => (
                <label
                  key={perm.permissionCode}
                  className="flex cursor-pointer items-start gap-3 px-4 py-3 hover:bg-muted/50"
                >
                  <input
                    type="checkbox"
                    checked={selected.has(perm.permissionCode)}
                    onChange={() => toggle(perm.permissionCode)}
                    className="mt-0.5 h-4 w-4 shrink-0 cursor-pointer rounded border border-input accent-primary"
                  />
                  <div className="min-w-0 flex-1">
                    <p className="text-sm font-medium leading-tight">{perm.displayName}</p>
                    {perm.description && (
                      <p className="mt-0.5 text-xs text-muted-foreground">{perm.description}</p>
                    )}
                    <p className="mt-0.5 font-mono text-[10px] text-muted-foreground/60">
                      {perm.permissionCode}
                    </p>
                  </div>
                </label>
              ))}
            </CardContent>
          </Card>
        </div>
      ))}

      <PermissionGate permission={PERMISSIONS.PLATFORM_ROLES_MANAGE}>
        <Button
          onClick={() => mutation.mutate()}
          disabled={mutation.isPending || !isDirty}
          size="sm"
        >
          {mutation.isPending ? 'Saving…' : 'Save Changes'}
        </Button>
      </PermissionGate>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Members Tab
// ---------------------------------------------------------------------------
function MembersTab({
  roleId,
  members,
  isLoading,
}: {
  roleId: number
  members: PlatformRoleMember[]
  isLoading: boolean
}) {
  const queryClient = useQueryClient()

  const removeMutation = useMutation({
    mutationFn: (userId: number) => api.platformRoles.removeMember(roleId, userId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['platform-roles', roleId] })
      queryClient.invalidateQueries({ queryKey: ['platform-roles'] })
      toast.success('Member removed')
    },
    onError: (err) => {
      toast.error(err instanceof Error ? err.message : 'Failed to remove member.')
    },
  })

  const columns: ColumnDef<PlatformRoleMember, unknown>[] = [
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
      accessorKey: 'assignedOnUtc',
      header: 'Assigned',
      cell: ({ row }) => (
        <span className="text-sm text-muted-foreground">
          {new Date(row.original.assignedOnUtc).toLocaleDateString()}
        </span>
      ),
      meta: { className: 'w-[130px]' },
    },
    {
      id: 'remove',
      header: '',
      cell: ({ row }) => (
        <PermissionGate permission={PERMISSIONS.PLATFORM_ROLES_MANAGE}>
          <Button
            size="sm"
            variant="ghost"
            className="text-destructive hover:bg-destructive/10 hover:text-destructive"
            onClick={() => removeMutation.mutate(row.original.userId)}
            disabled={removeMutation.isPending}
          >
            <Trash2 className="h-3.5 w-3.5" />
          </Button>
        </PermissionGate>
      ),
      meta: { className: 'w-[50px]' },
    },
  ]

  return (
    <div className="space-y-3 pt-4">
      <div className="flex justify-end">
        <PermissionGate permission={PERMISSIONS.PLATFORM_ROLES_MANAGE}>
          <AddMemberDialog
            roleId={roleId}
            memberUpns={members.map((member) => member.upn)}
            onSuccess={() => {
              queryClient.invalidateQueries({ queryKey: ['platform-roles', roleId] })
              queryClient.invalidateQueries({ queryKey: ['platform-roles'] })
            }}
          />
        </PermissionGate>
      </div>
      <DataTable columns={columns} data={members} isLoading={isLoading} />
    </div>
  )
}

// ---------------------------------------------------------------------------
// Main component
// ---------------------------------------------------------------------------
export function PlatformRoleDetail({ roleId }: { roleId: number }) {
  const router = useRouter()

  const { data, isLoading, isError } = useQuery({
    queryKey: ['platform-roles', roleId],
    queryFn: () => api.platformRoles.get(roleId),
  })

  const { data: allPermsData, isLoading: permsLoading } = useQuery({
    queryKey: ['platform-permissions'],
    queryFn: () => api.platformPermissions.list(),
  })

  if (isError) {
    return (
      <div className="rounded-md border border-destructive/40 bg-destructive/5 p-6 text-center">
        <p className="text-sm font-medium text-destructive">Failed to load platform role</p>
      </div>
    )
  }

  const role = data?.role
  const permissions = data?.permissions ?? []
  const members = data?.members ?? []
  const allPermissions = allPermsData?.items ?? []

  return (
    <div className="space-y-6">
      <Button
        variant="ghost"
        size="sm"
        className="-ml-2 text-muted-foreground"
        onClick={() => router.push('/platform-roles')}
      >
        <ArrowLeft className="mr-1.5 h-4 w-4" />
        Platform Roles
      </Button>

      {isLoading ? (
        <div className="space-y-2">
          <Skeleton className="h-7 w-48" />
          <Skeleton className="h-4 w-64" />
        </div>
      ) : role ? (
        <div className="flex items-start justify-between">
          <div>
            <div className="flex flex-wrap items-center gap-3">
              <h1 className="text-2xl font-semibold tracking-tight">{role.roleName}</h1>
              <span className="rounded bg-muted px-2 py-0.5 font-mono text-sm text-muted-foreground">
                {role.roleCode}
              </span>
            </div>
            {role.description && (
              <p className="mt-1 text-sm text-muted-foreground">{role.description}</p>
            )}
          </div>
          <StatusBadge status={role.isActive ? 'Active' : 'Inactive'} />
        </div>
      ) : null}

      <div className="grid grid-cols-2 gap-4 sm:grid-cols-2">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">Members</CardTitle>
            <Users className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold tabular-nums">
              {isLoading ? '—' : role?.memberCount ?? 0}
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">Permissions</CardTitle>
            <ShieldCheck className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold tabular-nums">
              {isLoading ? '—' : role?.permissionCount ?? 0}
            </div>
          </CardContent>
        </Card>
      </div>

      <Tabs defaultValue="permissions">
        <TabsList>
          <TabsTrigger value="permissions">
            Permissions {!isLoading && `(${permissions.length})`}
          </TabsTrigger>
          <TabsTrigger value="members">
            Members {!isLoading && `(${members.length})`}
          </TabsTrigger>
        </TabsList>

        <TabsContent value="permissions">
          <PermissionsTab
            roleId={roleId}
            currentPermissions={permissions}
            allPermissions={allPermissions}
            isLoading={isLoading || permsLoading}
          />
        </TabsContent>

        <TabsContent value="members">
          <MembersTab roleId={roleId} members={members} isLoading={isLoading} />
        </TabsContent>
      </Tabs>
    </div>
  )
}
