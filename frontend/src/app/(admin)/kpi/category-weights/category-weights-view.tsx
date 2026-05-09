'use client'

import { useEffect, useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Info, Loader2, Plus, RotateCcw, Trash2 } from 'lucide-react'
import { toast } from 'sonner'
import { PageHeader } from '@/components/shared/page-header'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Switch } from '@/components/ui/switch'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { ConfirmDialog } from '@/components/shared/confirm-dialog'
import { api } from '@/lib/api'
import { useAccount } from '@/contexts/account-context'
import type { CategoryWeight } from '@/types/api'

// Category set used as suggestions when the account has no rows yet.
// These match the values in KPI.Definition.Category and the seed data.
const SUGGESTED_CATEGORIES = [
  'Safety',
  'Quality',
  'Productivity',
  'Finance',
  'Compliance',
  'HR/People',
] as const

interface EditableRow extends CategoryWeight {
  isNew?: boolean
}

export function CategoryWeightsView() {
  const { selectedAccount } = useAccount()
  const queryClient = useQueryClient()
  const accountCode = selectedAccount?.accountCode

  const { data, isLoading } = useQuery({
    queryKey: ['kpi', 'category-weights', accountCode],
    queryFn: () => api.kpi.categoryWeights.list(accountCode!),
    enabled: !!accountCode,
  })

  const [rows, setRows] = useState<EditableRow[]>([])
  const [newCategory, setNewCategory] = useState('')

  // Hydrate local edit buffer when the server data arrives or the account changes.
  useEffect(() => {
    if (data?.items) setRows(data.items.map((w) => ({ ...w })))
  }, [data, accountCode])

  const total = useMemo(
    () => rows.filter((r) => r.isActive).reduce((acc, r) => acc + (Number.isFinite(r.weight) ? r.weight : 0), 0),
    [rows],
  )

  const remainingSuggestions = useMemo(() => {
    const taken = new Set(rows.map((r) => r.category))
    return SUGGESTED_CATEGORIES.filter((c) => !taken.has(c))
  }, [rows])

  const upsertMutation = useMutation({
    mutationFn: () =>
      api.kpi.categoryWeights.upsert({
        accountCode: accountCode!,
        // Strip the local-only `isNew` flag before sending — backend doesn't know about it.
        weights: rows.map((r) => ({ category: r.category, weight: r.weight, isActive: r.isActive })),
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['kpi', 'category-weights', accountCode] })
      toast.success('Category weights saved.')
    },
    onError: (err: Error) => toast.error(err.message ?? 'Failed to save category weights.'),
  })

  // Re-apply the current account-level weights to every existing template
  // (and cascade to their unsubmitted assignments). Submitted history stays
  // frozen because each submitted assignment's snapshot is left alone by the
  // server-side cascade filter.
  const refreshMutation = useMutation({
    mutationFn: () => api.kpi.categoryWeights.refreshTemplates({ accountCode: accountCode! }),
    onSuccess: (result) => {
      queryClient.invalidateQueries({ queryKey: ['kpi', 'assignment-templates'] })
      queryClient.invalidateQueries({ queryKey: ['kpi', 'assignments'] })
      queryClient.invalidateQueries({ queryKey: ['kpi', 'site-scores'] })
      toast.success(
        `${result.templatesUpdated} templates re-snapped, ${result.assignmentsUpdated} unsubmitted assignments updated.`,
      )
    },
    onError: (err: Error) => toast.error(err.message ?? 'Failed to re-apply weights.'),
  })

  // The cascade button is disabled while there are local edits, so the admin
  // must save (or revert) before propagating. Comparison ignores the
  // local-only isNew flag.
  const hasUnsavedEdits = useMemo(() => {
    const server = data?.items ?? []
    if (server.length !== rows.length) return true
    const byCategory = new Map(server.map((r) => [r.category, r]))
    return rows.some((r) => {
      if (r.isNew) return true
      const s = byCategory.get(r.category)
      return !s || s.weight !== r.weight || s.isActive !== r.isActive
    })
  }, [rows, data])

  function updateRow(idx: number, patch: Partial<EditableRow>) {
    setRows((prev) => prev.map((r, i) => (i === idx ? { ...r, ...patch } : r)))
  }

  function addRow(category: string) {
    if (!category.trim()) return
    if (rows.some((r) => r.category === category)) {
      toast.error('That category is already in the list.')
      return
    }
    setRows((prev) => [...prev, { category, weight: 1.0, isActive: true, isNew: true }])
    setNewCategory('')
  }

  function removeRow(idx: number) {
    // Soft-remove: mark inactive so the upsert proc disables the existing
    // server row. Net-new (isNew) rows can just drop from local state.
    setRows((prev) => {
      const row = prev[idx]
      if (!row) return prev
      if (row.isNew) return prev.filter((_, i) => i !== idx)
      return prev.map((r, i) => (i === idx ? { ...r, isActive: false } : r))
    })
  }

  if (!selectedAccount) {
    return (
      <div className="space-y-6">
        <PageHeader
          title="Category Weights"
          description="Configure how each KPI category weighs into the composite score on the Monitoring page."
        />
        <p className="text-sm text-muted-foreground rounded-md border border-dashed px-4 py-3">
          Select an account from the sidebar to manage its category weights.
        </p>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Category Weights"
        description={`Weights applied to each KPI category when computing ${selectedAccount.accountName}'s composite score. Values are normalised at compute time, so they don't have to sum to 1.`}
        actions={
          <div className="flex items-center gap-2">
            <ConfirmDialog
              trigger={
                <Button
                  variant="outline"
                  disabled={hasUnsavedEdits || refreshMutation.isPending || upsertMutation.isPending || isLoading}
                  title={hasUnsavedEdits ? 'Save your changes first' : undefined}
                >
                  {refreshMutation.isPending
                    ? <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                    : <RotateCcw className="mr-2 h-4 w-4" />}
                  Re-apply to existing templates
                </Button>
              }
              title="Re-apply current weights to existing templates?"
              description={`This re-snaps every assignment template under ${selectedAccount.accountName} from the values shown in the table, then propagates the new weights to each template's unsubmitted assignments. Already-submitted history is unaffected.`}
              confirmLabel="Re-apply"
              isLoading={refreshMutation.isPending}
              onConfirm={() => refreshMutation.mutate()}
            />
            <Button
              onClick={() => upsertMutation.mutate()}
              disabled={upsertMutation.isPending || isLoading}
            >
              {upsertMutation.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
              Save changes
            </Button>
          </div>
        }
      />

      {/* Snapshot semantics info banner */}
      <div className="flex items-start gap-2 rounded-md border bg-muted/40 px-3 py-2.5 text-sm">
        <Info className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />
        <p className="text-muted-foreground">
          Edits apply to <strong>new</strong> templates only — existing templates retain the weight that
          was in effect when they were created. Click <strong>Re-apply to existing templates</strong> to
          cascade current values to existing templates and their unsubmitted assignments. Submitted
          history is never re-scored.
        </p>
      </div>

      <section className="space-y-3">
        <div className="rounded-md border">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="w-[45%]">Category</TableHead>
                <TableHead className="w-[20%]">Weight</TableHead>
                <TableHead className="w-[20%]">Active</TableHead>
                <TableHead className="w-[15%] text-right">Actions</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {isLoading ? (
                <TableRow>
                  <TableCell colSpan={4} className="text-center text-sm text-muted-foreground">
                    Loading…
                  </TableCell>
                </TableRow>
              ) : rows.length === 0 ? (
                <TableRow>
                  <TableCell colSpan={4} className="text-center text-sm text-muted-foreground">
                    No category weights configured. All categories will use weight 1.0 until you set values below.
                  </TableCell>
                </TableRow>
              ) : (
                rows.map((row, idx) => (
                  <TableRow key={`${row.category}-${idx}`}>
                    <TableCell className="font-medium">{row.category}</TableCell>
                    <TableCell>
                      <Input
                        type="number"
                        step="0.01"
                        min={0}
                        value={Number.isFinite(row.weight) ? row.weight : ''}
                        onChange={(e) => updateRow(idx, { weight: parseFloat(e.target.value) || 0 })}
                        className="max-w-[120px]"
                      />
                    </TableCell>
                    <TableCell>
                      <Switch
                        checked={row.isActive}
                        onCheckedChange={(value) => updateRow(idx, { isActive: value })}
                      />
                    </TableCell>
                    <TableCell className="text-right">
                      <Button variant="ghost" size="sm" onClick={() => removeRow(idx)}>
                        <Trash2 className="h-4 w-4" />
                      </Button>
                    </TableCell>
                  </TableRow>
                ))
              )}
            </TableBody>
          </Table>
        </div>

        <div className="flex items-end gap-2">
          <div className="flex-1">
            <label className="text-xs font-medium uppercase tracking-wider text-muted-foreground">
              Add category
            </label>
            <Input
              placeholder="Type a category name or pick a suggestion"
              value={newCategory}
              onChange={(e) => setNewCategory(e.target.value)}
              list="kpi-category-suggestions"
            />
            <datalist id="kpi-category-suggestions">
              {remainingSuggestions.map((c) => (
                <option key={c} value={c} />
              ))}
            </datalist>
          </div>
          <Button onClick={() => addRow(newCategory)} disabled={!newCategory.trim()}>
            <Plus className="mr-2 h-4 w-4" />
            Add
          </Button>
        </div>

        <p className="text-xs text-muted-foreground">
          Active weights total <span className="font-mono">{total.toFixed(2)}</span>. Composite score normalises by
          total at compute time — this is informational only.
        </p>
      </section>
    </div>
  )
}
