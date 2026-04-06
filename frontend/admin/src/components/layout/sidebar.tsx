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
  ClipboardList,
  GitBranch,
  ListChecks,
  Lock,
  Map,
  MapPin,
  Menu,
  Package,
  Shield,
  Users,
  X,
} from 'lucide-react'
import { useState } from 'react'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import { usePermissions } from '@/hooks/usePermissions'
import { PERMISSIONS } from '@/types/api'

// ---------------------------------------------------------------------------
// Nav structure
// ---------------------------------------------------------------------------

interface NavItem {
  label: string
  href: Route
  icon: React.ElementType
  /** If set, item is hidden unless user has this permission (or is Super Admin) */
  permission?: string
}

interface NavSection {
  title: string
  items: NavItem[]
}

const NAV_SECTIONS: NavSection[] = [
  {
    title: 'RBAC Management',
    items: [
      { label: 'Accounts', href: '/accounts', icon: Building2 },
      { label: 'Users', href: '/users', icon: Users },
      { label: 'Roles', href: '/roles', icon: Shield, permission: PERMISSIONS.PLATFORM_ROLES_MANAGE },
      { label: 'Policies', href: '/policies', icon: Lock, permission: PERMISSIONS.POLICIES_MANAGE },
      { label: 'Delegations', href: '/delegations', icon: ArrowRightLeft, permission: PERMISSIONS.GRANTS_MANAGE },
    ],
  },
  {
    title: 'Catalogue',
    items: [
      { label: 'Packages', href: '/packages', icon: Package },
      { label: 'BI Reports', href: '/reports', icon: BarChart2, permission: PERMISSIONS.SUPER_ADMIN },
    ],
  },
  {
    title: 'Infrastructure',
    items: [
      { label: 'Shared Geography', href: '/shared-geography', icon: Map, permission: PERMISSIONS.SUPER_ADMIN },
      { label: 'Org Units', href: '/sites', icon: MapPin },
      { label: 'Coverage', href: '/coverage', icon: Map, permission: PERMISSIONS.SUPER_ADMIN },
      { label: 'Source Mapping', href: '/source-mapping', icon: GitBranch, permission: PERMISSIONS.SUPER_ADMIN },
    ],
  },
  {
    title: 'KPI Platform',
    items: [
      { label: 'KPI Library', href: '/kpi/definitions', icon: ListChecks, permission: PERMISSIONS.KPI_MANAGE },
      { label: 'Periods', href: '/kpi/periods', icon: Calendar, permission: PERMISSIONS.KPI_MANAGE },
      { label: 'Assignments', href: '/kpi/assignments', icon: ClipboardList },
      { label: 'Monitoring', href: '/kpi/monitoring', icon: Activity },
    ],
  },
]

// ---------------------------------------------------------------------------
// NavItem component
// ---------------------------------------------------------------------------

function SidebarNavItem({ item }: { item: NavItem }) {
  const pathname = usePathname()
  const isActive =
    item.href === '/accounts'
      ? pathname === '/accounts' || pathname.startsWith('/accounts/')
      : pathname === item.href || pathname.startsWith(`${item.href}/`)

  const Icon = item.icon

  return (
    <Link
      href={item.href}
      className={cn(
        'group flex items-center gap-2.5 rounded-md px-3 py-2 text-sm font-medium transition-colors',
        isActive
          ? 'bg-primary/10 text-primary'
          : 'text-muted-foreground hover:bg-muted hover:text-foreground'
      )}
    >
      <Icon
        className={cn(
          'h-4 w-4 shrink-0 transition-colors',
          isActive ? 'text-primary' : 'text-muted-foreground group-hover:text-foreground'
        )}
      />
      {item.label}
    </Link>
  )
}

// ---------------------------------------------------------------------------
// Sidebar content (shared between desktop and mobile)
// ---------------------------------------------------------------------------

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
    <div className="flex h-full flex-col gap-1 px-3 py-4">
      {/* Wordmark */}
      <div className="mb-4 flex items-center gap-2.5 px-3">
        <div className="flex h-7 w-7 shrink-0 items-center justify-center rounded-md bg-primary text-xs font-bold text-primary-foreground">
          G
        </div>
        <div className="min-w-0">
          <p className="truncate text-sm font-semibold leading-none">GCE Platform</p>
          <p className="truncate text-xs text-muted-foreground">Admin Portal</p>
        </div>
      </div>

      {/* Nav sections */}
      {visibleSections.map((section) => (
        <div key={section.title} className="mb-3">
          <p className="mb-1 px-3 text-[10px] font-semibold uppercase tracking-widest text-muted-foreground/70">
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
    <aside className="hidden w-60 shrink-0 border-r bg-background lg:flex lg:flex-col">
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
          className="fixed inset-0 z-40 bg-black/40 lg:hidden"
          onClick={() => setOpen(false)}
          aria-hidden="true"
        />
      )}

      {/* Drawer */}
      <div
        className={cn(
          'fixed inset-y-0 left-0 z-50 w-60 bg-background shadow-xl transition-transform duration-200 ease-in-out lg:hidden',
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
          >
            <X className="h-4 w-4" />
          </Button>
        </div>
        <SidebarContent />
      </div>
    </>
  )
}
