'use client'

/**
 * Client wrapper that reads the current pathname to derive the page title
 * for the Topbar, then renders the main content area.
 *
 * Keeping this as a separate client component means the parent AdminLayout
 * can remain a server component (for the `auth()` call) while still having
 * dynamic title behaviour.
 *
 * Also enforces the route → permission map from `lib/route-permissions.ts`,
 * closing the direct-URL bypass that sidebar-only gating leaves open.
 */

import { usePathname } from 'next/navigation'
import { Lock } from 'lucide-react'
import { Topbar } from '@/components/layout/topbar'
import { usePermissions } from '@/hooks/usePermissions'
import { getRequiredPermission } from '@/lib/route-permissions'

const TITLE_MAP: Record<string, string> = {
  '/dashboard': 'Dashboard',
  '/accounts': 'Accounts',
  '/users': 'Users',
  '/roles': 'Roles',
  '/policies': 'Policies',
  '/delegations': 'Delegations',
  '/packages': 'Packages',
  '/reports': 'BI Reports',
  '/platform-roles': 'Platform Roles',
  '/shared-geography': 'Shared Geography',
  '/sites': 'Org Units',
  '/coverage': 'Coverage Map',
  '/source-mapping': 'Source Mapping',
  '/kpi/definitions': 'KPI Library',
  '/kpi/periods': 'Periods',
  '/kpi/assignments': 'Assignments',
  '/kpi/monitoring': 'Submission Monitoring',
}

function resolveTitle(pathname: string): string {
  if (TITLE_MAP[pathname]) return TITLE_MAP[pathname]

  const prefix = Object.keys(TITLE_MAP).find(
    (key) => key !== '/' && pathname.startsWith(key + '/')
  )
  if (prefix) return TITLE_MAP[prefix]

  return 'GCE Admin'
}

function AccessDenied({ permission }: { permission: string }) {
  return (
    <div className="mx-auto max-w-lg">
      <div className="rounded-xl border border-destructive/30 bg-destructive/5 p-8 text-center">
        <div className="mx-auto flex h-10 w-10 items-center justify-center rounded-full bg-destructive/10 text-destructive">
          <Lock className="h-5 w-5" />
        </div>
        <h2 className="mt-4 text-lg font-semibold tracking-tight text-foreground">
          You don&apos;t have access to this page
        </h2>
        <p className="mt-1 text-sm text-muted-foreground">
          This page requires the <code className="font-mono text-xs">{permission}</code> permission.
          Contact your administrator if you believe you should have access.
        </p>
      </div>
    </div>
  )
}

export function AdminShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname()
  const title = resolveTitle(pathname)
  const { can } = usePermissions()

  const requiredPermission = getRequiredPermission(pathname)
  const isAuthorized = !requiredPermission || can(requiredPermission)

  return (
    <div className="flex min-h-screen flex-1 flex-col">
      <Topbar title={title} />
      <main className="flex-1">
        <div className="mx-auto max-w-7xl space-y-6 p-6">
          {isAuthorized ? children : <AccessDenied permission={requiredPermission!} />}
        </div>
      </main>
    </div>
  )
}
