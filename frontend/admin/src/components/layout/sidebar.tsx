'use client'

import Link from 'next/link'
import type { Route } from 'next'
import { usePathname } from 'next/navigation'
import {
  Activity,
  ArrowRightLeft,
  BarChart2,
  Building2,
  Calendar,
  Check,
  ChevronDown,
  ClipboardList,
  GitBranch,
  LayoutDashboard,
  ListChecks,
  Lock,
  Map,
  MapPin,
  Menu,
  Package,
  Shield,
  ShieldCheck,
  Users,
  X,
} from 'lucide-react'
import { useState } from 'react'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { usePermissions } from '@/hooks/usePermissions'
import { useAccount } from '@/contexts/account-context'
import { PERMISSIONS } from '@/types/api'

// ---------------------------------------------------------------------------
// Nav structure
// ---------------------------------------------------------------------------

interface NavItem {
  label: string
  href: Route
  icon: React.ElementType
  permission?: string
}

interface NavSection {
  title: string
  items: NavItem[]
}

const NAV_SECTIONS: NavSection[] = [
  {
    title: 'My Account',
    items: [
      { label: 'Dashboard', href: '/dashboard', icon: LayoutDashboard },
      { label: 'Users', href: '/users', icon: Users },
      { label: 'Org Structure', href: '/sites', icon: MapPin },
      { label: 'KPI Monitoring', href: '/kpi/monitoring', icon: Activity },
    ],
  },
  {
    title: 'Access Control',
    items: [
      { label: 'Roles', href: '/roles', icon: Shield, permission: PERMISSIONS.PLATFORM_ROLES_MANAGE },
      { label: 'Delegations', href: '/delegations', icon: ArrowRightLeft, permission: PERMISSIONS.GRANTS_MANAGE },
      { label: 'Policies', href: '/policies', icon: Lock, permission: PERMISSIONS.POLICIES_MANAGE },
    ],
  },
  {
    title: 'Platform Admin',
    items: [
      { label: 'All Accounts', href: '/accounts', icon: Building2 },
      { label: 'Platform Roles', href: '/platform-roles', icon: ShieldCheck, permission: PERMISSIONS.SUPER_ADMIN },
      { label: 'Packages', href: '/packages', icon: Package },
      { label: 'BI Reports', href: '/reports', icon: BarChart2, permission: PERMISSIONS.SUPER_ADMIN },
      { label: 'KPI Library', href: '/kpi/definitions', icon: ListChecks, permission: PERMISSIONS.KPI_MANAGE },
      { label: 'KPI Periods', href: '/kpi/periods', icon: Calendar, permission: PERMISSIONS.KPI_MANAGE },
      { label: 'KPI Assignments', href: '/kpi/assignments', icon: ClipboardList },
      { label: 'Coverage', href: '/coverage', icon: Map, permission: PERMISSIONS.SUPER_ADMIN },
      { label: 'Source Mapping', href: '/source-mapping', icon: GitBranch, permission: PERMISSIONS.SUPER_ADMIN },
      { label: 'Shared Geography', href: '/shared-geography', icon: Map, permission: PERMISSIONS.SUPER_ADMIN },
    ],
  },
]

// ---------------------------------------------------------------------------
// NavItem component
// ---------------------------------------------------------------------------

function SidebarNavItem({ item }: { item: NavItem }) {
  const pathname = usePathname()
  const isActive =
    item.href === '/dashboard'
      ? pathname === '/dashboard' || pathname === '/'
      : pathname === item.href || pathname.startsWith(`${item.href}/`)

  const Icon = item.icon

  return (
    <Link
      href={item.href}
      className={cn(
        'group flex items-center gap-2.5 rounded-lg px-3 py-2 text-sm font-medium transition-all duration-150',
        isActive
          ? 'bg-slate-700 text-white shadow-sm'
          : 'text-slate-400 hover:bg-slate-800 hover:text-slate-100'
      )}
    >
      <Icon
        className={cn(
          'h-4 w-4 shrink-0 transition-colors',
          isActive ? 'text-white' : 'text-slate-500 group-hover:text-slate-300'
        )}
      />
      {item.label}
    </Link>
  )
}

// ---------------------------------------------------------------------------
// Sidebar content (shared between desktop and mobile)
// ---------------------------------------------------------------------------

