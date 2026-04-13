'use client'

import { useQuery } from '@tanstack/react-query'
import { useRouter } from 'next/navigation'
import {
  ArrowLeft,
  ArrowRight,
  Building2,
  CheckCircle2,
  ExternalLink,
  MapPin,
  Package,
  Shield,
  UserPlus,
  Users,
  AlertTriangle,
} from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Badge } from '@/components/ui/badge'
import { StatusBadge } from '@/components/shared/status-badge'
import { PermissionGate } from '@/components/shared/permission-gate'
import { AccountSitesTable } from '@/app/(admin)/sites/sites-table'
import { AccountUsersTable } from '@/app/(admin)/users/users-table'
import { ImportOrgUnitsDialog } from '@/app/(admin)/sites/import-org-units-dialog'
import { OnboardUserWizard } from '@/components/shared/onboard-user-wizard'
import { api } from '@/lib/api'
import { PERMISSIONS } from '@/types/api'
import type { CoverageSummary } from '@/types/api'
import { useState } from 'react'
import { cn } from '@/lib/utils'

// ---------------------------------------------------------------------------
// Stat card
// ---------------------------------------------------------------------------

interface StatCardProps {
  title: string
  value: string | number
  icon: React.ElementType
  iconColor: string
  loading?: boolean
  onClick?: () => void
}

function StatCard({ title, value, icon: Icon, iconColor, loading, onClick }: StatCardProps) {
  return (
    <Card
      className={cn('rounded-xl', onClick && 'cursor-pointer hover:border-primary/40 transition-colors')}
      onClick={onClick}
    >
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm font-medium text-muted-foreground">{title}</CardTitle>
        <div className={`rounded-lg p-2 ${iconColor}`}>
          <Icon className="h-4 w-4" />
        </div>
      </CardHeader>
      <CardContent>
        {loading ? (
          <div className="h-8 w-12 animate-pulse rounded bg-muted" />
        ) : (
          <div className="text-2xl font-bold tabular-nums">{value}</div>
        )}
      </CardContent>
    </Card>
  )
}

// ---------------------------------------------------------------------------
// Coverage tab
// ---------------------------------------------------------------------------

