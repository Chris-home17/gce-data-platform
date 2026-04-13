'use client'

import { useState, useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import { api } from '@/lib/api'
import { DataTable } from '@/components/shared/data-table'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { definitionColumns } from './columns'

export function DefinitionsTable() {
  const [categoryFilter, setCategoryFilter] = useState<string>('all')

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['kpi', 'definitions'],
    queryFn: () => api.kpi.definitions.list(),
  })

  const categories = useMemo(() => {
    const cats = new Set(data?.items.map((d) => d.category).filter(Boolean) as string[])
    return Array.from(cats).sort()
  }, [data])

  const filtered = useMemo(() => {
    if (categoryFilter === 'all') return data?.items ?? []
    return (data?.items ?? []).filter((d) => d.category === categoryFilter)
  }, [data, categoryFilter])

  if (isError) {
    return (
      <div className="rounded-md border border-destructive/40 bg-destructive/5 p-6 text-center">
        <p className="text-sm font-medium text-destructive">Failed to load KPI definitions</p>
        <p className="mt-1 text-xs text-muted-foreground">
          {error instanceof Error ? error.message : 'An unexpected error occurred.'}
        </p>
      </div>
    )
  }

  return (
    <div className="space-y-3">
      {/* Category filter */}
      <div className="flex items-center gap-2">
        <span className="text-sm text-muted-foreground">Category:</span>
        <Select value={categoryFilter} onValueChange={setCategoryFilter}>
          <SelectTrigger className="w-44 h-8 text-sm">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All categories</SelectItem>
            {categories.map((cat) => (
              <SelectItem key={cat} value={cat}>{cat}</SelectItem>
            ))}
          </SelectContent>
        </Select>
        {categoryFilter !== 'all' && (
          <span className="text-xs text-muted-foreground">
            {filtered.length} KPI{filtered.length !== 1 ? 's' : ''}
          </span>
        )}
      </div>

      <DataTable
        columns={definitionColumns}
        data={filtered}
        isLoading={isLoading}
        pageSize={20}
      />
    </div>
  )
}
