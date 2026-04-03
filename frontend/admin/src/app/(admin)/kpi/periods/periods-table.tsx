'use client'

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { api } from '@/lib/api'
import { DataTable } from '@/components/shared/data-table'
import { createPeriodColumns } from './columns'
import type { KpiPeriod } from '@/types/api'

export function PeriodsTable() {
  const queryClient = useQueryClient()

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['kpi', 'periods'],
    queryFn: () => api.kpi.periods.list(),
  })

  const openMutation = useMutation({
    mutationFn: (period: KpiPeriod) => api.kpi.periods.open(period.periodId),
    onSuccess: (_result, period) => {
      queryClient.invalidateQueries({ queryKey: ['kpi', 'periods'] })
      toast.success(`Period ${period.periodLabel} is now Open.`)
    },
    onError: (err: Error) => toast.error(err.message ?? 'Failed to open period.'),
  })

  const closeMutation = useMutation({
    mutationFn: (period: KpiPeriod) => api.kpi.periods.close(period.periodId),
    onSuccess: (_result, period) => {
      queryClient.invalidateQueries({ queryKey: ['kpi', 'periods'] })
      queryClient.invalidateQueries({ queryKey: ['kpi', 'monitoring'] })
      toast.success(`Period ${period.periodLabel} closed. All unlocked submissions locked.`)
    },
    onError: (err: Error) => toast.error(err.message ?? 'Failed to close period.'),
  })

  const columns = createPeriodColumns({
    onOpen: (period) => openMutation.mutate(period),
    onClose: (period) => closeMutation.mutate(period),
    openingId: openMutation.isPending ? (openMutation.variables as KpiPeriod)?.periodId : null,
    closingId: closeMutation.isPending ? (closeMutation.variables as KpiPeriod)?.periodId : null,
  })

  if (isError) {
    return (
      <div className="rounded-md border border-destructive/40 bg-destructive/5 p-6 text-center">
        <p className="text-sm font-medium text-destructive">Failed to load periods</p>
        <p className="mt-1 text-xs text-muted-foreground">
          {error instanceof Error ? error.message : 'An unexpected error occurred.'}
        </p>
      </div>
    )
  }

  // Sort: Open first, then Draft, then Closed/Distributed, then by year+month desc
  const sorted = [...(data?.items ?? [])].sort((a, b) => {
    const priority = { Open: 0, Draft: 1, Closed: 2, Distributed: 3 }
    const pa = priority[a.status] ?? 4
    const pb = priority[b.status] ?? 4
    if (pa !== pb) return pa - pb
    return b.periodYear * 100 + b.periodMonth - (a.periodYear * 100 + a.periodMonth)
  })

  return (
    <DataTable
      columns={columns}
      data={sorted}
      isLoading={isLoading}
      pageSize={12}
    />
  )
}
