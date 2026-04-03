import type { Metadata } from 'next'
import { PackageDetail } from './package-detail'

export const metadata: Metadata = { title: 'Package Detail' }

export default function PackageDetailPage({ params }: { params: { id: string } }) {
  return <PackageDetail packageId={Number(params.id)} />
}
