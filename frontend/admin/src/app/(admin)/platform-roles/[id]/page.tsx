import type { Metadata } from 'next'
import { PlatformRoleDetail } from './platform-role-detail'

interface Props {
  params: { id: string }
}

export const metadata: Metadata = { title: 'Platform Role Detail' }

export default function PlatformRoleDetailPage({ params }: Props) {
  return <PlatformRoleDetail roleId={parseInt(params.id, 10)} />
}
