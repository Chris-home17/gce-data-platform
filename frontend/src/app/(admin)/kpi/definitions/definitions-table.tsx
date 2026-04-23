'use client'

import { useState, useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import { api } from '@/lib/api'
import { DataTable } from '@/components/shared/data-table'
import { ErrorState } from '@/components/shared/error-state'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { definitionColumns } from './columns'

function parseTagsRaw(raw: string | null): Array<{ id: number; name: string }> {
  if (!raw) return []
  return raw.split('|').map((part) => {
    const [id, ...rest] = part.split(':')
    return { id: parseInt(id), name: rest.join(':') }
  })
}

export function DefinitionsTable() {
  const [categoryFilter, setCategoryFilter] = useState<string>('all')
  const [tagFilter, setTagFilter] = useState<string>('all')

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['kpi', 'definitions'],
    queryFn: () => api.kpi.definitions.list(),
  })

  const tagsQuery = useQuery({
    queryKey: ['tags'],
    queryFn: () => api.tags.list(),
  })
  const activeTags = useMemo(
    () => (tagsQuery.data?.items ?? []).filter((t) => t.isActive),
    [tagsQuery.data]
  )

  const categories = useMemo(() => {
    const cats = new Set(data?.items.map((d) => d.category).filter(Boolean) as string[])
    return Array.from(cats).sort()
  }, [data])

  const filtered = useMemo(() => {
    let items = data?.items ?? []
    if (categoryFilter !== 'all') items = items.filter((d) => d.category === categoryFilter)
    if (tagFilter !== 'all') {
      const tagId = parseInt(tagFilter)
      items = items.filter((d) => parseTagsRaw(d.tagsRaw).some((t) => t.id === tagId))
    }
    return items
  }, [data, categoryFilter, tagFilter])

  if (isError) {
    return (
      <ErrorState title="Failed to load KPI definitions" error={error} />
    )
  }

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-3 flex-wrap">
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
        </div>

        {activeTags.length > 0 && (
          <div className="flex items-center gap-2">
            <span className="text-sm text-muted-foreground">Tag:</span>
            <Select value={tagFilter} onValueChange={setTagFilter}>
              <SelectTrigger className="w-40 h-8 text-sm">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All tags</SelectItem>
                {activeTags.map((t) => (
                  <SelectItem key={t.tagId} value={String(t.tagId)}>{t.tagName}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        )}

        {(categoryFilter !== 'all' || tagFilter !== 'all') && (
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
