'use client'

import { useQuery } from '@tanstack/react-query'
import { useRouter } from 'next/navigation'
import {
  Activity,
  AlertTriangle,
  ArrowRight,
  ArrowRightLeft,
  Building2,
  CheckCircle2,
  Shield,
  UserPlus,
  Users,
} from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { api } from '@/lib/api'
import { useMemo, useState } from 'react'
import { OnboardUserWizard } from '@/components/shared/onboard-user-wizard'
import { StatCard } from '@/components/shared/stat-card'
import { useAccount } from '@/contexts/account-context'
import { usePermissions } from '@/hooks/usePermissions'
import { useAccessibleSites } from '@/hooks/useAccessibleSites'

// ---------------------------------------------------------------------------
// Quick action button
// ---------------------------------------------------------------------------

interface QuickActionProps {
  label: string
  description: string
  icon: React.ElementType
  onClick: () => void
  variant?: 'default' | 'outline'
}

function QuickAction({ label, description, icon: Icon, onClick, variant: _variant = 'outline' }: QuickActionProps) {
  return (
    <button
      onClick={onClick}
      className="group flex items-center gap-4 rounded-xl border bg-card p-4 text-left transition-all hover:border-primary/40 hover:shadow-sm w-full"
    >
      <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary group-hover:bg-primary/15">
        <Icon className="h-5 w-5" />
      </div>
      <div className="min-w-0 flex-1">
        <p className="text-sm font-medium leading-tight">{label}</p>
        <p className="mt-0.5 text-xs text-muted-foreground truncate">{description}</p>
      </div>
      <ArrowRight className="h-4 w-4 shrink-0 text-muted-foreground/50 group-hover:text-primary transition-colors" />
    </button>
  )
}

// ---------------------------------------------------------------------------
// Coverage health card
// ---------------------------------------------------------------------------

function CoverageHealthCard() {
  // Coverage is a cross-tenant platform-wide aggregation and is only safe to
  // surface for super-admins. The /coverage page itself is gated at the
  // route-permission layer; this card would otherwise pull the same unscoped
  // data onto every tenant admin's dashboard.
  const { isSuperAdmin } = usePermissions()
  const { data, isLoading } = useQuery({
    queryKey: ['coverage'],
    queryFn: () => api.coverage.list(),
    enabled: isSuperAdmin,
  })

  const router = useRouter()

  if (!isSuperAdmin) return null

  if (isLoading) {
    return (
      <Card className="rounded-xl">
        <CardHeader>
          <CardTitle className="text-sm font-semibold">Coverage Health</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          {[1, 2, 3].map((i) => (
            <div key={i} className="h-10 animate-pulse rounded-lg bg-muted" />
          ))}
        </CardContent>
      </Card>
    )
  }

  const items = data?.items ?? []
  const totalUsers = items.length
  const okUsers = items.filter((u) => !u.gapStatus || u.gapStatus === 'OK').length
  const gapUsers = items.filter((u) => u.gapStatus && u.gapStatus !== 'OK')

  return (
    <Card className="rounded-xl">
      <CardHeader className="flex flex-row items-center justify-between pb-3">
        <CardTitle className="text-sm font-semibold">Coverage Health</CardTitle>
        <Button
          variant="ghost"
          size="sm"
          className="h-7 text-xs text-muted-foreground"
          onClick={() => router.push('/coverage')}
        >
          View all
          <ArrowRight className="ml-1 h-3 w-3" />
        </Button>
      </CardHeader>
      <CardContent className="space-y-3">
        {/* OK */}
        <div className="flex items-center justify-between rounded-lg bg-success-muted px-3 py-2.5">
          <div className="flex items-center gap-2.5">
            <CheckCircle2 className="h-4 w-4 text-success" />
            <span className="text-sm font-medium text-success-muted-foreground">Full coverage</span>
          </div>
          <span className="text-sm font-bold tabular-nums text-success-muted-foreground">
            {okUsers} / {totalUsers}
          </span>
        </div>

        {/* Gaps */}
        {gapUsers.length > 0 ? (
          <div className="flex items-center justify-between rounded-lg bg-warning-muted px-3 py-2.5">
            <div className="flex items-center gap-2.5">
              <AlertTriangle className="h-4 w-4 text-warning" />
              <span className="text-sm font-medium text-warning-muted-foreground">Coverage gaps</span>
            </div>
            <Badge variant="outline" className="border-warning-border bg-warning-muted text-warning-muted-foreground tabular-nums text-xs">
              {gapUsers.length} {gapUsers.length === 1 ? 'user' : 'users'}
            </Badge>
          </div>
        ) : (
          <p className="text-center text-xs text-muted-foreground py-2">No coverage gaps detected</p>
        )}

        {/* Top gap users */}
        {gapUsers.slice(0, 3).map((u) => (
          <div key={u.userId} className="flex items-center justify-between rounded-md px-2 py-1.5">
            <div className="min-w-0">
              <p className="truncate text-xs font-medium">{u.upn}</p>
              <p className="text-xs text-muted-foreground">{u.siteCount} sites · {u.packageCount} packages</p>
            </div>
            <Badge variant="destructive" className="ml-2 shrink-0 text-xs">
              {u.gapStatus}
            </Badge>
          </div>
        ))}
      </CardContent>
    </Card>
  )
}

