'use client'

import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Badge } from '@/components/ui/badge'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { StatusBadge } from '@/components/shared/status-badge'
import { RowActions } from '@/components/shared/row-actions'
import { api } from '@/lib/api'
import type { OrgUnit, OrgUnitType } from '@/types/api'

// Depth in the hierarchy: count non-empty path segments, subtract 1 for account code
function pathDepth(path: string): number {
  return path.split('|').filter(Boolean).length - 1
}

const TYPE_COLOURS: Record<OrgUnitType, string> = {
  Division:  'bg-violet-100 text-violet-700 border-violet-200',
  Region:    'bg-blue-100 text-blue-700 border-blue-200',
  Country:   'bg-sky-100 text-sky-700 border-sky-200',
  Area:      'bg-teal-100 text-teal-700 border-teal-200',
  Territory: 'bg-cyan-100 text-cyan-700 border-cyan-200',
  Branch:    'bg-orange-100 text-orange-700 border-orange-200',
  Site:      'bg-emerald-100 text-emerald-700 border-emerald-200',
}

function TypeBadge({ type }: { type: OrgUnitType }) {
  return (
    <span className={`inline-flex items-center rounded border px-1.5 py-0.5 text-xs font-medium ${TYPE_COLOURS[type] ?? 'bg-muted text-muted-foreground'}`}>
      {type}
    </span>
  )
}

function OrgUnitRow({ unit }: { unit: OrgUnit }) {
  const depth = pathDepth(unit.path)
  const indent = depth * 20 // px per level

  return (
    <tr className="border-b transition-colors hover:bg-muted/40">
      {/* Name + Code — indented */}
      <td className="py-2.5 pr-3 pl-4" style={{ paddingLeft: `${16 + indent}px` }}>
        <div className="flex items-center gap-2">
          {depth > 0 && (
            <span className="text-muted-foreground/40 select-none">{'└'}</span>
          )}
          <div>
            <span className="font-medium text-sm">{unit.orgUnitName}</span>
            <span className="ml-2 font-mono text-xs text-muted-foreground">{unit.orgUnitCode}</span>
          </div>
        </div>
      </td>

      {/* Type */}
      <td className="py-2.5 px-3 w-[110px]">
        <TypeBadge type={unit.orgUnitType} />
      </td>

      {/* Country */}
      <td className="py-2.5 px-3 w-[80px]">
        {unit.countryCode
          ? <span className="font-mono text-xs text-muted-foreground">{unit.countryCode}</span>
          : <span className="text-muted-foreground/40">—</span>}
      </td>

      {/* Children */}
      <td className="py-2.5 px-3 w-[80px] text-right">
        {unit.childCount > 0
          ? <span className="tabular-nums text-sm text-muted-foreground">{unit.childCount}</span>
          : <span className="text-muted-foreground/40">—</span>}
      </td>

      {/* Source Mappings */}
      <td className="py-2.5 px-3 w-[110px] text-right">
        {unit.sourceMappingCount > 0
          ? <Badge variant="secondary" className="text-xs tabular-nums">{unit.sourceMappingCount}</Badge>
          : <span className="text-muted-foreground/40 text-xs">none</span>}
      </td>

      {/* Status */}
      <td className="py-2.5 pl-3 pr-2 w-[90px]">
        <StatusBadge status={unit.isActive ? 'Active' : 'Inactive'} />
      </td>

      {/* Actions */}
      <td className="py-2.5 pl-1 pr-3 w-[40px]">
        <RowActions
          isActive={unit.isActive}
          onToggle={() => api.orgUnits.setActive(unit.orgUnitId, !unit.isActive)}
          invalidateKeys={[['org-units']]}
        />
      </td>
    </tr>
  )
}

function SkeletonRows() {
  return (
    <>
      {Array.from({ length: 6 }).map((_, i) => (
        <tr key={i} className="border-b">
          <td className="py-3 px-4" style={{ paddingLeft: `${16 + (i % 3) * 20}px` }}>
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

function SitesTreeTable({
  accountId,
  showAccountFilter,
}: {
  accountId?: number
  showAccountFilter: boolean
}) {
  const [selectedAccountId, setSelectedAccountId] = useState<string>('all')
  const effectiveAccountId = accountId ?? (selectedAccountId !== 'all' ? Number(selectedAccountId) : undefined)

  const { data: accounts } = useQuery({
    queryKey: ['accounts'],
    queryFn: () => api.accounts.list(),
    enabled: showAccountFilter,
  })

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['org-units', effectiveAccountId ?? 'all'],
    queryFn: () =>
      api.orgUnits.list(effectiveAccountId ? { accountId: effectiveAccountId } : undefined),
  })

  // Items arrive pre-sorted by Path from the API — tree order is correct already
  const items = data?.items ?? []

  return (
    <div className="space-y-3">
      {showAccountFilter && (
        <div className="flex items-center gap-2">
          <span className="text-sm text-muted-foreground">Account</span>
          <Select value={selectedAccountId} onValueChange={setSelectedAccountId}>
            <SelectTrigger className="w-[260px] h-8 text-sm">
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
        </div>
      )}

      {/* Tree table */}
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
                <th className="py-2.5 px-4 text-left text-xs font-medium text-muted-foreground">Name / Code</th>
                <th className="py-2.5 px-3 text-left text-xs font-medium text-muted-foreground w-[110px]">Type</th>
                <th className="py-2.5 px-3 text-left text-xs font-medium text-muted-foreground w-[80px]">Country</th>
                <th className="py-2.5 px-3 text-right text-xs font-medium text-muted-foreground w-[80px]">Children</th>
                <th className="py-2.5 px-3 text-right text-xs font-medium text-muted-foreground w-[110px]">Src Maps</th>
                <th className="py-2.5 px-3 text-left text-xs font-medium text-muted-foreground w-[90px]">Status</th>
              </tr>
            </thead>
            <tbody>
              {isLoading ? (
                <SkeletonRows />
              ) : items.length === 0 ? (
                <tr>
                  <td colSpan={6} className="py-10 text-center text-sm text-muted-foreground">
                    No org units found.
                  </td>
                </tr>
              ) : (
                items.map((unit) => <OrgUnitRow key={unit.orgUnitId} unit={unit} />)
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
