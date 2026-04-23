'use client'

import { useState, useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import { api } from '@/lib/api'
import { DataTable } from '@/components/shared/data-table'
import { ErrorState } from '@/components/shared/error-state'
import { Input } from '@/components/ui/input'
import { tagColumns } from './columns'

export function TagsTable() {
  const [search, setSearch] = useState('')

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['tags'],
    queryFn: () => api.tags.list(),
  })

  const filtered = useMemo(() => {
    const items = data?.items ?? []
    if (!search.trim()) return items
    const q = search.trim().toLowerCase()
    return items.filter(
      (t) =>
        t.tagCode.toLowerCase().includes(q) ||
        t.tagName.toLowerCase().includes(q) ||
        (t.tagDescription ?? '').toLowerCase().includes(q)
    )
  }, [data, search])

  if (isError) {
    return (
      <ErrorState title="Failed to load tags" error={error} />
    )
  }

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-2">
        <Input
          placeholder="Search tags…"
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
        columns={tagColumns}
        data={filtered}
        isLoading={isLoading}
        pageSize={20}
      />
    </div>
  )
}
