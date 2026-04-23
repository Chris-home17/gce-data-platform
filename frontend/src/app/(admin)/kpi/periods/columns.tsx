'use client'

import type { ColumnDef } from '@tanstack/react-table'
import { Loader2, LockOpen, Lock } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { StatusBadge } from '@/components/shared/status-badge'
import { ConfirmDialog } from '@/components/shared/confirm-dialog'
import { formatDate } from '@/lib/utils'
import type { KpiPeriod } from '@/types/api'

function formatScheduleRef(period: KpiPeriod) {
  return `SCH-${period.periodScheduleId}`
}

export interface PeriodColumnHandlers {
  onOpen: (period: KpiPeriod) => void
  onClose: (period: KpiPeriod) => void
  openingId: number | null   // periodId currently being opened
  closingId: number | null   // periodId currently being closed
}

export function createPeriodColumns(handlers: PeriodColumnHandlers): ColumnDef<KpiPeriod, unknown>[] {
  return [
    {
      accessorKey: 'periodLabel',
      header: 'Period',
      cell: ({ row }) => (
        <div>
          <p className="font-mono font-medium">{row.original.periodLabel}</p>
          <p className="text-xs text-muted-foreground">
            {formatScheduleRef(row.original)} · {row.original.scheduleName}
          </p>
        </div>
      ),
    },
    {
      accessorKey: 'status',
      header: 'Status',
      cell: ({ row }) => <StatusBadge status={row.original.status} />,
      meta: { className: 'w-28' },
    },
    {
      accessorKey: 'submissionOpenDate',
      header: 'Opens',
      cell: ({ row }) => formatDate(row.original.submissionOpenDate),
      meta: { className: 'tabular-nums' },
    },
    {
      accessorKey: 'submissionCloseDate',
      header: 'Closes',
      cell: ({ row }) => formatDate(row.original.submissionCloseDate),
      meta: { className: 'tabular-nums' },
    },
    {
      id: 'daysRemaining',
      header: 'Days left',
      cell: ({ row }) => {
        const { status, daysRemaining, isCurrentlyOpen } = row.original
        if (status !== 'Open') return <span className="text-muted-foreground">—</span>
        if (daysRemaining === null || daysRemaining === undefined)
          return <span className="text-muted-foreground">—</span>
        const colour = daysRemaining <= 3 ? 'text-danger font-medium' : daysRemaining <= 7 ? 'text-warning' : 'text-foreground'
        return (
          <span className={colour}>
            {isCurrentlyOpen ? `${daysRemaining}d` : 'Window closed'}
          </span>
        )
      },
      meta: { className: 'w-24 tabular-nums' },
    },
    {
      id: 'actions',
      header: '',
      cell: ({ row }) => {
        const period = row.original
        const isOpening = handlers.openingId === period.periodId
        const isClosing = handlers.closingId === period.periodId

        if (period.status === 'Draft') {
          return (
            <ConfirmDialog
              trigger={
                <Button size="sm" variant="outline" disabled={isOpening}>
                  {isOpening
                    ? <Loader2 className="mr-2 h-3 w-3 animate-spin" />
                    : <LockOpen className="mr-2 h-3 w-3" />
                  }
                  Open
                </Button>
              }
              title={`Open period ${period.periodLabel}?`}
              description={`This will allow KPI submissions for ${period.periodLabel}. Submitters will be notified. This action cannot be undone.`}
              confirmLabel="Open Period"
              onConfirm={() => handlers.onOpen(period)}
              isLoading={isOpening}
            />
          )
        }

        if (period.status === 'Open') {
          return (
            <ConfirmDialog
              trigger={
                <Button size="sm" variant="destructive" disabled={isClosing}>
                  {isClosing
                    ? <Loader2 className="mr-2 h-3 w-3 animate-spin" />
                    : <Lock className="mr-2 h-3 w-3" />
                  }
                  Close
                </Button>
              }
              title={`Close period ${period.periodLabel}?`}
              description={`All unlocked submissions will be locked as "LockedByPeriodClose". This cannot be reversed. Submissions with no value will be permanently marked as missing.`}
              confirmLabel="Close Period"
              onConfirm={() => handlers.onClose(period)}
              isLoading={isClosing}
            />
          )
        }

        return null
      },
      meta: { className: 'w-28 text-right' },
    },
  ]
}
