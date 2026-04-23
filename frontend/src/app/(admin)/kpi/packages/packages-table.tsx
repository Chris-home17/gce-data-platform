'use client'

import { useState, useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import { api } from '@/lib/api'
import { DataTable } from '@/components/shared/data-table'
import { ErrorState } from '@/components/shared/error-state'
import { Input } from '@/components/ui/input'
import { packageColumns } from './columns'

export function PackagesTable() {
  const [search, setSearch] = useState('')

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['kpi', 'packages'],
    queryFn: () => api.kpi.packages.list(),
  })

  const filtered = useMemo(() => {
    const items = data?.items ?? []
    if (!search.trim()) return items
    const q = search.trim().toLowerCase()
    return items.filter(
      (p) =>
        p.packageCode.toLowerCase().includes(q) ||
        p.packageName.toLowerCase().includes(q) ||
        (p.tagsRaw ?? '').toLowerCase().includes(q)
    )
  }, [data, search])

  if (isError) {
    return (
      <ErrorState title="Failed to load KPI packages" error={error} />
    )
  }

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-2">
        <Input
          placeholder="Search packages…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="h-8 w-64 text-sm"
        />
        {search && (
          <span className="text-xs text-muted-foreground">
            {filtered.length} result{filtered.length !== 1 ? 's' : ''}
          </span>
        )}
      </div>

      <DataTable
        columns={packageColumns}
        data={filtered}
        isLoading={isLoading}
        pageSize={20}
      />
    </div>
  )
}
