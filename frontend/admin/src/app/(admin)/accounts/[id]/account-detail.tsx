'use client'

import { useQuery } from '@tanstack/react-query'
import { useRouter } from 'next/navigation'
import { ArrowLeft, Building2, Users, MapPin } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { StatusBadge } from '@/components/shared/status-badge'
import { PermissionGate } from '@/components/shared/permission-gate'
import { AccountSitesTable } from '@/app/(admin)/sites/sites-table'
import { AccountUsersTable } from '@/app/(admin)/users/users-table'
import { ImportOrgUnitsDialog } from '@/app/(admin)/sites/import-org-units-dialog'
import { api } from '@/lib/api'
import { PERMISSIONS } from '@/types/api'

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

interface AccountDetailProps {
  accountId: number
}

export function AccountDetail({ accountId }: AccountDetailProps) {
  const router = useRouter()

  const {
    data: account,
    isLoading: accountLoading,
    isError: accountError,
  } = useQuery({
    queryKey: ['accounts', accountId],
    queryFn: () => api.accounts.get(accountId),
  })

  const {
    data: orgUnitsData,
    isLoading: orgUnitsLoading,
  } = useQuery({
    queryKey: ['org-units', { accountId }],
    queryFn: () => api.orgUnits.list({ accountId }),
    enabled: !!account,
  })

  if (accountError) {
    return (
      <div className="rounded-md border border-destructive/40 bg-destructive/5 p-6 text-center">
        <p className="text-sm font-medium text-destructive">Failed to load account</p>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Back navigation */}
      <Button
        variant="ghost"
        size="sm"
        className="-ml-2 text-muted-foreground"
        onClick={() => router.push('/accounts')}
      >
        <ArrowLeft className="mr-1.5 h-4 w-4" />
        Accounts
      </Button>

      {/* Account header */}
      {accountLoading ? (
        <div className="h-14 w-64 animate-pulse rounded-md bg-muted" />
      ) : account ? (
        <div className="flex items-start justify-between">
          <div>
            <div className="flex items-center gap-3">
              <h1 className="text-2xl font-semibold tracking-tight">{account.accountName}</h1>
              <span className="font-mono text-sm text-muted-foreground bg-muted px-2 py-0.5 rounded">
                {account.accountCode}
              </span>
            </div>
          </div>
          <StatusBadge status={account.isActive ? 'Active' : 'Inactive'} />
        </div>
      ) : null}

      {/* Stat cards */}
      <div className="grid grid-cols-2 gap-4 sm:grid-cols-3">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">Sites</CardTitle>
            <MapPin className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold tabular-nums">
              {accountLoading ? '—' : account?.siteCount ?? 0}
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">Users</CardTitle>
            <Users className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold tabular-nums">
              {accountLoading ? '—' : account?.userCount ?? 0}
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">Org Units</CardTitle>
            <Building2 className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold tabular-nums">
              {orgUnitsLoading ? '—' : orgUnitsData?.totalCount ?? 0}
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Tabs */}
      <Tabs defaultValue="structure">
        <TabsList>
          <TabsTrigger value="structure">Organisation Structure</TabsTrigger>
          <TabsTrigger value="users">Users</TabsTrigger>
          <TabsTrigger value="kpi">KPI Assignments</TabsTrigger>
        </TabsList>

        <TabsContent value="structure" className="mt-4">
          <div className="flex justify-end mb-3">
            <PermissionGate permission={PERMISSIONS.ACCOUNTS_MANAGE}>
              <ImportOrgUnitsDialog defaultAccountCode={account?.accountCode} />
            </PermissionGate>
          </div>
          <AccountSitesTable accountId={accountId} />
        </TabsContent>

        <TabsContent value="users" className="mt-4">
          <AccountUsersTable accountId={accountId} />
        </TabsContent>

        <TabsContent value="kpi" className="mt-4">
          <div className="rounded-md border border-dashed p-8 text-center text-sm text-muted-foreground">
            KPI assignment filtering by account coming soon.
          </div>
        </TabsContent>
      </Tabs>
    </div>
  )
}
