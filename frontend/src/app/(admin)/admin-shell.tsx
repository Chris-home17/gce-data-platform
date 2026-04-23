'use client'

/**
 * Client wrapper that enforces the route → permission map from
 * `lib/route-permissions.ts`, closing the direct-URL bypass that
 * sidebar-only gating leaves open. The page title is rendered as a
 * breadcrumb trail inside the Topbar itself.
 */

import { usePathname } from 'next/navigation'
import { Lock } from 'lucide-react'
import { Topbar } from '@/components/layout/topbar'
import { usePermissions } from '@/hooks/usePermissions'
import {
  getRequiredPermission,
  hasRequiredPermission,
  type RequiredPermission,
} from '@/lib/route-permissions'

function AccessDenied({ permission }: { permission: RequiredPermission }) {
  // Render either a single code or a " / "-joined list when the route accepts
  // any-of (e.g. kpi.assign OR kpi.admin).
  const label = Array.isArray(permission) ? permission.join(' / ') : permission
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
          This page requires the <code className="font-mono text-xs">{label}</code> permission.
          Contact your administrator if you believe you should have access.
        </p>
      </div>
    </div>
  )
}

export function AdminShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname()
  const { can } = usePermissions()

  const requiredPermission = getRequiredPermission(pathname)
  const isAuthorized = !requiredPermission || hasRequiredPermission(requiredPermission, can)

  return (
    <div className="flex min-h-screen flex-1 flex-col">
      <Topbar />
      <main className="flex-1">
        <div className="mx-auto max-w-7xl space-y-6 p-6">
          {isAuthorized ? children : <AccessDenied permission={requiredPermission!} />}
        </div>
      </main>
    </div>
  )
}
