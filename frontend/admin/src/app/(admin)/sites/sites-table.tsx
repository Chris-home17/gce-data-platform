'use client'

import type { DragEvent } from 'react'
import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { GripVertical } from 'lucide-react'
import { toast } from 'sonner'
import { Badge } from '@/components/ui/badge'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { StatusBadge } from '@/components/shared/status-badge'
import { RowActions } from '@/components/shared/row-actions'
import { api } from '@/lib/api'
import type { OrgUnit, OrgUnitType } from '@/types/api'
import { ImportOrgUnitsDialog } from './import-org-units-dialog'

function pathDepth(path: string): number {
  return path.split('|').filter(Boolean).length - 1
}

function allowedParentTypes(type: OrgUnitType): OrgUnitType[] {
  switch (type) {
    case 'Region':
      return []
    case 'SubRegion':
      return ['Region']
    case 'Cluster':
      return ['Region', 'SubRegion']
    case 'Country':
      return ['Region', 'SubRegion', 'Cluster']
    case 'Area':
      return ['Country']
    case 'Branch':
      return ['Country', 'Area']
    case 'Site':
      return ['Country', 'Area', 'Branch']
    default:
      return []
  }
}

function canMoveUnder(unit: OrgUnit, candidateParent: OrgUnit): boolean {
  if (unit.accountId !== candidateParent.accountId) return false
  if (unit.orgUnitId === candidateParent.orgUnitId) return false
  if (candidateParent.path.startsWith(unit.path)) return false
  return allowedParentTypes(unit.orgUnitType).includes(candidateParent.orgUnitType)
}

const TYPE_COLOURS: Record<OrgUnitType, string> = {
  Region: 'bg-blue-100 text-blue-700 border-blue-200',
  SubRegion: 'bg-indigo-100 text-indigo-700 border-indigo-200',
  Cluster: 'bg-violet-100 text-violet-700 border-violet-200',
  Country: 'bg-sky-100 text-sky-700 border-sky-200',
  Area: 'bg-teal-100 text-teal-700 border-teal-200',
  Branch: 'bg-orange-100 text-orange-700 border-orange-200',
  Site: 'bg-emerald-100 text-emerald-700 border-emerald-200',
}

function TypeBadge({ type }: { type: OrgUnitType }) {
  return (
    <span className={`inline-flex items-center rounded border px-1.5 py-0.5 text-xs font-medium ${TYPE_COLOURS[type] ?? 'bg-muted text-muted-foreground'}`}>
      {type}
    </span>
  )
}

function SkeletonRows() {
  return (
    <>
      {Array.from({ length: 6 }).map((_, i) => (
        <tr key={i} className="border-b">
          <td className="py-3 pl-4 pr-2"><div className="h-4 w-4 rounded bg-muted animate-pulse" /></td>
          <td className="py-3 px-3" style={{ paddingLeft: `${16 + (i % 3) * 20}px` }}>
            <div className="h-4 w-48 rounded bg-muted animate-pulse" />
          </td>
          <td className="py-3 px-3"><div className="h-4 w-16 rounded bg-muted animate-pulse" /></td>
          <td className="py-3 px-3"><div className="h-4 w-8 rounded bg-muted animate-pulse" /></td>
          <td className="py-3 px-3"><div className="h-4 w-6 rounded bg-muted animate-pulse ml-auto" /></td>
          <td className="py-3 px-3"><div className="h-4 w-6 rounded bg-muted animate-pulse ml-auto" /></td>
          <td className="py-3 px-3"><div className="h-5 w-14 rounded bg-muted animate-pulse" /></td>
        </tr>
      ))}
    </>
  )
}

interface OrgUnitRowProps {
  unit: OrgUnit
  canDrag: boolean
  isDragged: boolean
  isValidDropTarget: boolean
  isInvalidDropTarget: boolean
  onDragStart: (unit: OrgUnit) => void
  onDragEnd: () => void
  onDragOver: (unit: OrgUnit, event: DragEvent<HTMLTableRowElement>) => void
  onDragLeave: (unitId: number) => void
  onDrop: (unit: OrgUnit) => void
}

