'use client'

import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import type { ColumnDef } from '@tanstack/react-table'
import { CheckCircle, ExternalLink, MoreHorizontal, Pencil, XCircle } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { DataTable } from '@/components/shared/data-table'
import { StatusBadge } from '@/components/shared/status-badge'
import { EditReportDialog } from './edit-report-dialog'
import { api } from '@/lib/api'
import type { BiReport } from '@/types/api'

function ReportRowActions({ report }: { report: BiReport }) {
  const [editOpen, setEditOpen] = useState(false)
  const queryClient = useQueryClient()

  const toggleMutation = useMutation({
    mutationFn: () => api.reports.setActive(report.biReportId, !report.isActive),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['reports'] }),
  })

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button
            variant="ghost"
            size="sm"
            className="h-7 w-7 p-0 data-[state=open]:bg-muted"
            disabled={toggleMutation.isPending}
            onClick={(e) => e.stopPropagation()}
          >
            <MoreHorizontal className="h-4 w-4" />
            <span className="sr-only">Actions</span>
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          {report.reportUri && (
            <DropdownMenuItem onClick={(e) => { e.stopPropagation(); window.open(report.reportUri!, '_blank', 'noopener,noreferrer') }}>
              <ExternalLink className="mr-2 h-4 w-4" />
              Open Report
            </DropdownMenuItem>
          )}
          <DropdownMenuItem onClick={(e) => { e.stopPropagation(); setEditOpen(true) }}>
            <Pencil className="mr-2 h-4 w-4" />
            Edit
          </DropdownMenuItem>
          <DropdownMenuSeparator />
          {report.isActive ? (
            <DropdownMenuItem
              className="text-destructive focus:text-destructive"
              onClick={(e) => { e.stopPropagation(); toggleMutation.mutate() }}
            >
              <XCircle className="mr-2 h-4 w-4" />
              Deactivate
            </DropdownMenuItem>
          ) : (
            <DropdownMenuItem onClick={(e) => { e.stopPropagation(); toggleMutation.mutate() }}>
              <CheckCircle className="mr-2 h-4 w-4 text-success" />
              Activate
            </DropdownMenuItem>
          )}
        </DropdownMenuContent>
      </DropdownMenu>

      <EditReportDialog report={report} open={editOpen} onOpenChange={setEditOpen} />
    </>
  )
}

const columns: ColumnDef<BiReport, unknown>[] = [
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
        <span className="font-mono text-xs text-muted-foreground truncate max-w-[260px] block">
          {row.original.reportUri}
        </span>
      ) : (
        <span className="text-muted-foreground/40 text-xs">—</span>
      ),
  },
  {
    accessorKey: 'packageList',
    header: 'Packages',
    cell: ({ row }) => {
      const list = row.original.packageList
      if (!list) return <span className="text-muted-foreground/40 text-xs">none</span>
      return (
        <div className="flex flex-wrap gap-1">
          {list.split(', ').map((code) => (
            <Badge key={code} variant="secondary" className="font-mono text-xs">{code}</Badge>
          ))}
        </div>
      )
    },
  },
  {
    accessorKey: 'isActive',
    header: 'Status',
    cell: ({ row }) => (
      <StatusBadge status={row.original.isActive ? 'Active' : 'Inactive'} />
    ),
    meta: { className: 'w-[100px]' },
  },
  {
    id: 'actions',
    header: '',
    cell: ({ row }) => <ReportRowActions report={row.original} />,
    meta: { className: 'w-[40px]' },
  },
]

export function ReportsTable() {
  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['reports'],
    queryFn: () => api.reports.list(),
  })

  if (isError) {
    return (
      <div className="rounded-md border border-destructive/40 bg-destructive/5 p-6 text-center">
        <p className="text-sm font-medium text-destructive">Failed to load reports</p>
        <p className="mt-1 text-xs text-muted-foreground">
          {error instanceof Error ? error.message : 'An unexpected error occurred.'}
        </p>
      </div>
    )
  }

  return (
    <DataTable
      columns={columns}
      data={data?.items ?? []}
      isLoading={isLoading}
    />
  )
}
