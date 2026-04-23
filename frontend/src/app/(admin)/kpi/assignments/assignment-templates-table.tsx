'use client'

import { useMemo } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import type { ColumnDef } from '@tanstack/react-table'
import { MoreHorizontal, RefreshCcw } from 'lucide-react'
import { toast } from 'sonner'
import { DataTable } from '@/components/shared/data-table'
import { StatusBadge } from '@/components/shared/status-badge'
import { ErrorState } from '@/components/shared/error-state'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { api } from '@/lib/api'
import type { KpiAssignmentTemplate } from '@/types/api'

function TemplateActions({ template }: { template: KpiAssignmentTemplate }) {
  const queryClient = useQueryClient()

  const materializeMutation = useMutation({
    mutationFn: () => api.kpi.assignments.templates.materialize(template.assignmentTemplateId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['kpi', 'assignment-templates'] })
      queryClient.invalidateQueries({ queryKey: ['kpi', 'assignments'] })
      toast.success(`Assignments materialized for ${template.kpiCode}.`)
    },
    onError: (err: Error) => toast.error(err.message ?? 'Failed to materialize assignments.'),
  })

  const toggleMutation = useMutation({
    mutationFn: () => api.kpi.assignments.templates.setActive(template.assignmentTemplateId, !template.isActive),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['kpi', 'assignment-templates'] })
      queryClient.invalidateQueries({ queryKey: ['kpi', 'assignments'] })
      toast.success(template.isActive ? 'Template deactivated.' : 'Template activated.')
    },
    onError: (err: Error) => toast.error(err.message ?? 'Failed to update template.'),
  })

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          variant="ghost"
          size="sm"
          className="h-7 w-7 p-0 data-[state=open]:bg-muted"
          disabled={materializeMutation.isPending || toggleMutation.isPending}
          onClick={(e) => e.stopPropagation()}
        >
          <MoreHorizontal className="h-4 w-4" />
          <span className="sr-only">Actions</span>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuItem onClick={(e) => { e.stopPropagation(); materializeMutation.mutate() }}>
          <RefreshCcw className="mr-2 h-4 w-4" />
          Materialize now
        </DropdownMenuItem>
        <DropdownMenuSeparator />
        <DropdownMenuItem onClick={(e) => { e.stopPropagation(); toggleMutation.mutate() }}>
          {template.isActive ? 'Deactivate' : 'Activate'}
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

function formatCadence(template: KpiAssignmentTemplate) {
  if (!template.frequencyType) return '—'
  if (template.frequencyType === 'EveryNMonths') {
    return `Every ${template.frequencyInterval} months`
  }
  if (template.frequencyType === 'SemiAnnual') return 'Semi-annual'
  return template.frequencyType
}

export function AssignmentTemplatesTable({
  data,
  isLoading,
  isError,
  error,
}: {
  data: KpiAssignmentTemplate[]
  isLoading: boolean
  isError: boolean
  error: Error | null
}) {

  const columns = useMemo<ColumnDef<KpiAssignmentTemplate, unknown>[]>(() => [
    {
      accessorKey: 'kpiCode',
      header: 'KPI',
      cell: ({ row }) => (
        <div>
          <p className="font-mono text-sm font-medium">{row.original.kpiCode}</p>
          <p className="text-xs text-muted-foreground">{row.original.kpiName}</p>
        </div>
      ),
    },
    {
      accessorKey: 'accountCode',
      header: 'Account',
      cell: ({ row }) => (
        <div>
          <p className="text-sm font-medium">{row.original.accountCode}</p>
          <p className="text-xs text-muted-foreground">{row.original.accountName}</p>
        </div>
      ),
      meta: { className: 'w-40' },
    },
    {
      id: 'scope',
      header: 'Scope',
      cell: ({ row }) => row.original.isAccountWide
        ? <span className="text-sm text-muted-foreground">Account-wide</span>
        : (
          <div>
            <p className="font-mono text-sm">{row.original.siteCode}</p>
            <p className="text-xs text-muted-foreground">{row.original.siteName}</p>
          </div>
        ),
    },
    {
      id: 'schedule',
      header: 'Schedule',
      cell: ({ row }) => (
        <div>
          <p className="text-sm font-medium">{row.original.scheduleName ?? '—'}</p>
          <p className="text-xs text-muted-foreground">{formatCadence(row.original)}</p>
        </div>
      ),
      meta: { className: 'w-40' },
    },
    {
      accessorKey: 'generatedAssignmentCount',
      header: 'Generated',
      cell: ({ row }) => <span className="text-sm font-medium">{row.original.generatedAssignmentCount}</span>,
      meta: { className: 'w-24' },
    },
    {
      id: 'source',
      header: 'Source',
      cell: ({ row }) => {
        const { kpiPackageId, kpiPackageName } = row.original
        if (kpiPackageId && kpiPackageName) {
          return (
            <Badge variant="secondary" className="text-xs max-w-[120px] truncate" title={kpiPackageName}>
              {kpiPackageName}
            </Badge>
          )
        }
        return <span className="text-xs text-muted-foreground">Individual</span>
      },
      meta: { className: 'w-36' },
    },
    {
      accessorKey: 'assignmentGroupName',
      header: 'Group',
      cell: ({ row }) => {
        const g = row.original.assignmentGroupName
        return g
          ? <Badge variant="outline" className="text-xs font-normal">{g}</Badge>
          : <span className="text-xs text-muted-foreground">—</span>
      },
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
      cell: ({ row }) => <TemplateActions template={row.original} />,
      meta: { className: 'w-[40px]' },
    },
  ], [])

  if (isError) {
    return (
      <ErrorState title="Failed to load recurring templates" error={error} />
    )
  }

  return <DataTable columns={columns} data={data} isLoading={isLoading} pageSize={8} />
}
