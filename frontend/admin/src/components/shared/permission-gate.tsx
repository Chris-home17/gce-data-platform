'use client'

import { usePermissions } from '@/hooks/usePermissions'

interface PermissionGateProps {
  permission: string
  children: React.ReactNode
  /** Rendered when the user lacks permission. Defaults to null (hidden). */
  fallback?: React.ReactNode
}

/**
 * Renders children only when the current user holds the given permission
 * (or is a Super Admin). Use this to gate action buttons, dialogs, and
 * other write-oriented UI elements.
 *
 * @example
 * <PermissionGate permission={PERMISSIONS.ACCOUNTS_MANAGE}>
 *   <Button onClick={onCreate}>Create Account</Button>
 * </PermissionGate>
 */
export function PermissionGate({ permission, children, fallback = null }: PermissionGateProps) {
  const { can } = usePermissions()
  return can(permission) ? <>{children}</> : <>{fallback}</>
}
