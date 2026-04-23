'use client'

import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import type { ColumnDef } from '@tanstack/react-table'
import { MoreHorizontal, Pencil } from 'lucide-react'
import { DataTable } from '@/components/shared/data-table'
import { ErrorState } from '@/components/shared/error-state'
import { OrgUnitTypeBadge } from '@/components/shared/org-unit-type-badge'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import { StatusBadge } from '@/components/shared/status-badge'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { api } from '@/lib/api'
import type { SharedGeoUnit } from '@/types/api'
import { EditSharedGeoDialog } from './edit-shared-geo-dialog'


function SharedGeoRowActions({ onEdit }: { onEdit: () => void }) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          variant="ghost"
          size="sm"
          className="h-7 w-7 p-0 data-[state=open]:bg-muted"
          onClick={(e) => e.stopPropagation()}
        >
          <MoreHorizontal className="h-4 w-4" />
          <span className="sr-only">Actions</span>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuItem onClick={(e) => { e.stopPropagation(); onEdit() }}>
          <Pencil className="mr-2 h-4 w-4" />
          Edit
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

function makeColumns(onEdit: (unit: SharedGeoUnit) => void): ColumnDef<SharedGeoUnit, unknown>[] {
  return [
    {
      accessorKey: 'geoUnitName',
      header: 'Name / Code',
      cell: ({ row }) => (
        <div>
          <span className="text-sm font-medium">{row.original.geoUnitName}</span>
          <span className="ml-2 font-mono text-xs text-muted-foreground">{row.original.geoUnitCode}</span>
        </div>
      ),
    },
    {
      accessorKey: 'geoUnitType',
      header: 'Type',
      cell: ({ row }) => <OrgUnitTypeBadge type={row.original.geoUnitType} />,
      meta: { className: 'w-[110px]' },
    },
    {
      accessorKey: 'countryCode',
      header: 'Country',
      cell: ({ row }) =>
        row.original.countryCode ? (
          <span className="font-mono text-xs text-muted-foreground">{row.original.countryCode}</span>
        ) : (
          <span className="text-muted-foreground/40">—</span>
        ),
      meta: { className: 'w-[80px]' },
    },
    {
      accessorKey: 'isActive',
      header: 'Status',
      cell: ({ row }) => <StatusBadge status={row.original.isActive ? 'Active' : 'Inactive'} />,
      meta: { className: 'w-[90px]' },
    },
    {
      id: 'actions',
      header: '',
      cell: ({ row }) => (
        <SharedGeoRowActions onEdit={() => onEdit(row.original)} />
      ),
      meta: { className: 'w-[40px]' },
    },
  ]
}

export function SharedGeoTable() {
  const [search, setSearch] = useState('')
  const [editingUnit, setEditingUnit] = useState<SharedGeoUnit | null>(null)

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['shared-geo-units'],
    queryFn: () => api.sharedGeoUnits.list(),
  })

  const items = useMemo(() => {
    const term = search.trim().toLowerCase()
    if (!term) return data?.items ?? []

    return (data?.items ?? []).filter((item) =>
      [
        item.geoUnitType,
        item.geoUnitCode,
        item.geoUnitName,
        item.countryCode,
      ]
        .filter(Boolean)
        .some((value) => String(value).toLowerCase().includes(term))
    )
  }, [data?.items, search])

  const columns = makeColumns(setEditingUnit)

  return (
    <>
      <div className="space-y-3">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <Input
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="Search type, code, name, country..."
            className="sm:max-w-sm"
          />
          {!isLoading && (
            <span className="text-xs text-muted-foreground">
              {items.length} item{items.length !== 1 ? 's' : ''}
            </span>
          )}
        </div>

        {isError ? (
          <ErrorState title="Failed to load shared geography" error={error} />
        ) : (
          <DataTable columns={columns} data={items} isLoading={isLoading} pageSize={25} />
        )}
      </div>

      <EditSharedGeoDialog
        unit={editingUnit}
        open={!!editingUnit}
        onOpenChange={(open) => { if (!open) setEditingUnit(null) }}
      />
    </>
  )
}
