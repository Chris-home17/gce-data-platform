'use client'

import { useState, useMemo } from 'react'
import { DataTable } from '@/components/shared/data-table'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import type { KpiAssignment, KpiPeriod } from '@/types/api'
import { assignmentColumns } from './columns'

function formatScheduleRef(periodScheduleId: number) {
  return `SCH-${periodScheduleId}`
}

export function AssignmentsTable({
  data,
  periods,
  isLoading,
  isError,
  error,
}: {
  data: KpiAssignment[]
  periods: KpiPeriod[]
  isLoading: boolean
  isError: boolean
  error: Error | null
}) {
  const [periodFilter, setPeriodFilter] = useState<string>('all')

  // Sort periods: Open first, then by year+month desc
  const sortedPeriods = useMemo(() => {
    return [...periods].sort((a, b) => {
      const priority = { Open: 0, Draft: 1, Closed: 2, Distributed: 3 }
      const pa = priority[a.status] ?? 4
      const pb = priority[b.status] ?? 4
      if (pa !== pb) return pa - pb
      return b.periodYear * 100 + b.periodMonth - (a.periodYear * 100 + a.periodMonth)
    })
  }, [periods])

  const filtered = useMemo(() => {
    return data.filter((assignment) => periodFilter === 'all' || String(assignment.periodId) === periodFilter)
  }, [data, periodFilter])

  if (isError) {
    return (
      <div className="rounded-md border border-destructive/40 bg-destructive/5 p-6 text-center">
        <p className="text-sm font-medium text-destructive">Failed to load assignments</p>
        <p className="mt-1 text-xs text-muted-foreground">
          {error instanceof Error ? error.message : 'An unexpected error occurred.'}
        </p>
      </div>
    )
  }

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <div className="flex items-center gap-2">
          <span className="text-sm text-muted-foreground">Period:</span>
          <Select value={periodFilter} onValueChange={setPeriodFilter}>
            <SelectTrigger className="h-8 w-44 text-sm">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All periods</SelectItem>
              {sortedPeriods.map((p) => (
                <SelectItem key={p.periodId} value={String(p.periodId)}>
                  {p.periodLabel}
                  <span className="ml-2 text-xs text-muted-foreground">
                    {formatScheduleRef(p.periodScheduleId)} · {p.scheduleName} ({p.status})
                  </span>
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>

        <span className="text-xs text-muted-foreground">
          {filtered.length} assignment{filtered.length !== 1 ? 's' : ''}
        </span>
      </div>

      <DataTable
        columns={assignmentColumns}
        data={filtered}
        isLoading={isLoading}
        pageSize={20}
      />
    </div>
  )
}
