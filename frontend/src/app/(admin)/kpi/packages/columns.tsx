'use client'

import { useState } from 'react'
import type { ColumnDef } from '@tanstack/react-table'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { MoreHorizontal, Pencil, CheckCircle, XCircle, ListChecks } from 'lucide-react'
import { Button } from '@/components/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { Badge } from '@/components/ui/badge'
import { StatusBadge } from '@/components/shared/status-badge'
import { EditPackageDialog } from './edit-package-dialog'
import { PackageDetailSheet } from './package-detail-sheet'
import { api } from '@/lib/api'
import { parsePackageTags } from '@/types/api'
import type { KpiPackage } from '@/types/api'

function PackageActions({ pkg }: { pkg: KpiPackage }) {
  const [editOpen, setEditOpen] = useState(false)
  const [detailOpen, setDetailOpen] = useState(false)
  const queryClient = useQueryClient()

  const toggleMutation = useMutation({
    mutationFn: () => api.kpi.packages.setActive(pkg.kpiPackageId, !pkg.isActive),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['kpi', 'packages'] }),
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
          <DropdownMenuItem onClick={(e) => { e.stopPropagation(); setDetailOpen(true) }}>
            <ListChecks className="mr-2 h-4 w-4" />
            Manage KPIs
          </DropdownMenuItem>
          <DropdownMenuItem onClick={(e) => { e.stopPropagation(); setEditOpen(true) }}>
            <Pencil className="mr-2 h-4 w-4" />
            Edit
          </DropdownMenuItem>
          <DropdownMenuSeparator />
          {pkg.isActive ? (
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

      <EditPackageDialog pkg={pkg} open={editOpen} onClose={() => setEditOpen(false)} />
      <PackageDetailSheet pkg={pkg} open={detailOpen} onClose={() => setDetailOpen(false)} />
    </>
  )
}

export const packageColumns: ColumnDef<KpiPackage, unknown>[] = [
  {
    accessorKey: 'packageCode',
    header: 'Code',
    cell: ({ row }) => (
      <span className="font-mono text-sm font-medium">{row.original.packageCode}</span>
    ),
    meta: { className: 'w-36' },
  },
  {
    accessorKey: 'packageName',
    header: 'Name',
    cell: ({ row }) => <span className="font-medium">{row.original.packageName}</span>,
  },
  {
    accessorKey: 'tagsRaw',
    header: 'Tags',
    cell: ({ row }) => {
      const tags = parsePackageTags(row.original.tagsRaw)
      return tags.length > 0 ? (
        <div className="flex flex-wrap gap-1">
          {tags.map((t) => (
            <Badge key={t.tagId} variant="secondary" className="text-xs">{t.tagName}</Badge>
          ))}
        </div>
      ) : (
        <span className="text-muted-foreground text-sm">—</span>
      )
    },
    meta: { className: 'w-48' },
  },
  {
    accessorKey: 'kpiCount',
    header: 'KPIs',
    cell: ({ row }) => (
      <span className="tabular-nums text-sm">{row.original.kpiCount}</span>
    ),
    meta: { className: 'w-20 text-right', headerClassName: 'text-right' },
  },
  {
    accessorKey: 'isActive',
    header: 'Status',
    cell: ({ row }) => <StatusBadge status={row.original.isActive ? 'Active' : 'Inactive'} />,
    meta: { className: 'w-24' },
  },
  {
    id: 'actions',
    header: '',
    cell: ({ row }) => <PackageActions pkg={row.original} />,
    meta: { className: 'w-[40px]' },
  },
]
