'use client'

import { useQuery } from '@tanstack/react-query'
import { useRouter } from 'next/navigation'
import type { ColumnDef } from '@tanstack/react-table'
import { ArrowLeft, FileText } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { DataTable } from '@/components/shared/data-table'
import { StatusBadge } from '@/components/shared/status-badge'
import { api } from '@/lib/api'
import type { BiReport } from '@/types/api'
import { AssignReportDialog } from './assign-report-dialog'
import { NewReportForPackageDialog } from './new-report-for-package-dialog'

const reportColumns: ColumnDef<BiReport, unknown>[] = [
  {
    accessorKey: 'reportCode',
    header: 'Code',
    cell: ({ row }) => (
      <span className="font-mono text-sm font-medium">{row.original.reportCode}</span>
    ),
    meta: { className: 'w-[160px]' },
  },
  {
    accessorKey: 'reportName',
    header: 'Name',
    cell: ({ row }) => <span className="font-medium">{row.original.reportName}</span>,
  },
  {
    accessorKey: 'reportUri',
    header: 'URI',
    cell: ({ row }) =>
      row.original.reportUri ? (
        <span className="font-mono text-xs text-muted-foreground truncate max-w-[300px] block">
          {row.original.reportUri}
        </span>
      ) : (
        <span className="text-muted-foreground/40">—</span>
      ),
  },
  {
    accessorKey: 'packageCount',
    header: 'In Packages',
    cell: ({ row }) => (
      <span className="tabular-nums text-sm text-muted-foreground">{row.original.packageCount}</span>
    ),
    meta: { className: 'w-[110px] text-right', headerClassName: 'text-right' },
  },
  {
    accessorKey: 'isActive',
    header: 'Status',
    cell: ({ row }) => (
      <StatusBadge status={row.original.isActive ? 'Active' : 'Inactive'} />
    ),
    meta: { className: 'w-[100px]' },
  },
]

export function PackageDetail({ packageId }: { packageId: number }) {
  const router = useRouter()

  const { data: pkg, isLoading: pkgLoading } = useQuery({
    queryKey: ['packages', packageId],
    queryFn: () => api.packages.get(packageId),
  })

  const { data: reports, isLoading: reportsLoading } = useQuery({
    queryKey: ['packages', packageId, 'reports'],
    queryFn: () => api.packages.reports(packageId),
    enabled: !!pkg,
  })

  if (pkgLoading) {
    return (
      <div className="space-y-6">
        <div className="h-8 w-48 rounded bg-muted animate-pulse" />
        <div className="h-24 rounded-lg bg-muted animate-pulse" />
      </div>
    )
  }

  if (!pkg) {
    return (
      <div className="rounded-md border border-destructive/40 bg-destructive/5 p-6 text-center">
        <p className="text-sm font-medium text-destructive">Package not found.</p>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Back + header */}
      <div>
        <Button variant="ghost" size="sm" className="-ml-2 mb-3" onClick={() => router.push('/packages')}>
          <ArrowLeft className="mr-1.5 h-4 w-4" />
          Packages
        </Button>

        <div className="flex items-start justify-between gap-4">
          <div>
            <div className="flex items-center gap-2 flex-wrap">
              <h1 className="text-2xl font-semibold">{pkg.packageName}</h1>
              <Badge variant="outline" className="font-mono text-sm">{pkg.packageCode}</Badge>
              {pkg.packageGroup && (
                <Badge variant="secondary" className="text-xs">{pkg.packageGroup}</Badge>
              )}
              <StatusBadge status={pkg.isActive ? 'Active' : 'Inactive'} />
            </div>
          </div>
        </div>
      </div>

      {/* Stat card */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-1 max-w-xs">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">Reports</CardTitle>
            <FileText className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <p className="text-2xl font-semibold tabular-nums">{pkg.reportCount}</p>
          </CardContent>
        </Card>
      </div>

      {/* Reports table */}
      <div>
        <div className="flex items-center justify-between mb-3">
          <h2 className="text-base font-semibold">Reports in this Package</h2>
          <div className="flex items-center gap-2">
            <AssignReportDialog packageId={packageId} packageCode={pkg.packageCode} />
            <NewReportForPackageDialog packageId={packageId} packageCode={pkg.packageCode} />
          </div>
        </div>
        <DataTable
          columns={reportColumns}
          data={reports?.items ?? []}
          isLoading={reportsLoading}
        />
      </div>
    </div>
  )
}