function OrgUnitRow({
  unit,
  canDrag,
  isDragged,
  isValidDropTarget,
  isInvalidDropTarget,
  onDragStart,
  onDragEnd,
  onDragOver,
  onDragLeave,
  onDrop,
}: OrgUnitRowProps) {
  const depth = pathDepth(unit.path)
  const indent = depth * 20

  return (
    <tr
      draggable={canDrag}
      onDragStart={() => onDragStart(unit)}
      onDragEnd={onDragEnd}
      onDragOver={(event) => onDragOver(unit, event)}
      onDragLeave={() => onDragLeave(unit.orgUnitId)}
      onDrop={() => onDrop(unit)}
      className={[
        'border-b transition-colors hover:bg-muted/40',
        canDrag ? 'cursor-grab active:cursor-grabbing' : '',
        isDragged ? 'opacity-45' : '',
        isValidDropTarget ? 'bg-emerald-50 ring-1 ring-inset ring-emerald-300' : '',
        isInvalidDropTarget ? 'bg-red-50/60' : '',
      ].join(' ')}
    >
      <td className="py-2.5 pl-4 pr-2 w-[36px] align-middle">
        {canDrag ? (
          <GripVertical className="h-4 w-4 text-muted-foreground/70" />
        ) : (
          <span className="block h-4 w-4" />
        )}
      </td>

      <td className="py-2.5 pr-3 pl-4" style={{ paddingLeft: `${16 + indent}px` }}>
        <div className="flex items-center gap-2">
          {depth > 0 && <span className="select-none text-muted-foreground/40">{'└'}</span>}
          <div>
            <span className="text-sm font-medium">{unit.orgUnitName}</span>
            <span className="ml-2 font-mono text-xs text-muted-foreground">{unit.orgUnitCode}</span>
          </div>
        </div>
      </td>

      <td className="w-[110px] px-3 py-2.5">
        <TypeBadge type={unit.orgUnitType} />
      </td>

      <td className="w-[80px] px-3 py-2.5">
        {unit.countryCode
          ? <span className="font-mono text-xs text-muted-foreground">{unit.countryCode}</span>
          : <span className="text-muted-foreground/40">—</span>}
      </td>

      <td className="w-[80px] px-3 py-2.5 text-right">
        {unit.childCount > 0
          ? <span className="text-sm tabular-nums text-muted-foreground">{unit.childCount}</span>
          : <span className="text-muted-foreground/40">—</span>}
      </td>

      <td className="w-[110px] px-3 py-2.5 text-right">
        {unit.sourceMappingCount > 0
          ? <Badge variant="secondary" className="text-xs tabular-nums">{unit.sourceMappingCount}</Badge>
          : <span className="text-xs text-muted-foreground/40">none</span>}
      </td>

      <td className="w-[90px] pl-3 pr-2 py-2.5">
        <StatusBadge status={unit.isActive ? 'Active' : 'Inactive'} />
      </td>

      <td className="w-[40px] pl-1 pr-3 py-2.5">
        <RowActions
          isActive={unit.isActive}
          onToggle={() => api.orgUnits.setActive(unit.orgUnitId, !unit.isActive)}
          invalidateKeys={[['org-units']]}
        />
      </td>
    </tr>
  )
}