// ---------------------------------------------------------------------------
// Recent delegations card
// ---------------------------------------------------------------------------

function RecentDelegationsCard() {
  const { selectedAccount } = useAccount()
  const accountId = selectedAccount?.accountId

  // api.delegations.list() is not yet filterable server-side. We scope the
  // cache key on accountId so switching accounts does not surface stale
  // counts from another tenant, and filter client-side to ALL delegations
  // + delegations tagged to this account.
  const { data, isLoading } = useQuery({
    // Shared key with the /delegations page: api.delegations.list() returns
    // the full set, so there is no server-side accountId filter to key on.
    // Filtering happens client-side below.
    queryKey: ['delegations'],
    queryFn: () => api.delegations.list(),
    enabled: !!accountId,
  })
  const router = useRouter()

  const recent = (data?.items ?? [])
    .filter(
      (d) =>
        d.accessType === 'ALL' || d.accountCode === selectedAccount?.accountCode
    )
    .sort((a, b) => new Date(b.createdOnUtc).getTime() - new Date(a.createdOnUtc).getTime())
    .slice(0, 5)

  return (
    <Card className="rounded-xl">
      <CardHeader className="flex flex-row items-center justify-between pb-3">
        <CardTitle className="text-sm font-semibold">Recent Delegations</CardTitle>
        <Button
          variant="ghost"
          size="sm"
          className="h-7 text-xs text-muted-foreground"
          onClick={() => router.push('/delegations')}
        >
          View all
          <ArrowRight className="ml-1 h-3 w-3" />
        </Button>
      </CardHeader>
      <CardContent>
        {isLoading ? (
          <div className="space-y-2">
            {[1, 2, 3].map((i) => (
              <div key={i} className="h-10 animate-pulse rounded-lg bg-muted" />
            ))}
          </div>
        ) : recent.length === 0 ? (
          <p className="text-center text-xs text-muted-foreground py-4">No delegations found</p>
        ) : (
          <div className="space-y-2">
            {recent.map((d) => (
              <div
                key={d.principalDelegationId}
                className="flex items-start justify-between gap-2 rounded-lg px-2 py-2 hover:bg-muted/40 transition-colors"
              >
                <div className="min-w-0 flex-1">
                  <p className="truncate text-xs font-medium">
                    {d.delegateName}
                  </p>
                  <p className="text-xs text-muted-foreground truncate">
                    from {d.delegatorName}
                    {d.accountName ? ` · ${d.accountName}` : ''}
                  </p>
                </div>
                <Badge
                  variant={d.isActive ? 'default' : 'secondary'}
                  className="shrink-0 text-xs"
                >
                  {d.isActive ? 'Active' : 'Inactive'}
                </Badge>
              </div>
            ))}
          </div>
        )}
      </CardContent>
    </Card>
  )
}

// ---------------------------------------------------------------------------
// Main dashboard
// ---------------------------------------------------------------------------

