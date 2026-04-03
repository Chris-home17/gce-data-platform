'use client'

import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Input } from '@/components/ui/input'
import { StatusBadge } from '@/components/shared/status-badge'
import { api } from '@/lib/api'
import type { SharedGeoUnit } from '@/types/api'

const TYPE_COLOURS: Record<SharedGeoUnit['geoUnitType'], string> = {
  Region: 'bg-blue-100 text-blue-700 border-blue-200',
  SubRegion: 'bg-indigo-100 text-indigo-700 border-indigo-200',
  Cluster: 'bg-violet-100 text-violet-700 border-violet-200',
  Country: 'bg-sky-100 text-sky-700 border-sky-200',
}

function TypeBadge({ type }: { type: SharedGeoUnit['geoUnitType'] }) {
  return (
    <span
      className={`inline-flex items-center rounded border px-1.5 py-0.5 text-xs font-medium ${TYPE_COLOURS[type] ?? 'bg-muted text-muted-foreground'}`}
    >
      {type}
    </span>
  )
}

function SharedGeoRow({ unit }: { unit: SharedGeoUnit }) {
  return (
    <tr className="border-b transition-colors hover:bg-muted/40">
      <td className="px-4 py-2.5">
        <div>
          <span className="text-sm font-medium">{unit.geoUnitName}</span>
          <span className="ml-2 font-mono text-xs text-muted-foreground">{unit.geoUnitCode}</span>
        </div>
      </td>

      <td className="w-[110px] px-3 py-2.5">
        <TypeBadge type={unit.geoUnitType} />
      </td>

      <td className="w-[80px] px-3 py-2.5">
        {unit.countryCode ? (
          <span className="font-mono text-xs text-muted-foreground">{unit.countryCode}</span>
        ) : (
          <span className="text-muted-foreground/40">—</span>
        )}
      </td>

      <td className="w-[90px] py-2.5 pl-3 pr-4">
        <StatusBadge status={unit.isActive ? 'Active' : 'Inactive'} />
      </td>
    </tr>
  )
}

function SkeletonRows() {
  return (
    <>
      {Array.from({ length: 6 }).map((_, i) => (
        <tr key={i} className="border-b">
          <td className="px-4 py-3">
            <div className="h-4 w-48 animate-pulse rounded bg-muted" />
          </td>
          <td className="px-3 py-3">
            <div className="h-4 w-16 animate-pulse rounded bg-muted" />
          </td>
          <td className="px-3 py-3">
            <div className="h-4 w-8 animate-pulse rounded bg-muted" />
          </td>
          <td className="px-3 py-3">
            <div className="h-5 w-14 animate-pulse rounded bg-muted" />
          </td>
        </tr>
      ))}
    </>
  )
}

export function SharedGeoTable() {
  const [search, setSearch] = useState('')

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

  return (
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
        <div className="rounded-md border border-destructive/40 bg-destructive/5 p-6 text-center">
          <p className="text-sm font-medium text-destructive">Failed to load shared geography</p>
          <p className="mt-1 text-xs text-muted-foreground">
            {error instanceof Error ? error.message : 'An unexpected error occurred.'}
          </p>
        </div>
      ) : (
        <div className="rounded-md border">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b bg-muted/50">
                <th className="px-4 py-2.5 text-left text-xs font-medium text-muted-foreground">
                  Name / Code
                </th>
                <th className="w-[110px] px-3 py-2.5 text-left text-xs font-medium text-muted-foreground">
                  Type
                </th>
                <th className="w-[80px] px-3 py-2.5 text-left text-xs font-medium text-muted-foreground">
                  Country
                </th>
                <th className="w-[90px] px-3 py-2.5 text-left text-xs font-medium text-muted-foreground">
                  Status
                </th>
              </tr>
            </thead>
            <tbody>
              {isLoading ? (
                <SkeletonRows />
              ) : items.length === 0 ? (
                <tr>
                  <td colSpan={4} className="py-10 text-center text-sm text-muted-foreground">
                    No shared geography items found.
                  </td>
                </tr>
              ) : (
                items.map((unit) => <SharedGeoRow key={unit.sharedGeoUnitId} unit={unit} />)
              )}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