function AccountCoverageTab({ accountId }: { accountId: number }) {
  const { data, isLoading } = useQuery({
    queryKey: ['coverage'],
    queryFn: () => api.coverage.list(),
  })

  const { data: usersData } = useQuery({
    queryKey: ['accounts', accountId, 'users'],
    queryFn: () => api.accounts.users(accountId),
    enabled: !!accountId,
  })

  // Filter coverage to users in this account
  const accountUpns = new Set((usersData?.items ?? []).map((u) => u.upn.toLowerCase()))
  const coverage = (data?.items ?? []).filter((c) => accountUpns.has(c.upn.toLowerCase()))

  const gapUsers = coverage.filter((c) => c.gapStatus && c.gapStatus !== 'OK')
  const okUsers = coverage.filter((c) => !c.gapStatus || c.gapStatus === 'OK')

  if (isLoading) {
    return (
      <div className="space-y-2">
        {[1, 2, 3].map((i) => (
          <div key={i} className="h-12 animate-pulse rounded-lg bg-muted" />
        ))}
      </div>
    )
  }

  return (
    <div className="space-y-4">
      {/* Summary */}
      <div className="grid gap-3 sm:grid-cols-2">
        <div className="flex items-center justify-between rounded-xl border bg-emerald-50/50 px-4 py-3 dark:bg-emerald-950/10">
          <div className="flex items-center gap-2.5">
            <CheckCircle2 className="h-4 w-4 text-emerald-600" />
            <span className="text-sm font-medium">Full coverage</span>
          </div>
          <span className="text-lg font-bold tabular-nums text-emerald-700">{okUsers.length}</span>
        </div>
        <div className="flex items-center justify-between rounded-xl border bg-amber-50/50 px-4 py-3 dark:bg-amber-950/10">
          <div className="flex items-center gap-2.5">
            <AlertTriangle className="h-4 w-4 text-amber-600" />
            <span className="text-sm font-medium">Coverage gaps</span>
          </div>
          <span className="text-lg font-bold tabular-nums text-amber-700">{gapUsers.length}</span>
        </div>
      </div>

      {/* Gap users */}
      {gapUsers.length === 0 ? (
        <div className="rounded-xl border border-dashed py-8 text-center">
          <CheckCircle2 className="mx-auto mb-2 h-8 w-8 text-emerald-500" />
          <p className="text-sm font-medium text-muted-foreground">No coverage gaps for this account</p>
        </div>
      ) : (
        <div className="rounded-xl border divide-y overflow-hidden">
          {gapUsers.map((user: CoverageSummary) => (
            <div key={user.userId} className="flex items-center justify-between px-4 py-3 hover:bg-muted/30 transition-colors">
              <div>
                <p className="text-sm font-medium">{user.upn}</p>
                <p className="text-xs text-muted-foreground">
                  {user.siteCount} sites · {user.packageCount} packages
                </p>
              </div>
              <Badge variant="destructive" className="text-xs">{user.gapStatus}</Badge>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Access & Roles tab
// ---------------------------------------------------------------------------

function AccountAccessTab({ accountId }: { accountId: number }) {
  const { data: rolesData, isLoading: rolesLoading } = useQuery({
    queryKey: ['roles', { accountId }],
    queryFn: () => api.roles.list({ accountId }),
  })

  const router = useRouter()

  // API returns only account-specific roles + global roles for this account
  const accountRoles = (rolesData?.items ?? []).filter((r) => r.accountId === accountId)

  if (rolesLoading) {
    return (
      <div className="space-y-2">
        {[1, 2, 3].map((i) => (
          <div key={i} className="h-12 animate-pulse rounded-lg bg-muted" />
        ))}
      </div>
    )
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <p className="text-sm text-muted-foreground">
          Roles associated with this account.{' '}
          <button
            className="text-primary hover:underline"
            onClick={() => router.push('/roles')}
          >
            Manage all roles →
          </button>
        </p>
      </div>

      {accountRoles.length === 0 ? (
        <div className="rounded-xl border border-dashed py-8 text-center text-sm text-muted-foreground">
          No account-scoped roles found. Roles will appear here once policies are applied to this account.
        </div>
      ) : (
        <div className="rounded-xl border divide-y overflow-hidden">
          {accountRoles.map((role) => (
            <div
              key={role.roleId}
              className="flex items-center justify-between px-4 py-3 hover:bg-muted/30 transition-colors cursor-pointer"
              onClick={() => router.push(`/roles/${role.roleId}`)}
            >
              <div className="min-w-0">
                <div className="flex items-center gap-2">
                  <span className="text-sm font-medium">{role.roleName}</span>
                  {!role.isActive && (
                    <Badge variant="secondary" className="text-xs">Inactive</Badge>
                  )}
                </div>
                <span className="font-mono text-xs text-muted-foreground">{role.roleCode}</span>
              </div>
              <div className="flex items-center gap-4 shrink-0">
                <div className="text-right">
                  <p className="text-sm font-medium tabular-nums">{role.memberCount}</p>
                  <p className="text-xs text-muted-foreground">members</p>
                </div>
                <ArrowRight className="h-4 w-4 text-muted-foreground/40" />
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

// ---------------------------------------------------------------------------
// KPI tab
// ---------------------------------------------------------------------------

function AccountKpiTab({ accountId }: { accountId: number }) {
  const router = useRouter()

  const { data: periodsData, isLoading: periodsLoading } = useQuery({
    queryKey: ['kpi-periods'],
    queryFn: () => api.kpi.periods.list(),
  })

  const latestPeriod = periodsData?.items
    .sort((a, b) => {
      const av = a.periodYear * 100 + a.periodMonth
      const bv = b.periodYear * 100 + b.periodMonth
      return bv - av
    })[0]

  const { data: monitoringData, isLoading: monitoringLoading } = useQuery({
    queryKey: ['kpi-monitoring', { accountId, periodId: latestPeriod?.periodId }],
    queryFn: () =>
      api.kpi.monitoring.list({
        accountId,
        periodId: latestPeriod?.periodId,
      }),
    enabled: !!latestPeriod,
  })

  const sites = monitoringData?.items ?? []
  const totalSites = sites.length
  const completedSites = sites.filter((s) => s.completionPct >= 100).length
  const avgCompletion =
    totalSites > 0
      ? Math.round(sites.reduce((sum, s) => sum + s.completionPct, 0) / totalSites)
      : 0

  const isLoading = periodsLoading || monitoringLoading

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          {latestPeriod && (
            <p className="text-sm text-muted-foreground">
              Period:{' '}
              <span className="font-medium text-foreground">
                {latestPeriod.periodYear}/{String(latestPeriod.periodMonth).padStart(2, '0')}
              </span>
              {' · '}
              <Badge variant="outline" className="text-xs">{latestPeriod.status}</Badge>
            </p>
          )}
        </div>
        <Button
          variant="outline"
          size="sm"
          onClick={() => router.push('/kpi/monitoring')}
        >
          <ExternalLink className="mr-1.5 h-3.5 w-3.5" />
          Full monitoring view
        </Button>
      </div>

      {/* Stats */}
      {!isLoading && totalSites > 0 && (
        <div className="grid gap-3 sm:grid-cols-3">
          <div className="rounded-xl border p-4 text-center">
            <p className="text-2xl font-bold tabular-nums">{avgCompletion}%</p>
            <p className="text-xs text-muted-foreground mt-0.5">Avg completion</p>
          </div>
          <div className="rounded-xl border p-4 text-center">
            <p className="text-2xl font-bold tabular-nums text-emerald-600">{completedSites}</p>
            <p className="text-xs text-muted-foreground mt-0.5">Sites complete</p>
          </div>
          <div className="rounded-xl border p-4 text-center">
            <p className="text-2xl font-bold tabular-nums text-amber-600">{totalSites - completedSites}</p>
            <p className="text-xs text-muted-foreground mt-0.5">Pending</p>
          </div>
        </div>
      )}

      {/* Site list */}
      {isLoading ? (
        <div className="space-y-2">
          {[1, 2, 3].map((i) => (
            <div key={i} className="h-12 animate-pulse rounded-lg bg-muted" />
          ))}
        </div>
      ) : sites.length === 0 ? (
        <div className="rounded-xl border border-dashed py-8 text-center text-sm text-muted-foreground">
          No KPI data for this account.{' '}
          <button
            className="text-primary hover:underline"
            onClick={() => router.push('/kpi/assignments')}
          >
            Configure assignments →
          </button>
        </div>
      ) : (
        <div className="rounded-xl border divide-y overflow-hidden">
          {sites.slice(0, 10).map((site) => {
            const pct = Math.min(Math.round(site.completionPct), 100)
            const color = pct >= 100 ? 'bg-emerald-500' : pct >= 75 ? 'bg-amber-400' : 'bg-red-400'
            return (
              <div key={site.siteOrgUnitId} className="flex items-center gap-4 px-4 py-3">
                <div className="min-w-0 flex-1">
                  <p className="text-sm font-medium truncate">{site.siteName}</p>
                  <p className="text-xs text-muted-foreground font-mono">{site.siteCode}</p>
                </div>
                <div className="flex items-center gap-3 shrink-0">
                  <div className="hidden sm:flex items-center gap-2 w-32">
                    <div className="h-1.5 flex-1 rounded-full bg-muted overflow-hidden">
                      <div
                        className={cn('h-full rounded-full transition-all', color)}
                        style={{ width: `${pct}%` }}
                      />
                    </div>
                    <span className="text-xs tabular-nums text-muted-foreground w-8 text-right">{pct}%</span>
                  </div>
                  <Badge
                    variant={pct >= 100 ? 'default' : 'secondary'}
                    className={cn('text-xs sm:hidden', pct >= 100 ? 'bg-emerald-100 text-emerald-800' : '')}
                  >
                    {pct}%
                  </Badge>
                </div>
              </div>
            )
          })}
          {sites.length > 10 && (
            <div className="px-4 py-3 text-center">
              <button
                className="text-xs text-primary hover:underline"
                onClick={() => router.push('/kpi/monitoring')}
              >
                View all {sites.length} sites →
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Main account detail
// ---------------------------------------------------------------------------

interface AccountDetailProps {
  accountId: number
}

export function AccountDetail({ accountId }: AccountDetailProps) {
  const router = useRouter()
  const [onboardOpen, setOnboardOpen] = useState(false)

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

  const {
    data: packagesData,
  } = useQuery({
    queryKey: ['packages'],
    queryFn: () => api.packages.list(),
  })

  const {
    data: rolesData,
    isLoading: rolesLoading,
  } = useQuery({
    queryKey: ['roles', { accountId }],
    queryFn: () => api.roles.list({ accountId }),
    enabled: !!account,
  })

  const accountRoleCount = (rolesData?.items ?? []).filter((r) => r.accountId === accountId).length

  if (accountError) {
    return (
      <div className="rounded-xl border border-destructive/40 bg-destructive/5 p-6 text-center">
        <p className="text-sm font-medium text-destructive">Failed to load account</p>
      </div>
    )
  }

  const activePackages = packagesData?.items.filter((p) => p.isActive).length ?? 0

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
        All Accounts
      </Button>

      {/* Account header */}
      {accountLoading ? (
        <div className="h-14 w-64 animate-pulse rounded-lg bg-muted" />
      ) : account ? (
        <div className="flex items-start justify-between gap-4 flex-wrap">
          <div>
            <div className="flex items-center gap-3 flex-wrap">
              <h1 className="text-2xl font-bold tracking-tight">{account.accountName}</h1>
              <span className="font-mono text-sm text-muted-foreground bg-muted px-2.5 py-1 rounded-lg">
                {account.accountCode}
              </span>
            </div>
            <p className="mt-1 text-sm text-muted-foreground">
              Manage users, org structure, access and KPI for this account.
            </p>
          </div>
          <div className="flex items-center gap-2">
            <PermissionGate permission={PERMISSIONS.USERS_MANAGE}>
              <Button size="sm" onClick={() => setOnboardOpen(true)}>
                <UserPlus className="mr-1.5 h-4 w-4" />
                Onboard User
              </Button>
            </PermissionGate>
            <StatusBadge status={account.isActive ? 'Active' : 'Inactive'} />
          </div>
        </div>
      ) : null}

      {/* Stat cards */}
      <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-5">
        <StatCard
          title="Sites"
          value={accountLoading ? '—' : account?.siteCount ?? 0}
          icon={MapPin}
          iconColor="bg-blue-100 text-blue-600 dark:bg-blue-950/40"
          loading={accountLoading}
        />
        <StatCard
          title="Users"
          value={accountLoading ? '—' : account?.userCount ?? 0}
          icon={Users}
          iconColor="bg-violet-100 text-violet-600 dark:bg-violet-950/40"
          loading={accountLoading}
        />
        <StatCard
          title="Org Units"
          value={orgUnitsLoading ? '—' : orgUnitsData?.totalCount ?? 0}
          icon={Building2}
          iconColor="bg-amber-100 text-amber-600 dark:bg-amber-950/40"
          loading={orgUnitsLoading}
        />
        <StatCard
          title="Packages"
          value={activePackages}
          icon={Package}
          iconColor="bg-emerald-100 text-emerald-600 dark:bg-emerald-950/40"
        />
        <StatCard
          title="Roles"
          value={rolesLoading ? '—' : accountRoleCount}
          icon={Shield}
          iconColor="bg-slate-100 text-slate-600 dark:bg-slate-800/40"
          loading={rolesLoading}
        />
      </div>

      {/* Tabs */}
      <Tabs defaultValue="users">
        <TabsList className="h-auto flex-wrap gap-1 p-1">
          <TabsTrigger value="users">Users</TabsTrigger>
          <TabsTrigger value="structure">Org Structure</TabsTrigger>
          <TabsTrigger value="access">Access & Roles</TabsTrigger>
          <TabsTrigger value="kpi">KPI</TabsTrigger>
          <TabsTrigger value="coverage">Coverage</TabsTrigger>
        </TabsList>

        <TabsContent value="users" className="mt-5">
          <AccountUsersTable accountId={accountId} />
        </TabsContent>

        <TabsContent value="structure" className="mt-5">
          <div className="flex justify-end mb-3">
            <PermissionGate permission={PERMISSIONS.ACCOUNTS_MANAGE}>
              <ImportOrgUnitsDialog defaultAccountCode={account?.accountCode} />
            </PermissionGate>
          </div>
          <AccountSitesTable accountId={accountId} />
        </TabsContent>

        <TabsContent value="access" className="mt-5">
          <AccountAccessTab accountId={accountId} />
        </TabsContent>

        <TabsContent value="kpi" className="mt-5">
          <AccountKpiTab accountId={accountId} />
        </TabsContent>

        <TabsContent value="coverage" className="mt-5">
          <AccountCoverageTab accountId={accountId} />
        </TabsContent>
      </Tabs>

      <OnboardUserWizard open={onboardOpen} onOpenChange={setOnboardOpen} accountId={accountId} />
    </div>
  )
}
