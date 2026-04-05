import type { Metadata } from 'next'
import { PolicyDetail } from './policy-detail'

interface PolicyDetailPageProps {
  params: { id: string }
}

export const metadata: Metadata = { title: 'Policy Detail' }

export default function PolicyDetailPage({ params }: PolicyDetailPageProps) {
  return <PolicyDetail policyId={parseInt(params.id, 10)} />
}
