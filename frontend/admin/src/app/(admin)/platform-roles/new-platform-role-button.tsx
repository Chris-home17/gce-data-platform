'use client'

import { useRouter } from 'next/navigation'
import { Plus } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { PermissionGate } from '@/components/shared/permission-gate'
import { PERMISSIONS } from '@/types/api'

export function NewPlatformRoleButton() {
  const router = useRouter()
  return (
    <PermissionGate permission={PERMISSIONS.PLATFORM_ROLES_MANAGE}>
      <Button size="sm" onClick={() => router.push('/platform-roles/new')}>
        <Plus className="mr-1.5 h-4 w-4" />
        New Platform Role
      </Button>
    </PermissionGate>
  )
}
