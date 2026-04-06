'use client'

import { useSession } from 'next-auth/react'
import { PERMISSIONS } from '@/types/api'

export function usePermissions() {
  const { data: session } = useSession()
  const s = session as typeof session & { permissions?: string[]; userId?: number }
  const permissions: string[] = s?.permissions ?? []
  const userId: number | undefined = s?.userId

  /** Returns true if the user has the given permission or is a Super Admin */
  const can = (permission: string): boolean =>
    permissions.includes(PERMISSIONS.SUPER_ADMIN) || permissions.includes(permission)

  const isSuperAdmin = permissions.includes(PERMISSIONS.SUPER_ADMIN)

  return { permissions, can, isSuperAdmin, userId }
}
