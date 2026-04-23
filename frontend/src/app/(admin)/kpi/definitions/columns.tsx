'use client'

import { useState } from 'react'
import type { ColumnDef } from '@tanstack/react-table'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { MoreHorizontal, Pencil, CheckCircle, XCircle } from 'lucide-react'
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
import { EditDefinitionSheet } from './edit-definition-sheet'
import { api } from '@/lib/api'
import type { KpiDefinition } from '@/types/api'

function parseTagsRaw(raw: string | null): Array<{ id: number; name: string }> {
  if (!raw) return []
  return raw.split('|').map((part) => {
    const [id, ...rest] = part.split(':')
    return { id: parseInt(id), name: rest.join(':') }
  })
}

function DefinitionActions({ kpi }: { kpi: KpiDefinition }) {
  const [editOpen, setEditOpen] = useState(false)
  const queryClient = useQueryClient()

  const toggleMutation = useMutation({
    mutationFn: () => api.kpi.definitions.setActive(kpi.kpiId, !kpi.isActive),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['kpi', 'definitions'] }),
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
          <DropdownMenuItem
            onClick={(e) => { e.stopPropagation(); setEditOpen(true) }}
          >
            <Pencil className="mr-2 h-4 w-4" />
            Edit
          </DropdownMenuItem>
          <DropdownMenuSeparator />
          {kpi.isActive ? (
            <DropdownMenuItem
              className="text-destructive focus:text-destructive"
              onClick={(e) => { e.stopPropagation(); toggleMutation.mutate() }}
            >
              <XCircle className="mr-2 h-4 w-4" />
              Deactivate
            </DropdownMenuItem>
          ) : (
            <DropdownMenuItem
              onClick={(e) => { e.stopPropagation(); toggleMutation.mutate() }}
            >
              <CheckCircle className="mr-2 h-4 w-4 text-success" />
              Activate
            </DropdownMenuItem>
          )}
        </DropdownMenuContent>
      </DropdownMenu>

      <EditDefinitionSheet
        kpi={kpi}
        open={editOpen}
        onClose={() => setEditOpen(false)}
      />
    </>
  )
}

export const definitionColumns: ColumnDef<KpiDefinition, unknown>[] = [
  {
    accessorKey: 'kpiCode',
    header: 'Code',
    cell: ({ row }) => (
      <span className="font-mono text-sm font-medium">{row.original.kpiCode}</span>
    ),
    meta: { className: 'w-24' },
  },
  {
    accessorKey: 'kpiName',
    header: 'Name',
    cell: ({ row }) => (
      <div>
        <p className="font-medium">{row.original.kpiName}</p>
      </div>
    ),
  },
  {
    accessorKey: 'category',
    header: 'Category',
    cell: ({ row }) => (
      <span className="text-sm">{row.original.category ?? '—'}</span>
    ),
    meta: { className: 'w-36' },
  },
  {
    accessorKey: 'dataType',
    header: 'Type',
    cell: ({ row }) => (
      <span className="text-sm text-muted-foreground">{row.original.dataType}</span>
    ),
    meta: { className: 'w-28' },
  },
  {
    accessorKey: 'unit',
    header: 'Unit',
    cell: ({ row }) => (
      <span className="text-sm text-muted-foreground">{row.original.unit ?? '—'}</span>
    ),
    meta: { className: 'w-28' },
  },
  {
    accessorKey: 'thresholdDirection',
    header: 'Direction',
    cell: ({ row }) => {
      const dir = row.original.thresholdDirection
      if (!dir) return <span className="text-muted-foreground">—</span>
      return (
        <span className={`text-sm font-medium ${dir === 'Higher' ? 'text-success' : 'text-info'}`}>
          {dir === 'Higher' ? '↑ Higher' : '↓ Lower'}
        </span>
      )
    },
    meta: { className: 'w-28' },
  },
  {
    accessorKey: 'collectionType',
    header: 'Collection',
    cell: ({ row }) => (
      <span className="text-sm text-muted-foreground">{row.original.collectionType}</span>
    ),
    meta: { className: 'w-28' },
  },
  {
    id: 'tags',
    header: 'Tags',
    cell: ({ row }) => {
      const tags = parseTagsRaw(row.original.tagsRaw)
      if (tags.length === 0) return <span className="text-muted-foreground text-sm">—</span>
      const visible = tags.slice(0, 2)
      const overflow = tags.length - visible.length
      return (
        <div className="flex flex-wrap gap-1">
          {visible.map((t) => (
            <Badge key={t.id} variant="secondary" className="text-xs">{t.name}</Badge>
          ))}
          {overflow > 0 && (
            <Badge variant="outline" className="text-xs">+{overflow}</Badge>
          )}
        </div>
      )
    },
    meta: { className: 'w-48' },
  },
  {
    accessorKey: 'assignmentCount',
    header: 'Assignments',
    cell: ({ row }) => (
      <span className="tabular-nums text-sm">{row.original.assignmentCount}</span>
    ),
    meta: { className: 'w-28 text-right', headerClassName: 'text-right' },
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
    cell: ({ row }) => <DefinitionActions kpi={row.original} />,
    meta: { className: 'w-[40px]' },
  },
]
