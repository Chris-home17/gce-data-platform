'use client'

import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { Loader2, Search, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetFooter,
  SheetHeader,
  SheetTitle,
} from '@/components/ui/sheet'
import { Badge } from '@/components/ui/badge'
import { Input } from '@/components/ui/input'
import { cn } from '@/lib/utils'
import { api } from '@/lib/api'
import type { KpiPackage } from '@/types/api'

interface Props {
  pkg: KpiPackage
  open: boolean
  onClose: () => void
}

export function PackageDetailSheet({ pkg, open, onClose }: Props) {
  const queryClient = useQueryClient()
  const [search, setSearch] = useState('')
  const [selectedIds, setSelectedIds] = useState<Set<number>>(new Set())
  const [initialized, setInitialized] = useState(false)

  const detailQuery = useQuery({
    queryKey: ['kpi', 'packages', pkg.kpiPackageId],
    queryFn: () => api.kpi.packages.get(pkg.kpiPackageId),
    enabled: open,
  })

  const definitionsQuery = useQuery({
    queryKey: ['kpi', 'definitions'],
    queryFn: () => api.kpi.definitions.list(),
    enabled: open,
  })

  // Initialise selection from existing package items
  useMemo(() => {
    if (!open || initialized || !detailQuery.data) return
    const ids = new Set(detailQuery.data.items.map((i) => i.kpiId))
    setSelectedIds(ids)
    setInitialized(true)
  }, [open, initialized, detailQuery.data])

  // Reset when closed
  function handleClose() {
    setSearch('')
    setSelectedIds(new Set())
    setInitialized(false)
    onClose()
  }

  const allKpis = useMemo(() => {
    return (definitionsQuery.data?.items ?? []).filter((k) => k.isActive)
  }, [definitionsQuery.data])

  const filtered = useMemo(() => {
    if (!search.trim()) return allKpis
    const q = search.trim().toLowerCase()
    return allKpis.filter(
      (k) =>
        k.kpiCode.toLowerCase().includes(q) ||
        k.kpiName.toLowerCase().includes(q) ||
        (k.category ?? '').toLowerCase().includes(q)
    )
  }, [allKpis, search])

  function toggle(kpiId: number) {
    setSelectedIds((prev) => {
      const next = new Set(prev)
      if (next.has(kpiId)) next.delete(kpiId)
      else next.add(kpiId)
      return next
    })
  }

  const mutation = useMutation({
    mutationFn: () =>
      api.kpi.packages.setItems(pkg.kpiPackageId, { kpiIds: Array.from(selectedIds) }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['kpi', 'packages'] })
      queryClient.invalidateQueries({ queryKey: ['kpi', 'packages', pkg.kpiPackageId] })
      toast.success('Package KPIs updated.')
      handleClose()
    },
    onError: (err: Error) => toast.error(err.message ?? 'Failed to update package KPIs.'),
  })

  const isLoading = detailQuery.isLoading || definitionsQuery.isLoading

  return (
    <Sheet open={open} onOpenChange={(v) => { if (!v) handleClose() }}>
      <SheetContent className="w-full sm:max-w-lg flex flex-col overflow-hidden">
        <SheetHeader>
          <SheetTitle>Manage KPIs — {pkg.packageName}</SheetTitle>
          <SheetDescription>
            Select which KPIs belong to this package. Changes are applied on Save.
          </SheetDescription>
        </SheetHeader>

        <div className="flex items-center gap-2 py-3">
          <div className="relative flex-1">
            <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-muted-foreground" />
            <Input
              placeholder="Search KPIs…"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="h-8 pl-8 text-sm"
            />
            {search && (
              <button
                onClick={() => setSearch('')}
                className="absolute right-2.5 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
              >
                <X className="h-3.5 w-3.5" />
              </button>
            )}
          </div>
          <Badge variant="secondary" className="shrink-0">
            {selectedIds.size} selected
          </Badge>
        </div>

        <div className="flex-1 overflow-y-auto border rounded-md divide-y">
          {isLoading ? (
            <div className="flex items-center justify-center p-8">
              <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
            </div>
          ) : filtered.length === 0 ? (
            <p className="p-4 text-sm text-center text-muted-foreground">No KPIs found.</p>
          ) : (
            filtered.map((kpi) => {
              const selected = selectedIds.has(kpi.kpiId)
              return (
                <button
                  key={kpi.kpiId}
                  type="button"
                  onClick={() => toggle(kpi.kpiId)}
                  className={cn(
                    'w-full flex items-start gap-3 px-3 py-2.5 text-left transition-colors',
                    selected ? 'bg-primary/5' : 'hover:bg-muted/40'
                  )}
                >
                  <div className={cn(
                    'mt-1 h-4 w-4 shrink-0 rounded border transition-colors',
                    selected ? 'border-primary bg-primary' : 'border-muted-foreground/40'
                  )}>
                    {selected && (
                      <svg viewBox="0 0 10 10" className="h-full w-full p-0.5 text-primary-foreground" fill="none" stroke="currentColor" strokeWidth="1.5">
                        <path d="M1.5 5l2.5 2.5 4.5-4.5" />
                      </svg>
                    )}
                  </div>
                  <div className="min-w-0">
                    <p className="text-sm font-medium leading-tight">{kpi.kpiName}</p>
                    <p className="text-xs text-muted-foreground font-mono">{kpi.kpiCode}
                      {kpi.category && <span className="ml-1.5 not-italic">{kpi.category}</span>}
                    </p>
                  </div>
                </button>
              )
            })
          )}
        </div>

        <SheetFooter className="pt-3">
          <Button type="button" variant="outline" onClick={handleClose} disabled={mutation.isPending}>
            Cancel
          </Button>
          <Button onClick={() => mutation.mutate()} disabled={mutation.isPending || isLoading}>
            {mutation.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            {mutation.isPending ? 'Saving…' : 'Save'}
          </Button>
        </SheetFooter>
      </SheetContent>
    </Sheet>
  )
}
