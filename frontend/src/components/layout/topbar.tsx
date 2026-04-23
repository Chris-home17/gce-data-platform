'use client'

import { useQueryClient } from '@tanstack/react-query'
import { useSession, signOut } from 'next-auth/react'
import { usePathname } from 'next/navigation'
import Link from 'next/link'
import type { Route } from 'next'
import { LogOut, ChevronDown, ChevronRight } from 'lucide-react'
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar'
import { Button } from '@/components/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { MobileSidebar } from './sidebar'

const SELECTED_ACCOUNT_STORAGE_KEY = 'gce:selectedAccountId'

// ---------------------------------------------------------------------------
// Breadcrumb helpers
// ---------------------------------------------------------------------------

const SEGMENT_LABELS: Record<string, string> = {
  dashboard: 'Dashboard',
  accounts: 'Accounts',
  users: 'Users',
  roles: 'Roles',
  policies: 'Policies',
  delegations: 'Delegations',
  packages: 'Packages',
  reports: 'BI Reports',
  'shared-geography': 'Shared Geography',
  sites: 'Org Units',
  coverage: 'Coverage',
  'source-mapping': 'Source Mapping',
  'platform-roles': 'Platform Roles',
  kpi: 'KPI',
  definitions: 'KPI Library',
  periods: 'Periods',
  assignments: 'Assignments',
  monitoring: 'Monitoring',
}

interface BreadcrumbItem {
  label: string
  href: string
}

function buildBreadcrumbs(pathname: string): BreadcrumbItem[] {
  const segments = pathname.split('/').filter(Boolean)
  if (segments.length === 0) return [{ label: 'Dashboard', href: '/dashboard' }]

  const crumbs: BreadcrumbItem[] = []
  let path = ''

  for (let i = 0; i < segments.length; i++) {
    const seg = segments[i]
    path += `/${seg}`

    // Skip numeric IDs in the middle of the path (keep last one)
    const isId = /^\d+$/.test(seg)
    if (isId) {
      // Replace the previous crumb's label with "Detail" variant
      if (crumbs.length > 0) {
        crumbs[crumbs.length - 1] = {
          label: crumbs[crumbs.length - 1].label.replace(/s$/, '') + ' Detail',
          href: path,
        }
      }
      continue
    }

    const label = SEGMENT_LABELS[seg] ?? seg.charAt(0).toUpperCase() + seg.slice(1)
    crumbs.push({ label, href: path })
  }

  return crumbs
}

// ---------------------------------------------------------------------------
// Topbar
// ---------------------------------------------------------------------------

function getInitials(name: string | null | undefined): string {
  if (!name) return '?'
  const parts = name.trim().split(/\s+/)
  if (parts.length === 1) return parts[0].charAt(0).toUpperCase()
  return (parts[0].charAt(0) + parts[parts.length - 1].charAt(0)).toUpperCase()
}

export function Topbar() {
  const queryClient = useQueryClient()
  const { data: session } = useSession()
  const user = session?.user
  const pathname = usePathname()
  const crumbs = buildBreadcrumbs(pathname)

  async function handleSignOut() {
    queryClient.clear()
    if (typeof window !== 'undefined') {
      localStorage.removeItem(SELECTED_ACCOUNT_STORAGE_KEY)
    }
    await signOut({ redirectTo: '/login' })
  }

  return (
    <header className="flex h-14 shrink-0 items-center justify-between border-b bg-background px-4 lg:px-6">
      <div className="flex items-center gap-3 min-w-0">
        <MobileSidebar />

        {/* Breadcrumbs */}
        <nav className="flex items-center gap-1 text-sm min-w-0" aria-label="Breadcrumb">
          {crumbs.map((crumb, i) => {
            const isLast = i === crumbs.length - 1
            return (
              <div key={crumb.href} className="flex items-center gap-1 min-w-0">
                {i > 0 && <ChevronRight className="h-3.5 w-3.5 shrink-0 text-muted-foreground/50" />}
                {isLast ? (
                  <span className="truncate font-semibold text-foreground">{crumb.label}</span>
                ) : (
                  <Link
                    href={crumb.href as Route}
                    className="truncate text-muted-foreground hover:text-foreground transition-colors"
                  >
                    {crumb.label}
                  </Link>
                )}
              </div>
            )
          })}
        </nav>
      </div>

      <div className="flex items-center gap-2">
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button
              variant="ghost"
              className="h-9 gap-2 pl-2 pr-2"
              aria-label="User menu"
            >
              <Avatar className="h-7 w-7">
                <AvatarImage src={user?.image ?? undefined} alt={user?.name ?? ''} />
                <AvatarFallback className="text-xs">{getInitials(user?.name)}</AvatarFallback>
              </Avatar>
              <span className="hidden max-w-[150px] truncate text-sm font-medium sm:block">
                {user?.name ?? 'Admin'}
              </span>
              <ChevronDown className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
            </Button>
          </DropdownMenuTrigger>

          <DropdownMenuContent align="end" className="w-56">
            <DropdownMenuLabel className="font-normal">
              <div className="flex flex-col gap-0.5">
                <span className="text-sm font-medium leading-none">{user?.name ?? 'Admin'}</span>
                <span className="text-xs leading-none text-muted-foreground">{user?.email}</span>
              </div>
            </DropdownMenuLabel>
            <DropdownMenuSeparator />
            <DropdownMenuItem
              className="cursor-pointer text-destructive focus:text-destructive"
              onClick={() => { void handleSignOut() }}
            >
              <LogOut className="mr-2 h-4 w-4" />
              Sign out
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </header>
  )
}
