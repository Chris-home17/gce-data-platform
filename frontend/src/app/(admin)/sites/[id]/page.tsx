import type { Metadata } from 'next'
import { PageHeader } from '@/components/shared/page-header'

interface SiteDetailPageProps {
  params: { id: string }
}

export const metadata: Metadata = { title: 'Site Detail' }

export default function SiteDetailPage({ params }: SiteDetailPageProps) {
  return (
    <div className="space-y-6">
      <PageHeader
        title={`Site ${params.id}`}
        description="Site configuration, assigned users, coverage and KPI assignments."
      />
      <p className="text-muted-foreground">Coming soon — M-04 Site Detail</p>
    </div>
  )
}
