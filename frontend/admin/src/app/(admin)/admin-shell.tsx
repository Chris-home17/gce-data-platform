'use client'

/**
 * Client wrapper that reads the current pathname to derive the page title
 * for the Topbar, then renders the main content area.
 *
 * Keeping this as a separate client component means the parent AdminLayout
 * can remain a server component (for the `auth()` call) while still having
 * dynamic title behaviour.
 */

import { usePathname } from 'next/navigation'
import { Topbar } from '@/components/layout/topbar'

const TITLE_MAP: Record<string, string> = {
  '/accounts': 'Accounts',
  '/users': 'Users',
  '/roles': 'Roles',
  '/policies': 'Policies',
  '/delegations': 'Delegations',
  '/packages': 'Packages',
  '/reports': 'BI Reports',
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
  // Exact match first
  if (TITLE_MAP[pathname]) return TITLE_MAP[pathname]

  // Prefix match for detail pages (e.g. /accounts/123 → "Accounts")
  const prefix = Object.keys(TITLE_MAP).find(
    (key) => key !== '/' && pathname.startsWith(key + '/')
  )
  if (prefix) return TITLE_MAP[prefix]

  return 'GCE Admin'
}

export function AdminShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname()
  const title = resolveTitle(pathname)

  return (
    <div className="flex min-h-screen flex-1 flex-col">
      <Topbar title={title} />
      <main className="flex-1">
        <div className="mx-auto max-w-7xl space-y-6 p-6">{children}</div>
      </main>
    </div>
  )
}
