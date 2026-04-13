'use client'

import { useMemo } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { ColumnDef } from '@tanstack/react-table'
import { MoreHorizontal, RefreshCcw } from 'lucide-react'
import { toast } from 'sonner'
import { DataTable } from '@/components/shared/data-table'
import { StatusBadge } from '@/components/shared/status-badge'
import { Button } from '@/components/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { api } from '@/lib/api'
import type { KpiPeriodSchedule } from '@/types/api'

function formatCadence(schedule: KpiPeriodSchedule) {
  if (schedule.frequencyType === 'EveryNMonths') {
    return `Every ${schedule.frequencyInterval} months`
  }
  if (schedule.frequencyType === 'SemiAnnual') {
    return 'Semi-annual'
  }
  return schedule.frequencyType
}

function ScheduleActions({ schedule }: { schedule: KpiPeriodSchedule }) {
  const queryClient = useQueryClient()

  const generateMutation = useMutation({
    mutationFn: () => api.kpi.periods.schedules.generate(schedule.periodScheduleId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['kpi', 'period-schedules'] })
      queryClient.invalidateQueries({ queryKey: ['kpi', 'periods'] })
      queryClient.invalidateQueries({ queryKey: ['kpi', 'assignments'] })
      toast.success(`Generated missing periods for ${schedule.scheduleName}.`)
    },
    onError: (err: Error) => toast.error(err.message ?? 'Failed to generate periods.'),
  })

  const toggleMutation = useMutation({
    mutationFn: () => api.kpi.periods.schedules.setActive(schedule.periodScheduleId, !schedule.isActive),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['kpi', 'period-schedules'] })
      queryClient.invalidateQueries({ queryKey: ['kpi', 'periods'] })
      queryClient.invalidateQueries({ queryKey: ['kpi', 'assignments'] })
      toast.success(schedule.isActive ? 'Schedule deactivated.' : 'Schedule activated.')
    },
    onError: (err: Error) => toast.error(err.message ?? 'Failed to update schedule.'),
  })

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          variant="ghost"
          size="sm"
          className="h-7 w-7 p-0 data-[state=open]:bg-muted"
          disabled={generateMutation.isPending || toggleMutation.isPending}
          onClick={(e) => e.stopPropagation()}
        >
          <MoreHorizontal className="h-4 w-4" />
          <span className="sr-only">Actions</span>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuItem onClick={(e) => { e.stopPropagation(); generateMutation.mutate() }}>
          <RefreshCcw className="mr-2 h-4 w-4" />
          Generate missing periods
        </DropdownMenuItem>
        <DropdownMenuSeparator />
        <DropdownMenuItem onClick={(e) => { e.stopPropagation(); toggleMutation.mutate() }}>
          {schedule.isActive ? 'Deactivate' : 'Activate'}
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

export function PeriodSchedulesTable() {
  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['kpi', 'period-schedules'],
    queryFn: () => api.kpi.periods.schedules.list(),
  })

  const columns = useMemo<ColumnDef<KpiPeriodSchedule, unknown>[]>(() => [
    {
      accessorKey: 'scheduleName',
      header: 'Schedule',
      cell: ({ row }) => (
        <div>
          <p className="text-sm font-medium">{row.original.scheduleName}</p>
          <p className="text-xs text-muted-foreground">
            {formatCadence(row.original)} · {row.original.startDate} to {row.original.endDate ?? 'open-ended'}
          </p>
        </div>
      ),
    },
    {
      id: 'window',
      header: 'Window',
      cell: ({ row }) => (
        <span className="text-sm text-muted-foreground">
          Day {row.original.submissionOpenDay} to {row.original.submissionCloseDay}
        </span>
      ),
    },
    {
      accessorKey: 'generateMonthsAhead',
      header: 'Horizon',
      cell: ({ row }) => <span className="text-sm">{row.original.generateMonthsAhead} months</span>,
      meta: { className: 'w-28' },
    },
    {
      accessorKey: 'generatedPeriodCount',
      header: 'Generated',
      cell: ({ row }) => (
        <div>
          <p className="text-sm font-medium">{row.original.generatedPeriodCount}</p>
          <p className="text-xs text-muted-foreground">{row.original.lastGeneratedPeriodLabel ?? '—'}</p>
        </div>
      ),
      meta: { className: 'w-28' },
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
      cell: ({ row }) => <ScheduleActions schedule={row.original} />,
      meta: { className: 'w-[40px]' },
    },
  ], [])

  if (isError) {
    return (
      <div className="rounded-md border border-destructive/40 bg-destructive/5 p-6 text-center">
        <p className="text-sm font-medium text-destructive">Failed to load period schedules</p>
        <p className="mt-1 text-xs text-muted-foreground">
          {error instanceof Error ? error.message : 'An unexpected error occurred.'}
        </p>
      </div>
    )
  }

  return <DataTable columns={columns} data={data?.items ?? []} isLoading={isLoading} pageSize={8} />
}
