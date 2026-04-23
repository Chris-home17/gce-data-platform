'use client'

import { useQuery } from '@tanstack/react-query'
import type { ColumnDef } from '@tanstack/react-table'
import { useRouter } from 'next/navigation'
import { Badge } from '@/components/ui/badge'
import { DataTable } from '@/components/shared/data-table'
import { api } from '@/lib/api'
import type { CoverageSummary } from '@/types/api'

function GapBadge({ status }: { status: string }) {
  if (status === 'OK') {
    return <Badge variant="outline" className="text-xs border-success-border bg-success-muted text-success-muted-foreground">OK</Badge>
  }
  if (status === 'Sites without packages') {
    return <Badge variant="outline" className="text-xs border-warning-border bg-warning-muted text-warning-muted-foreground">Sites w/o packages</Badge>
  }
  if (status === 'Packages without sites') {
    return <Badge variant="outline" className="text-xs border-warning-border bg-warning-muted text-warning-muted-foreground">Packages w/o sites</Badge>
  }
  return <Badge variant="outline" className="text-xs text-destructive border-destructive/40 bg-destructive/5">{status}</Badge>
}

const columns: ColumnDef<CoverageSummary, unknown>[] = [
  {
    accessorKey: 'upn',
    header: 'User (UPN)',
    cell: ({ row }) => (
      <span className="font-mono text-sm">{row.original.upn}</span>
    ),
  },
  {
    accessorKey: 'accountCount',
    header: 'Accounts',
    cell: ({ row }) => (
      <span className="tabular-nums text-sm">{row.original.accountCount}</span>
    ),
    meta: { className: 'w-[100px] text-right', headerClassName: 'text-right' },
  },
  {
    accessorKey: 'siteCount',
    header: 'Sites',
    cell: ({ row }) => (
      <span className="tabular-nums text-sm">{row.original.siteCount}</span>
    ),
    meta: { className: 'w-[80px] text-right', headerClassName: 'text-right' },
  },
  {
    accessorKey: 'packageCount',
    header: 'Packages',
    cell: ({ row }) => (
      <span className="tabular-nums text-sm">{row.original.packageCount}</span>
    ),
    meta: { className: 'w-[100px] text-right', headerClassName: 'text-right' },
  },
  {
    accessorKey: 'reportCount',
    header: 'Reports',
    cell: ({ row }) => (
      <span className="tabular-nums text-sm">{row.original.reportCount}</span>
    ),
    meta: { className: 'w-[90px] text-right', headerClassName: 'text-right' },
  },
  {
    accessorKey: 'gapStatus',
    header: 'Gap Status',
    cell: ({ row }) => <GapBadge status={row.original.gapStatus} />,
    meta: { className: 'w-[160px]' },
  },
]

interface CoverageTableProps {
  gapsOnly?: boolean
}

export function CoverageTable({ gapsOnly = false }: CoverageTableProps) {
  const router = useRouter()

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['coverage'],
    queryFn: () => api.coverage.list(),
    refetchOnMount: 'always',
    refetchOnWindowFocus: true,
  })

  const items = gapsOnly
    ? (data?.items ?? []).filter((u) => u.gapStatus !== 'OK')
    : (data?.items ?? [])

  if (isError) {
    return (
      <div className="rounded-md border border-destructive/40 bg-destructive/5 p-6 text-center">
        <p className="text-sm font-medium text-destructive">Failed to load coverage data</p>
        <p className="mt-1 text-xs text-muted-foreground">
          {error instanceof Error ? error.message : 'An unexpected error occurred.'}
        </p>
      </div>
    )
  }

  return (
    <DataTable
      columns={columns}
      data={items}
      isLoading={isLoading}
      onRowClick={(user) => router.push(`/users/${user.userId}`)}
    />
  )
}

export function CoverageSummaryStats() {
  const { data, isLoading } = useQuery({
    queryKey: ['coverage'],
    queryFn: () => api.coverage.list(),
    refetchOnMount: 'always',
    refetchOnWindowFocus: true,
  })

  if (isLoading || !data) {
    return (
      <div className="grid grid-cols-3 gap-4">
        {Array.from({ length: 3 }).map((_, i) => (
          <div key={i} className="rounded-lg border p-4">
            <div className="h-3 w-20 rounded bg-muted animate-pulse mb-2" />
            <div className="h-7 w-10 rounded bg-muted animate-pulse" />
          </div>
        ))}
      </div>
    )
  }

  const total = data.items.length
  const gaps = data.items.filter((u) => u.gapStatus !== 'OK').length
  const ok = total - gaps

  return (
    <div className="grid grid-cols-3 gap-4">
      <div className="rounded-lg border p-4">
        <p className="text-xs text-muted-foreground uppercase tracking-wide">Total Users</p>
        <p className="mt-1 text-2xl font-semibold tabular-nums">{total}</p>
      </div>
      <div className="rounded-lg border p-4">
        <p className="text-xs text-muted-foreground uppercase tracking-wide">No Gaps</p>
        <p className="mt-1 text-2xl font-semibold tabular-nums text-success">{ok}</p>
      </div>
      <div className={`rounded-lg border p-4 ${gaps > 0 ? 'border-warning-border bg-warning-muted/50' : ''}`}>
        <p className="text-xs text-muted-foreground uppercase tracking-wide">With Gaps</p>
        <p className={`mt-1 text-2xl font-semibold tabular-nums ${gaps > 0 ? 'text-warning-muted-foreground' : 'text-muted-foreground'}`}>{gaps}</p>
      </div>
    </div>
  )
}
