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
import { StatusBadge } from '@/components/shared/status-badge'
import { EditTagDialog } from './edit-tag-dialog'
import { api } from '@/lib/api'
import type { Tag } from '@/types/api'

function TagActions({ tag }: { tag: Tag }) {
  const [editOpen, setEditOpen] = useState(false)
  const queryClient = useQueryClient()

  const toggleMutation = useMutation({
    mutationFn: () => api.tags.setActive(tag.tagId, !tag.isActive),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['tags'] }),
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
          <DropdownMenuItem onClick={(e) => { e.stopPropagation(); setEditOpen(true) }}>
            <Pencil className="mr-2 h-4 w-4" />
            Edit
          </DropdownMenuItem>
          <DropdownMenuSeparator />
          {tag.isActive ? (
            <DropdownMenuItem
              className="text-destructive focus:text-destructive"
              onClick={(e) => { e.stopPropagation(); toggleMutation.mutate() }}
            >
              <XCircle className="mr-2 h-4 w-4" />
              Deactivate
            </DropdownMenuItem>
          ) : (
            <DropdownMenuItem onClick={(e) => { e.stopPropagation(); toggleMutation.mutate() }}>
              <CheckCircle className="mr-2 h-4 w-4 text-emerald-600" />
              Activate
            </DropdownMenuItem>
          )}
        </DropdownMenuContent>
      </DropdownMenu>

      <EditTagDialog tag={tag} open={editOpen} onClose={() => setEditOpen(false)} />
    </>
  )
}

export const tagColumns: ColumnDef<Tag, unknown>[] = [
  {
    accessorKey: 'tagCode',
    header: 'Code',
    cell: ({ row }) => (
      <span className="font-mono text-sm font-medium">{row.original.tagCode}</span>
    ),
    meta: { className: 'w-36' },
  },
  {
    accessorKey: 'tagName',
    header: 'Name',
    cell: ({ row }) => <span className="font-medium">{row.original.tagName}</span>,
  },
  {
    accessorKey: 'tagDescription',
    header: 'Description',
    cell: ({ row }) => (
      <span className="text-sm text-muted-foreground">{row.original.tagDescription ?? '—'}</span>
    ),
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
    cell: ({ row }) => <TagActions tag={row.original} />,
    meta: { className: 'w-[40px]' },
  },
]
