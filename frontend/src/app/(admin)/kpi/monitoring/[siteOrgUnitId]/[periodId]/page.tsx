import { Suspense } from 'react'
import type { Metadata } from 'next'
import { SitePeriodDetail } from './site-period-detail'

interface PageProps {
  params: { siteOrgUnitId: string; periodId: string }
}

export const metadata: Metadata = { title: 'KPI Submission Detail' }

export default function SitePeriodDetailPage({ params }: PageProps) {
  return (
    <Suspense>
      <SitePeriodDetail
        siteOrgUnitId={parseInt(params.siteOrgUnitId, 10)}
        periodId={parseInt(params.periodId, 10)}
      />
    </Suspense>
  )
}
