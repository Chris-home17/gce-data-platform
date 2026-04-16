import type { Metadata } from 'next'
import { PageHeader } from '@/components/shared/page-header'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { CoverageTable, CoverageSummaryStats } from './coverage-table'

export const metadata: Metadata = { title: 'Coverage Map' }

export default function CoveragePage() {
  return (
    <div className="space-y-6">
      <PageHeader
        title="Coverage Map"
        description="Per-user access coverage — sites, packages and reports each user can reach, and where there are gaps."
      />

      <CoverageSummaryStats />

      <Tabs defaultValue="all">
        <TabsList>
          <TabsTrigger value="all">All Users (M-11)</TabsTrigger>
          <TabsTrigger value="gaps">Access Gaps (M-12)</TabsTrigger>
        </TabsList>
        <TabsContent value="all" className="mt-4">
          <CoverageTable />
        </TabsContent>
        <TabsContent value="gaps" className="mt-4">
          <CoverageTable gapsOnly />
        </TabsContent>
      </Tabs>
    </div>
  )
}