function AccountSwitcher() {
  const { accounts, selectedAccount, isLoading, selectAccount } = useAccount()
  const activeAccounts = accounts.filter((a) => a.isActive)
  const hasMultiple = activeAccounts.length > 1

  if (isLoading) {
    return (
      <div className="mx-1 mb-3 h-10 animate-pulse rounded-lg bg-slate-800" />
    )
  }

  if (!selectedAccount) return null

  if (!hasMultiple) {
    // Single account — just show the name, no dropdown needed
    return (
      <div className="mx-1 mb-3 flex items-center gap-2.5 rounded-lg bg-slate-800/60 px-3 py-2.5">
        <div className="flex h-6 w-6 shrink-0 items-center justify-center rounded bg-blue-500/20 text-xs font-bold text-blue-300">
          {selectedAccount.accountCode.charAt(0)}
        </div>
        <div className="min-w-0">
          <p className="truncate text-xs font-semibold leading-tight text-slate-200">
            {selectedAccount.accountName}
          </p>
          <p className="font-mono text-[10px] text-slate-500">{selectedAccount.accountCode}</p>
        </div>
      </div>
    )
  }

  // Multiple accounts — show a dropdown switcher
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <button className="mx-1 mb-3 flex w-[calc(100%-0.5rem)] items-center gap-2.5 rounded-lg bg-slate-800/60 px-3 py-2.5 text-left transition-colors hover:bg-slate-800 focus:outline-none focus-visible:ring-1 focus-visible:ring-blue-500">
          <div className="flex h-6 w-6 shrink-0 items-center justify-center rounded bg-blue-500/20 text-xs font-bold text-blue-300">
            {selectedAccount.accountCode.charAt(0)}
          </div>
          <div className="min-w-0 flex-1">
            <p className="truncate text-xs font-semibold leading-tight text-slate-200">
              {selectedAccount.accountName}
            </p>
            <p className="font-mono text-[10px] text-slate-500">{selectedAccount.accountCode}</p>
          </div>
          <ChevronDown className="h-3.5 w-3.5 shrink-0 text-slate-500" />
        </button>
      </DropdownMenuTrigger>

      <DropdownMenuContent
        side="right"
        align="start"
        sideOffset={8}
        className="w-60"
      >
        <DropdownMenuLabel className="text-xs text-muted-foreground font-normal">
          Switch account
        </DropdownMenuLabel>
        <DropdownMenuSeparator />
        {activeAccounts.map((account) => (
          <DropdownMenuItem
            key={account.accountId}
            onClick={() => selectAccount(account.accountId)}
            className="flex items-center justify-between gap-2 cursor-pointer"
          >
            <div className="min-w-0">
              <p className="truncate text-sm font-medium">{account.accountName}</p>
              <p className="font-mono text-xs text-muted-foreground">{account.accountCode}</p>
            </div>
            {account.accountId === selectedAccount.accountId && (
              <Check className="h-4 w-4 shrink-0 text-primary" />
            )}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

function SidebarContent() {
  const { can, isSuperAdmin } = usePermissions()

  const visibleSections = NAV_SECTIONS
    .map(section => ({
      ...section,
      items: section.items.filter(item =>
        !item.permission || isSuperAdmin || can(item.permission)
      ),
    }))
    .filter(section => section.items.length > 0)

  return (
    <div className="flex h-full flex-col gap-1 overflow-y-auto px-3 py-4">
      {/* Wordmark */}
      <div className="mb-4 flex items-center gap-3 px-2">
        <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-blue-500 text-sm font-bold text-white shadow-md">
          G
        </div>
        <div className="min-w-0">
          <p className="truncate text-sm font-semibold leading-tight text-white">GCE Platform</p>
          <p className="truncate text-xs text-slate-400">Admin Portal</p>
        </div>
      </div>

      {/* Account switcher */}
      <AccountSwitcher />

      {/* Nav sections */}
      {visibleSections.map((section) => (
        <div key={section.title} className="mb-4">
          <p className="mb-1.5 px-3 text-[10px] font-semibold uppercase tracking-widest text-slate-500">
            {section.title}
          </p>
          <nav className="space-y-0.5">
            {section.items.map((item) => (
              <SidebarNavItem key={item.href} item={item} />
            ))}
          </nav>
        </div>
      ))}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Desktop sidebar
// ---------------------------------------------------------------------------

export function Sidebar() {
  return (
    <aside className="hidden w-60 shrink-0 bg-slate-900 lg:flex lg:flex-col">
      <SidebarContent />
    </aside>
  )
}

// ---------------------------------------------------------------------------
// Mobile sidebar (sheet-style drawer)
// ---------------------------------------------------------------------------

export function MobileSidebar() {
  const [open, setOpen] = useState(false)

  return (
    <>
      <Button
        variant="ghost"
        size="icon"
        className="lg:hidden"
        onClick={() => setOpen(true)}
        aria-label="Open navigation menu"
      >
        <Menu className="h-5 w-5" />
      </Button>

      {/* Backdrop */}
      {open && (
        <div
          className="fixed inset-0 z-40 bg-black/50 lg:hidden"
          onClick={() => setOpen(false)}
          aria-hidden="true"
        />
      )}

      {/* Drawer */}
      <div
        className={cn(
          'fixed inset-y-0 left-0 z-50 w-60 bg-slate-900 shadow-2xl transition-transform duration-200 ease-in-out lg:hidden',
          open ? 'translate-x-0' : '-translate-x-full'
        )}
        role="dialog"
        aria-modal="true"
        aria-label="Navigation menu"
      >
        <div className="flex items-center justify-end px-3 py-3">
          <Button
            variant="ghost"
            size="icon"
            onClick={() => setOpen(false)}
            aria-label="Close navigation menu"
            className="text-slate-400 hover:text-white hover:bg-slate-800"
          >
            <X className="h-4 w-4" />
          </Button>
        </div>
        <SidebarContent />
      </div>
    </>
  )
}