export function DashboardContent() {
  const router = useRouter()
  const [onboardOpen, setOnboardOpen] = useState(false)
  const { selectedAccount, accounts, isLoading: accountsLoading } = useAccount()

  const accountId = selectedAccount?.accountId

  // Account-scoped: users in this account
  const { data: accountUsersData, isLoading: usersLoading } = useQuery({
    queryKey: ['accounts', accountId, 'users'],
    queryFn: () => api.accounts.users(accountId!),
    enabled: !!accountId,
  })

  // Account-scoped: org units in this account
  const { data: orgUnitsData, isLoading: orgUnitsLoading } = useQuery({
    queryKey: ['org-units', { accountId }],
    queryFn: () => api.orgUnits.list({ accountId }),
    enabled: !!accountId,
  })

  // Account-scoped: roles for this account (api.roles.list already supports { accountId }).
  const { data: rolesData, isLoading: rolesLoading } = useQuery({
    queryKey: ['roles', { accountId }],
    queryFn: () => api.roles.list({ accountId }),
    enabled: !!accountId,
  })

  // Delegations are not yet filterable server-side, but we key the cache on
  // accountId so switching accounts doesn't surface stale counts. The counter
  // below still filters client-side to ALL delegations + this-account delegations.
  const { data: delegationsData, isLoading: delegationsLoading } = useQuery({
    // Shared key with the /delegations page: api.delegations.list() returns
    // the full set, so there is no server-side accountId filter to key on.
    // Filtering happens client-side below.
    queryKey: ['delegations'],
    queryFn: () => api.delegations.list(),
    enabled: !!accountId,
  })

  const accessible = useAccessibleSites()

  const activeUsers = accountUsersData?.items.filter((u) => u.isActive).length ?? 0

  // Scope the org-units count to what the user can actually see. Role-scoped
  // users otherwise see "25 sites" on the dashboard when they have access to
  // 1 — which reads as if the /sites page has a bug even though the tree is
  // filtered correctly.
  const totalOrgUnits = useMemo(() => {
    const raw = orgUnitsData?.items ?? []
    if (accessible.mode === 'all') return orgUnitsData?.totalCount ?? raw.length
    if (accessible.isLoading) return 0
    return raw.filter((u) => accessible.siteCodes.has(u.orgUnitCode)).length
  }, [orgUnitsData, accessible])

  const activeRoles = rolesData?.items.filter((r) => r.isActive).length ?? 0

  // Scope delegations to the selected account:
  // include global (ALL) delegations + those explicitly for this account
  const activeDelegations = delegationsData?.items.filter(
    (d) =>
      d.isActive &&
      (d.accessType === 'ALL' || d.accountCode === selectedAccount?.accountCode)
  ).length ?? 0

  return (
    <div className="space-y-8">
      {/* Page header with account context */}
      <div className="flex items-start justify-between gap-4 flex-wrap">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">Dashboard</h1>
          {selectedAccount ? (
            <p className="text-sm text-muted-foreground mt-1">
              Showing data for{' '}
              <span className="font-medium text-foreground">{selectedAccount.accountName}</span>
              <span className="ml-1.5 font-mono text-xs text-muted-foreground/70">
                {selectedAccount.accountCode}
              </span>
              {accounts.filter(a => a.isActive).length > 1 && (
                <span className="ml-2 text-xs text-muted-foreground">
                  · Switch account using the selector in the sidebar
                </span>
              )}
            </p>
          ) : (
            <p className="text-sm text-muted-foreground mt-1">
              {accountsLoading ? 'Loading account…' : 'No account selected'}
            </p>
          )}
        </div>
        {selectedAccount && (
          <button
            onClick={() => router.push(`/accounts/${selectedAccount.accountId}`)}
            className="flex items-center gap-1.5 rounded-lg border px-3 py-1.5 text-xs text-muted-foreground hover:border-primary/40 hover:text-primary transition-colors"
          >
            <Building2 className="h-3.5 w-3.5" />
            View account workspace
            <ArrowRight className="h-3 w-3" />
          </button>
        )}
      </div>

      {/* Stats — account-scoped */}
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard
          title="Users in Account"
          value={activeUsers}
          subtitle={accountUsersData ? `${accountUsersData.totalCount} total` : undefined}
          icon={Users}
          iconColor="bg-info-muted text-info-muted-foreground"
          loading={usersLoading || accountsLoading}
        />
        <StatCard
          title="Org Units"
          value={totalOrgUnits}
          subtitle={selectedAccount ? `in ${selectedAccount.accountCode}` : undefined}
          icon={Building2}
          iconColor="bg-brand-muted text-brand"
          loading={orgUnitsLoading || accountsLoading}
        />
        <StatCard
          title="Active Roles"
          value={activeRoles}
          subtitle={rolesData ? `${rolesData.totalCount} total` : undefined}
          icon={Shield}
          iconColor="bg-success-muted text-success-muted-foreground"
          loading={rolesLoading}
        />
        <StatCard
          title="Active Delegations"
          value={activeDelegations}
          subtitle={delegationsData ? `${delegationsData.totalCount} total` : undefined}
          icon={ArrowRightLeft}
          iconColor="bg-warning-muted text-warning-muted-foreground"
          loading={delegationsLoading}
        />
      </div>

      {/* Quick actions */}
      <div>
        <h2 className="mb-3 text-sm font-semibold text-muted-foreground uppercase tracking-wide">
          Quick Actions
        </h2>
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <QuickAction
            label="Onboard User"
            description="Create user, assign roles & access"
            icon={UserPlus}
            onClick={() => setOnboardOpen(true)}
          />
          <QuickAction
            label="Manage Users"
            description="View users, assign roles and grant access"
            icon={Users}
            onClick={() => router.push('/users')}
          />
          <QuickAction
            label="Delegations"
            description="Manage temporary access delegations"
            icon={ArrowRightLeft}
            onClick={() => router.push('/delegations')}
          />
          <QuickAction
            label="KPI Monitoring"
            description="Track submission completion by site"
            icon={Activity}
            onClick={() => router.push('/kpi/monitoring')}
          />
        </div>
      </div>

      {/* Bottom grid: coverage health + recent delegations */}
      <div className="grid gap-6 lg:grid-cols-2">
        <CoverageHealthCard />
        <RecentDelegationsCard />
      </div>

      {/* Wizards / dialogs */}
      <OnboardUserWizard open={onboardOpen} onOpenChange={setOnboardOpen} accountId={accountId} />
    </div>
  )
}
