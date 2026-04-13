import type { Metadata } from 'next'
import { UserDetail } from './user-detail'

interface UserDetailPageProps {
  params: { id: string }
}

export const metadata: Metadata = { title: 'User Detail' }

export default function UserDetailPage({ params }: UserDetailPageProps) {
  return <UserDetail userId={parseInt(params.id, 10)} />
}
