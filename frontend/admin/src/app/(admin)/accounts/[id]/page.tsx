import type { Metadata } from 'next'
import { AccountDetail } from './account-detail'

interface AccountDetailPageProps {
  params: { id: string }
}

export const metadata: Metadata = {
  title: 'Account Detail',
}

export default function AccountDetailPage({ params }: AccountDetailPageProps) {
  const accountId = parseInt(params.id, 10)
  return <AccountDetail accountId={accountId} />
}
