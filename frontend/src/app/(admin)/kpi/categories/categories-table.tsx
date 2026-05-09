'use client'

import { useState } from 'react'
import type { ColumnDef } from '@tanstack/react-table'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { CheckCircle, MoreHorizontal, Pencil, XCircle } from 'lucide-react'
import { api } from '@/lib/api'
import type { KpiCategory } from '@/types/api'
import { DataTable } from '@/components/shared/data-table'
import { ErrorState } from '@/components/shared/error-state'
import { StatusBadge } from '@/components/shared/status-badge'
import { Button } from '@/components/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { EditCategorySheet } from './edit-category-sheet'

function CategoryActions({ category }: { category: KpiCategory }) {
  const [editOpen, setEditOpen] = useState(false)
  const queryClient = useQueryClient()

  const toggleMutation = useMutation({
    mutationFn: () => api.kpi.categories.setActive(category.kpiCategoryId, !category.isActive),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['kpi', 'categories'] })
      toast.success(`Category "${category.code}" ${category.isActive ? 'deactivated' : 'activated'}.`)
    },
    onError: (err: Error) => toast.error(err.message ?? 'Failed to update category status.'),
  })

  // Deactivating a category that's still in use is risky for two reasons:
  //   - existing KPI definitions FK'd to it stay assigned (display still works)
  //   - new KPI definitions can no longer pick it
  // We surface the usage counter via a confirm prompt before disabling.
  const inUse = category.definitionCount + category.categoryWeightCount > 0

  function handleDeactivate() {
    if (inUse) {
      const msg =
        `Deactivate "${category.name}"?\n\n` +
        `This category is in use by ${category.definitionCount} KPI definition${category.definitionCount !== 1 ? 's' : ''}` +
        (category.categoryWeightCount > 0
          ? ` and ${category.categoryWeightCount} account weight rule${category.categoryWeightCount !== 1 ? 's' : ''}`
          : '') +
        `. Existing KPIs stay linked, but new KPIs won't be able to pick this category until it's reactivated.`
      if (!window.confirm(msg)) return
    }
    toggleMutation.mutate()
  }

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
          {category.isActive ? (
            <DropdownMenuItem
              className="text-destructive focus:text-destructive"
              onClick={(e) => { e.stopPropagation(); handleDeactivate() }}
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

      <EditCategorySheet
        category={category}
        open={editOpen}
        onClose={() => setEditOpen(false)}
      />
    </>
  )
}

const columns: ColumnDef<KpiCategory, unknown>[] = [
  {
    accessorKey: 'code',
    header: 'Code',
    cell: ({ row }) => (
      <span className="font-mono text-sm font-medium">{row.original.code}</span>
    ),
    meta: { className: 'w-24' },
  },
  {
    accessorKey: 'name',
    header: 'Name',
    cell: ({ row }) => <span className="font-medium">{row.original.name}</span>,
    meta: { className: 'w-48' },
  },
  {
    accessorKey: 'description',
    header: 'Description',
    cell: ({ row }) => (
      <span className="text-sm text-muted-foreground">
        {row.original.description ?? '—'}
      </span>
    ),
  },
  {
    accessorKey: 'definitionCount',
    header: 'KPIs',
    cell: ({ row }) => (
      <span className="tabular-nums text-sm">{row.original.definitionCount}</span>
    ),
    meta: { className: 'w-20 text-right', headerClassName: 'text-right' },
  },
  {
    accessorKey: 'categoryWeightCount',
    header: 'Weights',
    cell: ({ row }) => (
      <span className="tabular-nums text-sm">{row.original.categoryWeightCount}</span>
    ),
    meta: { className: 'w-24 text-right', headerClassName: 'text-right' },
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
    cell: ({ row }) => <CategoryActions category={row.original} />,
    meta: { className: 'w-[40px]' },
  },
]

export function CategoriesTable() {
  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['kpi', 'categories'],
    // includeInactive=true so admins can re-activate without losing them from view.
    queryFn: () => api.kpi.categories.list({ includeInactive: true }),
  })

  if (isError) {
    return <ErrorState title="Failed to load KPI categories" error={error} />
  }

  return (
    <DataTable
      columns={columns}
      data={data?.items ?? []}
      isLoading={isLoading}
      pageSize={20}
    />
  )
}