function SitesTreeTable({
  accountId,
  showAccountFilter,
}: {
  accountId?: number
  showAccountFilter: boolean
}) {
  const [selectedAccountId, setSelectedAccountId] = useState<string>('all')
  const [draggedUnitId, setDraggedUnitId] = useState<number | null>(null)
  const [hoveredUnitId, setHoveredUnitId] = useState<number | null>(null)
  const selectedAccountIdNumber = selectedAccountId !== 'all' ? Number(selectedAccountId) : undefined
  const currentAccountId = showAccountFilter ? selectedAccountIdNumber : accountId
  const queryClient = useQueryClient()

  const { data: accounts } = useQuery({
    queryKey: ['accounts'],
    queryFn: () => api.accounts.list(),
    enabled: showAccountFilter,
  })

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['org-units', currentAccountId ?? 'all'],
    queryFn: () =>
      api.orgUnits.list(currentAccountId ? { accountId: currentAccountId } : undefined),
  })

  const items = data?.items ?? []
  const draggedUnit = useMemo(
    () => items.find((unit) => unit.orgUnitId === draggedUnitId) ?? null,
    [draggedUnitId, items],
  )

  const moveMutation = useMutation({
    mutationFn: ({ orgUnitId, parentOrgUnitId }: { orgUnitId: number; parentOrgUnitId: number | null }) =>
      api.orgUnits.move(orgUnitId, { parentOrgUnitId }),
    onSuccess: (updatedUnit) => {
      toast.success(`${updatedUnit.orgUnitName} moved.`, {
        description: updatedUnit.parentOrgUnitName
          ? `New parent: ${updatedUnit.parentOrgUnitName}`
          : 'Placed at account root.',
      })
      queryClient.invalidateQueries({ queryKey: ['org-units'] })
      queryClient.invalidateQueries({ queryKey: ['accounts'] })
      setDraggedUnitId(null)
      setHoveredUnitId(null)
    },
    onError: (err: Error) => {
      toast.error('Could not move org unit', { description: err.message })
      setHoveredUnitId(null)
    },
  })

  const canReorganize = currentAccountId != null

  function handleDragStart(unit: OrgUnit) {
    if (!canReorganize || allowedParentTypes(unit.orgUnitType).length === 0 || moveMutation.isPending) return
    setDraggedUnitId(unit.orgUnitId)
  }

  function handleDragEnd() {
    setDraggedUnitId(null)
    setHoveredUnitId(null)
  }

  function handleDragOver(targetUnit: OrgUnit, event: DragEvent<HTMLTableRowElement>) {
    if (!draggedUnit || draggedUnit.orgUnitId === targetUnit.orgUnitId) return
    setHoveredUnitId(targetUnit.orgUnitId)
    if (canMoveUnder(draggedUnit, targetUnit)) {
      event.preventDefault()
      event.dataTransfer.dropEffect = 'move'
    }
  }

  function handleDragLeave(unitId: number) {
    if (hoveredUnitId === unitId) {
      setHoveredUnitId(null)
    }
  }

  function handleDrop(targetUnit: OrgUnit) {
    if (!draggedUnit) return
    if (!canMoveUnder(draggedUnit, targetUnit)) {
      setHoveredUnitId(null)
      return
    }

    moveMutation.mutate({
      orgUnitId: draggedUnit.orgUnitId,
      parentOrgUnitId: targetUnit.orgUnitId,
    })
  }

  return (
    <div className="space-y-3">
      {showAccountFilter && (
        <div className="flex items-center gap-2">
          <span className="text-sm text-muted-foreground">Account</span>
          <Select value={selectedAccountId} onValueChange={setSelectedAccountId}>
            <SelectTrigger className="h-8 w-[260px] text-sm">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All accounts</SelectItem>
              {accounts?.items.map((a) => (
                <SelectItem key={a.accountId} value={String(a.accountId)}>
                  {a.accountName} ({a.accountCode})
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          {!isLoading && (
            <span className="text-xs text-muted-foreground">
              {items.length} unit{items.length !== 1 ? 's' : ''}
            </span>
          )}
          <div className="ml-auto">
            <ImportOrgUnitsDialog />
          </div>
        </div>
      )}

      <div className="rounded-md border border-dashed bg-muted/20 px-3 py-2 text-xs text-muted-foreground">
        {canReorganize
          ? 'Drag an org unit onto a valid parent row to reorganize the structure. Hierarchy rules are enforced automatically.'
          : 'Select a single account to enable drag-and-drop reorganisation.'}
      </div>

      {isError ? (
        <div className="rounded-md border border-destructive/40 bg-destructive/5 p-6 text-center">
          <p className="text-sm font-medium text-destructive">Failed to load org units</p>
          <p className="mt-1 text-xs text-muted-foreground">
            {error instanceof Error ? error.message : 'An unexpected error occurred.'}
          </p>
        </div>
      ) : (
        <div className="rounded-md border">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b bg-muted/50">
                <th className="w-[36px] py-2.5 pl-4 pr-2 text-left text-xs font-medium text-muted-foreground" />
                <th className="px-4 py-2.5 text-left text-xs font-medium text-muted-foreground">Name / Code</th>
                <th className="w-[110px] px-3 py-2.5 text-left text-xs font-medium text-muted-foreground">Type</th>
                <th className="w-[80px] px-3 py-2.5 text-left text-xs font-medium text-muted-foreground">Country</th>
                <th className="w-[80px] px-3 py-2.5 text-right text-xs font-medium text-muted-foreground">Children</th>
                <th className="w-[110px] px-3 py-2.5 text-right text-xs font-medium text-muted-foreground">Src Maps</th>
                <th className="w-[90px] px-3 py-2.5 text-left text-xs font-medium text-muted-foreground">Status</th>
                <th className="w-[40px] py-2.5 pl-1 pr-3 text-left text-xs font-medium text-muted-foreground" />
              </tr>
            </thead>
            <tbody>
              {isLoading ? (
                <SkeletonRows />
              ) : items.length === 0 ? (
                <tr>
                  <td colSpan={8} className="py-10 text-center text-sm text-muted-foreground">
                    No org units found.
                  </td>
                </tr>
              ) : (
                items.map((unit) => {
                  const isDragged = unit.orgUnitId === draggedUnitId
                  const isHover = unit.orgUnitId === hoveredUnitId
                  const validDropTarget = !!draggedUnit && isHover && canMoveUnder(draggedUnit, unit)
                  const invalidDropTarget = !!draggedUnit && isHover && !validDropTarget && !isDragged

                  return (
                    <OrgUnitRow
                      key={unit.orgUnitId}
                      unit={unit}
                      canDrag={canReorganize && allowedParentTypes(unit.orgUnitType).length > 0 && !moveMutation.isPending}
                      isDragged={isDragged}
                      isValidDropTarget={validDropTarget}
                      isInvalidDropTarget={invalidDropTarget}
                      onDragStart={handleDragStart}
                      onDragEnd={handleDragEnd}
                      onDragOver={handleDragOver}
                      onDragLeave={handleDragLeave}
                      onDrop={handleDrop}
                    />
                  )
                })
              )}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}

export function SitesTable() {
  return <SitesTreeTable showAccountFilter />
}

export function AccountSitesTable({ accountId }: { accountId: number }) {
  return <SitesTreeTable accountId={accountId} showAccountFilter={false} />
}
