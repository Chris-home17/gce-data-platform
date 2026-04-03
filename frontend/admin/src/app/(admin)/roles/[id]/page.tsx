import type { Metadata } from 'next'
import { RoleDetail } from './role-detail'

interface RoleDetailPageProps {
  params: { id: string }
}

export const metadata: Metadata = { title: 'Role Detail' }

export default function RoleDetailPage({ params }: RoleDetailPageProps) {
  return <RoleDetail roleId={parseInt(params.id, 10)} />
}
