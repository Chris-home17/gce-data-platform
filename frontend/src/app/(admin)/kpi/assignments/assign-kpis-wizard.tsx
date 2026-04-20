'use client'

import { useEffect, useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import {
  AlertCircle,
  ChevronDown,
  ChevronRight,
  Loader2,
  Package,
  Plus,
  Search,
  Sparkles,
  X,
} from 'lucide-react'
import { cn } from '@/lib/utils'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from '@/components/ui/sheet'
import { Switch } from '@/components/ui/switch'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Textarea } from '@/components/ui/textarea'
import { api } from '@/lib/api'
import { parsePackageTags } from '@/types/api'
import type {
  BatchKpiAssignmentTemplateItem,
  KpiDefinition,
  KpiPackageDetail,
  OrgUnit,
} from '@/types/api'

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface WizardContext {
  accountCode: string
  isAccountWide: boolean
  orgUnitCodes: string[]   // empty = nothing selected yet
  periodScheduleId: number | null
  groupName: string | null
}

interface CartPackageEntry {
  type: 'package'
  packageId: number
  packageCode: string
  packageName: string
  kpiCodes: string[]
  kpiItems: Array<{ kpiCode: string; kpiName: string; dataType: string | null; category: string | null }>
  tags: Array<{ tagId: number; tagName: string }>
}

interface CartKpiEntry {
  type: 'kpi'
  kpiCode: string
  kpiName: string
  dataType: string
  category: string | null
}

type CartEntry = CartPackageEntry | CartKpiEntry

interface KpiTailoringValues {
  isRequired: boolean
  targetValue: string
  thresholdGreen: string
  thresholdAmber: string
  thresholdRed: string
  thresholdDirection: 'Higher' | 'Lower' | 'none'
  submitterGuidance: string
  overrideKpiName: boolean
  customKpiName: string
  customKpiDescription: string
}

interface EffectiveKpi {
  kpiCode: string
  kpiName: string
  dataType: string | null
  category: string | null
  sourcePackageId: number | null
  sourcePackageName: string | null
}

function defaultTailoring(): KpiTailoringValues {
  return {
    isRequired: true,
    targetValue: '',
    thresholdGreen: '',
    thresholdAmber: '',
    thresholdRed: '',
    thresholdDirection: 'none',
    submitterGuidance: '',
    overrideKpiName: false,
    customKpiName: '',
    customKpiDescription: '',
  }
}

function isTailoringDirty(v: KpiTailoringValues): boolean {
  return (
    !v.isRequired ||
    v.targetValue !== '' ||
    v.thresholdGreen !== '' ||
    v.thresholdAmber !== '' ||
    v.thresholdRed !== '' ||
    v.thresholdDirection !== 'none' ||
    v.submitterGuidance !== '' ||
    v.overrideKpiName
  )
}

function parseOptionalNumber(s: string): number | null {
  const n = parseFloat(s)
  return isNaN(n) ? null : n
}

function getTailoringErrors(kpi: EffectiveKpi, values: KpiTailoringValues): string[] {
  if (!['Numeric', 'Percentage', 'Currency'].includes(kpi.dataType ?? '')) return []
  const errors: string[] = []
  if (!values.targetValue) errors.push('targetValue')
  if (!values.thresholdGreen) errors.push('thresholdGreen')
  if (!values.thresholdAmber) errors.push('thresholdAmber')
  if (!values.thresholdRed) errors.push('thresholdRed')
  return errors
}

// ---------------------------------------------------------------------------
// Shared sub-components
// ---------------------------------------------------------------------------

function SectionHeading({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex items-center gap-3 pt-2">
      <span className="text-xs font-semibold uppercase tracking-wider text-muted-foreground whitespace-nowrap">
        {children}
      </span>
      <div className="flex-1 border-t" />
    </div>
  )
}

function StepIndicator({ current, steps }: { current: number; steps: string[] }) {
  return (
    <div className="flex items-center gap-1.5 mt-2">
      {steps.map((label, i) => (
        <div key={i} className="flex items-center gap-1.5">
          <div
            className={[
              'flex h-6 w-6 items-center justify-center rounded-full text-xs font-semibold',
              i < current
                ? 'bg-primary text-primary-foreground'
                : i === current
                  ? 'bg-primary text-primary-foreground ring-2 ring-primary ring-offset-2'
                  : 'bg-muted text-muted-foreground',
            ].join(' ')}
          >
            {i < current ? '✓' : i + 1}
          </div>
          <span
            className={[
              'hidden text-xs sm:inline',
              i === current ? 'font-medium text-foreground' : 'text-muted-foreground',
            ].join(' ')}
          >
            {label}
          </span>
          {i < steps.length - 1 && (
            <div className={['h-px w-6 flex-shrink-0', i < current ? 'bg-primary' : 'bg-border'].join(' ')} />
          )}
        </div>
      ))}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Step 0 — Context
// ---------------------------------------------------------------------------

interface StepContextProps {
  context: WizardContext
  onChange: (patch: Partial<WizardContext>) => void
  open: boolean
}

function SiteMultiSelect({
  sites,
  selectedCodes,
  onToggle,
  isLoading,
  disabled,
}: {
  sites: OrgUnit[]
  selectedCodes: string[]
  onToggle: (code: string) => void
  isLoading: boolean
  disabled: boolean
}) {
  const [siteSearch, setSiteSearch] = useState('')
  const selectedSet = useMemo(() => new Set(selectedCodes), [selectedCodes])

  const filtered = useMemo(() => {
    const q = siteSearch.trim().toLowerCase()
    if (!q) return sites
    return sites.filter(
      (s) => s.orgUnitCode.toLowerCase().includes(q) || s.orgUnitName.toLowerCase().includes(q),
    )
  }, [sites, siteSearch])

  if (disabled) {
    return <p className="text-xs text-muted-foreground">Select an account first.</p>
  }
  if (isLoading) {
    return <p className="text-xs text-muted-foreground">Loading sites…</p>
  }
  if (sites.length === 0) {
    return <p className="text-xs text-muted-foreground">No active sites for this account.</p>
  }

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between">
        <div className="relative flex-1 max-w-xs">
          <Search className="absolute left-2.5 top-2 h-3.5 w-3.5 text-muted-foreground" />
          <Input
            className="pl-8 h-8 text-sm"
            placeholder="Filter sites…"
            value={siteSearch}
            onChange={(e) => setSiteSearch(e.target.value)}
          />
        </div>
        {selectedCodes.length > 0 && (
          <span className="text-xs text-muted-foreground">
            {selectedCodes.length} site{selectedCodes.length !== 1 ? 's' : ''} selected
          </span>
        )}
      </div>
      <div className="rounded-md border max-h-52 overflow-y-auto divide-y">
        {filtered.map((s) => {
          const checked = selectedSet.has(s.orgUnitCode)
          return (
            <button
              key={s.orgUnitCode}
              type="button"
              onClick={() => onToggle(s.orgUnitCode)}
              className={[
                'w-full flex items-center gap-3 px-3 py-2 text-left hover:bg-muted/40 transition-colors',
                checked ? 'bg-primary/5' : '',
              ].join(' ')}
            >
              <div
                className={[
                  'h-4 w-4 shrink-0 rounded border flex items-center justify-center',
                  checked ? 'bg-primary border-primary' : 'border-input',
                ].join(' ')}
              >
                {checked && (
                  <svg className="h-2.5 w-2.5 text-primary-foreground" fill="none" viewBox="0 0 12 12">
                    <path d="M1 6l3.5 3.5L11 2" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                )}
              </div>
              <span className="font-mono text-xs text-muted-foreground shrink-0">{s.orgUnitCode}</span>
              <span className="text-sm truncate">{s.orgUnitName}</span>
            </button>
          )
        })}
        {filtered.length === 0 && (
          <p className="text-xs text-muted-foreground text-center py-4">No sites match the filter.</p>
        )}
      </div>
    </div>
  )
}

function StepContext({ context, onChange, open }: StepContextProps) {
  const accountsQuery = useQuery({
    queryKey: ['accounts'],
    queryFn: () => api.accounts.list(),
    enabled: open,
  })
  const schedulesQuery = useQuery({
    queryKey: ['kpi', 'period-schedules'],
    queryFn: () => api.kpi.periods.schedules.list(),
    enabled: open,
  })
  const selectedAccount = useMemo(
    () => (accountsQuery.data?.items ?? []).find((a) => a.accountCode === context.accountCode),
    [accountsQuery.data, context.accountCode],
  )
  const sitesQuery = useQuery({
    queryKey: ['org-units', 'sites', selectedAccount?.accountId],
    queryFn: () => api.orgUnits.list({ accountId: selectedAccount!.accountId }),
    enabled: open && !context.isAccountWide && !!selectedAccount,
  })
  const groupsQuery = useQuery({
    queryKey: ['kpi', 'assignment-groups', selectedAccount?.accountId],
    queryFn: () => api.kpi.assignments.groups({ accountId: selectedAccount!.accountId }),
    enabled: open && !!selectedAccount,
  })
  const existingGroups = useMemo(
    () => (groupsQuery.data?.items ?? []).map((g) => g.groupName),
    [groupsQuery.data],
  )

  const activeAccounts = useMemo(
    () => (accountsQuery.data?.items ?? []).filter((a) => a.isActive),
    [accountsQuery.data],
  )
  const activeSchedules = useMemo(
    () => (schedulesQuery.data?.items ?? []).filter((s) => s.isActive),
    [schedulesQuery.data],
  )
  const sites = useMemo(
    () => (sitesQuery.data?.items ?? []).filter((u) => u.orgUnitType === 'Site' && u.isActive),
    [sitesQuery.data],
  )

  function toggleSite(code: string) {
    const current = context.orgUnitCodes
    const next = current.includes(code) ? current.filter((c) => c !== code) : [...current, code]
    onChange({ orgUnitCodes: next })
  }

  return (
    <div className="space-y-5">
      <p className="text-sm text-muted-foreground">
        Choose which account and scope these KPI assignments will apply to, and which cadence schedule drives recurrence.
      </p>

      <SectionHeading>Scope</SectionHeading>

      <div className="space-y-3">
        <div className="space-y-1.5">
          <label className="text-sm font-medium">Account</label>
          <Select
            value={context.accountCode}
            onValueChange={(v) => onChange({ accountCode: v, orgUnitCodes: [] })}
          >
            <SelectTrigger>
              <SelectValue placeholder="Select an account" />
            </SelectTrigger>
            <SelectContent>
              {activeAccounts.map((a) => (
                <SelectItem key={a.accountCode} value={a.accountCode}>
                  <span className="mr-2 font-mono">{a.accountCode}</span>
                  <span className="text-muted-foreground">{a.accountName}</span>
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>

        <div className="flex items-center justify-between rounded-md border px-3 py-2.5">
          <div>
            <p className="text-sm font-medium">Account-wide</p>
            <p className="text-xs text-muted-foreground mt-0.5">
              Apply to all sites; or turn off to select specific sites.
            </p>
          </div>
          <Switch
            checked={context.isAccountWide}
            onCheckedChange={(v) => onChange({ isAccountWide: v, orgUnitCodes: [] })}
          />
        </div>

        {!context.isAccountWide && (
          <div className="space-y-1.5">
            <label className="text-sm font-medium">Sites</label>
            <SiteMultiSelect
              sites={sites}
              selectedCodes={context.orgUnitCodes}
              onToggle={toggleSite}
              isLoading={sitesQuery.isLoading}
              disabled={!context.accountCode}
            />
          </div>
        )}
      </div>

      <SectionHeading>Schedule</SectionHeading>

      <div className="space-y-1.5">
        <label className="text-sm font-medium">Period Schedule</label>
        <Select
          value={context.periodScheduleId ? String(context.periodScheduleId) : ''}
          onValueChange={(v) => onChange({ periodScheduleId: parseInt(v, 10) })}
        >
          <SelectTrigger>
            <SelectValue placeholder="Select a cadence schedule" />
          </SelectTrigger>
          <SelectContent>
            {activeSchedules.map((s) => (
              <SelectItem key={s.periodScheduleId} value={String(s.periodScheduleId)}>
                {s.scheduleName}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <p className="text-xs text-muted-foreground">Controls when assignment instances are generated.</p>
      </div>

      <SectionHeading>Group <span className="font-normal text-muted-foreground">(optional)</span></SectionHeading>

      <div className="space-y-1.5">
        <label className="text-sm font-medium">Group name</label>
        <div className="flex gap-2">
          <Input
            placeholder="e.g. Technology, Operational…"
            value={context.groupName ?? ''}
            onChange={(e) => onChange({ groupName: e.target.value || null })}
            list="group-suggestions"
            className="flex-1"
          />
          {context.groupName && (
            <Button variant="ghost" size="icon" onClick={() => onChange({ groupName: null })} title="Remove group">
              <X className="h-4 w-4" />
            </Button>
          )}
        </div>
        <datalist id="group-suggestions">
          {existingGroups.map((g) => (
            <option key={g} value={g} />
          ))}
        </datalist>
        <p className="text-xs text-muted-foreground">
          Assign this set of KPIs to a named group. Create a separate assignment with a different group name for other teams on the same account.
        </p>
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Step 1 — Build KPI Set
// ---------------------------------------------------------------------------

interface StepBuildKpiSetProps {
  cart: CartEntry[]
  blockedKpiCodes: Set<string>
  onAddPackage: (detail: KpiPackageDetail) => void
  onRemovePackage: (packageId: number) => void
  onAddKpi: (kpi: KpiDefinition) => void
  onRemoveKpi: (kpiCode: string) => void
  open: boolean
}

function StepBuildKpiSet({
  cart,
  blockedKpiCodes,
  onAddPackage,
  onRemovePackage,
  onAddKpi,
  onRemoveKpi,
  open,
}: StepBuildKpiSetProps) {
  const [kpiSearch, setKpiSearch] = useState('')
  const [categoryFilter, setCategoryFilter] = useState('all')
  const [expandedPackageIds, setExpandedPackageIds] = useState<Set<number>>(new Set())
  const [loadingPackageId, setLoadingPackageId] = useState<number | null>(null)

  const packagesQuery = useQuery({
    queryKey: ['kpi', 'packages'],
    queryFn: () => api.kpi.packages.list(),
    enabled: open,
  })
  const definitionsQuery = useQuery({
    queryKey: ['kpi', 'definitions'],
    queryFn: () => api.kpi.definitions.list(),
    enabled: open,
  })

  const activePackages = useMemo(
    () => (packagesQuery.data?.items ?? []).filter((p) => p.isActive),
    [packagesQuery.data],
  )
  const activeKpis = useMemo(
    () => (definitionsQuery.data?.items ?? []).filter((d) => d.isActive),
    [definitionsQuery.data],
  )
  const categories = useMemo(
    () => Array.from(new Set(activeKpis.map((k) => k.category).filter(Boolean))).sort() as string[],
    [activeKpis],
  )
  const filteredKpis = useMemo(() => {
    const search = kpiSearch.trim().toLowerCase()
    return activeKpis.filter((k) => {
      const matchesCat = categoryFilter === 'all' || k.category === categoryFilter
      if (!matchesCat) return false
      if (!search) return true
      return (
        k.kpiCode.toLowerCase().includes(search) ||
        k.kpiName.toLowerCase().includes(search) ||
        (k.category ?? '').toLowerCase().includes(search)
      )
    })
  }, [activeKpis, categoryFilter, kpiSearch])

  const cartPackageIds = useMemo(
    () => new Set(cart.filter((e): e is CartPackageEntry => e.type === 'package').map((e) => e.packageId)),
    [cart],
  )
  const cartStandaloneKpiCodes = useMemo(
    () => new Set(cart.filter((e): e is CartKpiEntry => e.type === 'kpi').map((e) => e.kpiCode)),
    [cart],
  )

  async function handleAddPackage(packageId: number) {
    setLoadingPackageId(packageId)
    try {
      const detail = await api.kpi.packages.get(packageId)
      onAddPackage(detail)
    } catch {
      toast.error('Failed to load package details.')
    } finally {
      setLoadingPackageId(null)
    }
  }

  function togglePackageExpand(packageId: number) {
    setExpandedPackageIds((prev) => {
      const next = new Set(prev)
      if (next.has(packageId)) next.delete(packageId)
      else next.add(packageId)
      return next
    })
  }

  const totalCartKpis = useMemo(() => {
    const codes = new Set<string>()
    for (const entry of cart) {
      if (entry.type === 'kpi') codes.add(entry.kpiCode)
      else entry.kpiCodes.forEach((c) => codes.add(c))
    }
    return codes.size
  }, [cart])

  return (
    <div className="flex h-full flex-col gap-4 lg:flex-row">
      {/* Picker panel */}
      <div className="flex-1 min-w-0">
        <Tabs defaultValue="packages">
          <TabsList className="w-full">
            <TabsTrigger value="packages" className="flex-1">Packages</TabsTrigger>
            <TabsTrigger value="individual" className="flex-1">Individual KPIs</TabsTrigger>
          </TabsList>

          {/* Packages tab */}
          <TabsContent value="packages" className="mt-3">
            <div className="space-y-1.5 max-h-[420px] overflow-y-auto pr-1">
              {activePackages.length === 0 && packagesQuery.isFetched && (
                <p className="text-xs text-muted-foreground py-4 text-center">No active packages.</p>
              )}
              {activePackages.map((pkg) => {
                const isInCart = cartPackageIds.has(pkg.kpiPackageId)
                return (
                  <div
                    key={pkg.kpiPackageId}
                    className="flex items-center gap-2 rounded-md border px-3 py-2"
                  >
                    <Package className="h-4 w-4 shrink-0 text-muted-foreground" />
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium truncate">{pkg.packageName}</p>
                      <p className="text-xs text-muted-foreground">
                        {pkg.kpiCount} KPI{pkg.kpiCount !== 1 ? 's' : ''}
                        {parsePackageTags(pkg.tagsRaw).map((t) => ` · ${t.tagName}`).join('')}
                      </p>
                    </div>
                    {isInCart ? (
                      <Badge variant="secondary" className="text-xs shrink-0">Added</Badge>
                    ) : (
                      <Button
                        size="sm"
                        variant="outline"
                        className="h-7 px-2 text-xs shrink-0"
                        onClick={() => handleAddPackage(pkg.kpiPackageId)}
                        disabled={loadingPackageId === pkg.kpiPackageId}
                      >
                        {loadingPackageId === pkg.kpiPackageId ? (
                          <Loader2 className="h-3 w-3 animate-spin" />
                        ) : (
                          <Plus className="h-3 w-3 mr-1" />
                        )}
                        Add
                      </Button>
                    )}
                  </div>
                )
              })}
            </div>
          </TabsContent>

          {/* Individual KPIs tab */}
          <TabsContent value="individual" className="mt-3">
            <div className="space-y-2">
              <div className="flex items-center gap-2">
                <div className="relative flex-1">
                  <Search className="absolute left-2.5 top-2.5 h-3.5 w-3.5 text-muted-foreground" />
                  <Input
                    className="pl-8 h-8 text-sm"
                    placeholder="Search KPIs…"
                    value={kpiSearch}
                    onChange={(e) => setKpiSearch(e.target.value)}
                  />
                </div>
                <Select value={categoryFilter} onValueChange={setCategoryFilter}>
                  <SelectTrigger className="h-8 w-36 text-xs">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">All categories</SelectItem>
                    {categories.map((c) => (
                      <SelectItem key={c} value={c}>{c}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

              <div className="space-y-1 max-h-[380px] overflow-y-auto pr-1">
                {filteredKpis.length === 0 && definitionsQuery.isFetched && (
                  <p className="text-xs text-muted-foreground py-4 text-center">No KPIs match the current filter.</p>
                )}
                {filteredKpis.map((k) => {
                  const isBlocked = blockedKpiCodes.has(k.kpiCode)
                  const isStandaloneInCart = cartStandaloneKpiCodes.has(k.kpiCode)
                  return (
                    <div
                      key={k.kpiCode}
                      className={[
                        'flex items-center gap-2 rounded-md border px-3 py-2',
                        isBlocked ? 'opacity-50' : '',
                      ].join(' ')}
                    >
                      <div className="flex-1 min-w-0">
                        <p className="text-xs font-mono text-muted-foreground">{k.kpiCode}</p>
                        <p className="text-sm truncate">{k.kpiName}</p>
                        {k.category && (
                          <Badge variant="outline" className="text-xs mt-0.5">{k.category}</Badge>
                        )}
                      </div>
                      {isBlocked && !isStandaloneInCart ? (
                        <span className="text-xs text-muted-foreground shrink-0">In package</span>
                      ) : isStandaloneInCart ? (
                        <Badge variant="secondary" className="text-xs shrink-0">Added</Badge>
                      ) : (
                        <Button
                          size="sm"
                          variant="outline"
                          className="h-7 px-2 text-xs shrink-0"
                          onClick={() => onAddKpi(k)}
                        >
                          <Plus className="h-3 w-3 mr-1" />
                          Add
                        </Button>
                      )}
                    </div>
                  )
                })}
              </div>
            </div>
          </TabsContent>
        </Tabs>
      </div>

      {/* Cart panel */}
      <div className="lg:w-72 shrink-0">
        <div className="rounded-md border h-full">
          <div className="px-3 py-2 border-b bg-muted/30 flex items-center justify-between">
            <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">KPI Set</p>
            <Badge variant="secondary" className="text-xs">{totalCartKpis} KPI{totalCartKpis !== 1 ? 's' : ''}</Badge>
          </div>
          <div className="p-2 space-y-1.5 max-h-[460px] overflow-y-auto">
            {cart.length === 0 && (
              <p className="text-xs text-muted-foreground text-center py-6">
                Add packages or individual KPIs from the left.
              </p>
            )}
            {cart.map((entry) => {
              if (entry.type === 'package') {
                const isExpanded = expandedPackageIds.has(entry.packageId)
                return (
                  <div key={`pkg-${entry.packageId}`} className="rounded-md border bg-background">
                    <div className="flex items-center gap-2 px-2 py-1.5">
                      <button
                        onClick={() => togglePackageExpand(entry.packageId)}
                        className="shrink-0 text-muted-foreground hover:text-foreground"
                      >
                        {isExpanded ? (
                          <ChevronDown className="h-3.5 w-3.5" />
                        ) : (
                          <ChevronRight className="h-3.5 w-3.5" />
                        )}
                      </button>
                      <Package className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
                      <div className="flex-1 min-w-0">
                        <p className="text-xs font-medium truncate">{entry.packageName}</p>
                        <p className="text-xs text-muted-foreground">
                          {entry.kpiCodes.length} KPI{entry.kpiCodes.length !== 1 ? 's' : ''}
                          {entry.tags.length > 0 && ` · ${entry.tags.map((t) => t.tagName).join(', ')}`}
                        </p>
                      </div>
                      <button
                        onClick={() => onRemovePackage(entry.packageId)}
                        className="shrink-0 text-muted-foreground hover:text-destructive"
                      >
                        <X className="h-3.5 w-3.5" />
                      </button>
                    </div>
                    {isExpanded && (
                      <div className="border-t px-2 pb-1.5 pt-1 space-y-0.5">
                        {entry.kpiItems.map((k) => (
                          <p key={k.kpiCode} className="text-xs text-muted-foreground font-mono pl-5 truncate">
                            {k.kpiCode} — {k.kpiName}
                          </p>
                        ))}
                      </div>
                    )}
                  </div>
                )
              }
              return (
                <div key={`kpi-${entry.kpiCode}`} className="flex items-center gap-2 rounded-md border px-2 py-1.5">
                  <div className="flex-1 min-w-0">
                    <p className="text-xs font-mono text-muted-foreground">{entry.kpiCode}</p>
                    <p className="text-xs truncate">{entry.kpiName}</p>
                  </div>
                  <button
                    onClick={() => onRemoveKpi(entry.kpiCode)}
                    className="shrink-0 text-muted-foreground hover:text-destructive"
                  >
                    <X className="h-3.5 w-3.5" />
                  </button>
                </div>
              )
            })}
          </div>
        </div>
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Per-KPI tailoring row
// ---------------------------------------------------------------------------

interface KpiTailoringRowProps {
  kpi: EffectiveKpi
  values: KpiTailoringValues
  onChange: (patch: Partial<KpiTailoringValues>) => void
  fieldErrors: string[]
  showErrors: boolean
}

function KpiTailoringRow({ kpi, values, onChange, fieldErrors, showErrors }: KpiTailoringRowProps) {
  const [expanded, setExpanded] = useState(false)
  const isDirty = isTailoringDirty(values)
  const supportsThresholds = ['Numeric', 'Percentage', 'Currency'].includes(kpi.dataType ?? '')
  const hasErrors = showErrors && fieldErrors.length > 0

  useEffect(() => {
    if (hasErrors) setExpanded(true)
  }, [hasErrors])

  const err = (field: string) => showErrors && fieldErrors.includes(field)

  return (
    <div className="rounded-md border">
      <button
        onClick={() => setExpanded((v) => !v)}
        className="w-full flex items-center gap-3 px-3 py-2.5 text-left hover:bg-muted/30 transition-colors rounded-md"
      >
        {expanded ? (
          <ChevronDown className="h-4 w-4 shrink-0 text-muted-foreground" />
        ) : (
          <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
        )}
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <span className="text-xs font-mono text-muted-foreground">{kpi.kpiCode}</span>
            <span className="text-sm font-medium truncate">{kpi.kpiName}</span>
          </div>
          <div className="flex items-center gap-1.5 mt-0.5 flex-wrap">
            {kpi.category && (
              <Badge variant="outline" className="text-xs py-0">{kpi.category}</Badge>
            )}
            {kpi.sourcePackageName && (
              <Badge variant="secondary" className="text-xs py-0">
                <Package className="h-2.5 w-2.5 mr-1" />
                {kpi.sourcePackageName}
              </Badge>
            )}
            {isDirty && !hasErrors && (
              <Badge className="text-xs py-0 bg-primary/10 text-primary border-primary/20">
                <Sparkles className="h-2.5 w-2.5 mr-1" />
                Customised
              </Badge>
            )}
            {hasErrors && (
              <Badge className="text-xs py-0 bg-destructive/10 text-destructive border-destructive/20">
                <AlertCircle className="h-2.5 w-2.5 mr-1" />
                Required fields missing
              </Badge>
            )}
          </div>
        </div>
        <div className="flex items-center gap-2 shrink-0" onClick={(e) => e.stopPropagation()}>
          <span className="text-xs text-muted-foreground">Required</span>
          <Switch
            checked={values.isRequired}
            onCheckedChange={(v) => onChange({ isRequired: v })}
          />
        </div>
      </button>

      {expanded && (
        <div className="border-t px-3 pb-4 pt-3 space-y-4">
          {/* Thresholds */}
          <SectionHeading>Thresholds</SectionHeading>
          {!supportsThresholds ? (
            <p className="text-xs text-muted-foreground rounded-md border border-dashed px-3 py-2">
              Thresholds are not applicable for <strong>{kpi.dataType}</strong> KPIs.
            </p>
          ) : (
            <>
              <div className="grid grid-cols-2 gap-3">
                <div className="space-y-1.5">
                  <label className="text-xs font-medium">
                    Target value <span className="text-destructive">*</span>
                  </label>
                  <input
                    type="number"
                    step="0.01"
                    className={cn(
                      "flex h-9 w-full rounded-md border bg-transparent px-3 py-1 text-sm shadow-sm transition-colors placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring",
                      err('targetValue') ? "border-destructive focus-visible:ring-destructive" : "border-input"
                    )}
                    value={values.targetValue}
                    onChange={(e) => onChange({ targetValue: e.target.value })}
                    placeholder="Required"
                  />
                  {err('targetValue') && <p className="text-xs text-destructive">Required</p>}
                </div>
                <div className="space-y-1.5">
                  <label className="text-xs font-medium">Direction</label>
                  <Select
                    value={values.thresholdDirection}
                    onValueChange={(v) => onChange({ thresholdDirection: v as KpiTailoringValues['thresholdDirection'] })}
                  >
                    <SelectTrigger className="h-9">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="none">Use KPI default</SelectItem>
                      <SelectItem value="Higher">Higher is better</SelectItem>
                      <SelectItem value="Lower">Lower is better</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
              </div>
              <div className="grid grid-cols-3 gap-3">
                {(['thresholdGreen', 'thresholdAmber', 'thresholdRed'] as const).map((field) => (
                  <div key={field} className="space-y-1.5">
                    <label className="text-xs font-medium capitalize">
                      {field.replace('threshold', '')} <span className="text-destructive">*</span>
                    </label>
                    <input
                      type="number"
                      step="0.01"
                      className={cn(
                        "flex h-9 w-full rounded-md border bg-transparent px-3 py-1 text-sm shadow-sm transition-colors placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring",
                        err(field) ? "border-destructive focus-visible:ring-destructive" : "border-input"
                      )}
                      value={values[field]}
                      onChange={(e) => onChange({ [field]: e.target.value })}
                      placeholder="Required"
                    />
                    {err(field) && <p className="text-xs text-destructive">Required</p>}
                  </div>
                ))}
              </div>
            </>
          )}

          {/* Display */}
          <SectionHeading>Display</SectionHeading>
          <div className="flex items-center justify-between rounded-md border px-3 py-2.5">
            <div>
              <p className="text-sm font-medium">Override KPI display name</p>
              <p className="text-xs text-muted-foreground mt-0.5">Use a custom name for this account.</p>
            </div>
            <Switch
              checked={values.overrideKpiName}
              onCheckedChange={(v) => {
                onChange({
                  overrideKpiName: v,
                  customKpiName: v ? kpi.kpiName : '',
                  customKpiDescription: '',
                })
              }}
            />
          </div>
          {values.overrideKpiName && (
            <div className="space-y-3">
              <div className="space-y-1.5">
                <label className="text-xs font-medium">Display name</label>
                <Input
                  value={values.customKpiName}
                  onChange={(e) => onChange({ customKpiName: e.target.value })}
                  placeholder="Name shown to submitters"
                  maxLength={200}
                />
              </div>
              <div className="space-y-1.5">
                <label className="text-xs font-medium">
                  Display description <span className="font-normal text-muted-foreground">(optional)</span>
                </label>
                <Textarea
                  value={values.customKpiDescription}
                  onChange={(e) => onChange({ customKpiDescription: e.target.value })}
                  placeholder="Custom description for this account"
                  className="resize-none"
                  rows={2}
                  maxLength={1000}
                />
              </div>
            </div>
          )}
          <div className="space-y-1.5">
            <label className="text-xs font-medium">
              Submitter guidance <span className="font-normal text-muted-foreground">(optional)</span>
            </label>
            <Textarea
              value={values.submitterGuidance}
              onChange={(e) => onChange({ submitterGuidance: e.target.value })}
              placeholder="Instructions shown to submitters when entering this KPI"
              className="resize-none"
              rows={2}
              maxLength={1000}
            />
          </div>
        </div>
      )}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Step 2 — Tailor
// ---------------------------------------------------------------------------

interface StepTailorProps {
  effectiveKpis: EffectiveKpi[]
  tailoring: Map<string, KpiTailoringValues>
  materializeNow: boolean
  onTailoringChange: (kpiCode: string, patch: Partial<KpiTailoringValues>) => void
  onMaterializeNowChange: (v: boolean) => void
  onApplyRequiredToAll: (v: boolean) => void
  tailoringErrors: Map<string, string[]>
  showErrors: boolean
}

function StepTailor({
  effectiveKpis,
  tailoring,
  materializeNow,
  onTailoringChange,
  onMaterializeNowChange,
  onApplyRequiredToAll,
  tailoringErrors,
  showErrors,
}: StepTailorProps) {
  return (
    <div className="space-y-4">
      <div className="rounded-md border bg-muted/30 px-3 py-2.5">
        <p className="text-sm text-muted-foreground">
          Configure thresholds, display names, and guidance for each KPI. Expand a row to customise — defaults are applied if left unchanged.
        </p>
      </div>

      <div className="flex items-center gap-3 flex-wrap">
        <Button
          variant="outline"
          size="sm"
          onClick={() => onApplyRequiredToAll(true)}
        >
          Mark all required
        </Button>
        <Button
          variant="outline"
          size="sm"
          onClick={() => onApplyRequiredToAll(false)}
        >
          Mark all optional
        </Button>
      </div>

      {showErrors && tailoringErrors.size > 0 && (
        <div className="flex items-center gap-2 rounded-md border border-destructive/50 bg-destructive/5 px-3 py-2.5">
          <AlertCircle className="h-4 w-4 text-destructive shrink-0" />
          <p className="text-sm text-destructive">
            {tailoringErrors.size === 1
              ? '1 KPI is missing required threshold values. Expand the row to complete it.'
              : `${tailoringErrors.size} KPIs are missing required threshold values. Expand each row to complete them.`}
          </p>
        </div>
      )}
      <div className="space-y-2 max-h-[440px] overflow-y-auto pr-1">
        {effectiveKpis.map((kpi) => (
          <KpiTailoringRow
            key={kpi.kpiCode}
            kpi={kpi}
            values={tailoring.get(kpi.kpiCode) ?? defaultTailoring()}
            onChange={(patch) => onTailoringChange(kpi.kpiCode, patch)}
            fieldErrors={tailoringErrors.get(kpi.kpiCode) ?? []}
            showErrors={showErrors}
          />
        ))}
      </div>

      <SectionHeading>Options</SectionHeading>
      <div className="flex items-center justify-between rounded-md border px-3 py-2.5">
        <div>
          <p className="text-sm font-medium">Materialize now</p>
          <p className="text-xs text-muted-foreground mt-0.5">
            Immediately generate reporting instances for existing periods on this schedule.
          </p>
        </div>
        <Switch checked={materializeNow} onCheckedChange={onMaterializeNowChange} />
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Main wizard
// ---------------------------------------------------------------------------

const STEPS = ['Context', 'KPI Set', 'Tailor']

export function AssignKpisWizard() {
  const [open, setOpen] = useState(false)
  const [step, setStep] = useState(0)
  const [context, setContext] = useState<WizardContext>({
    accountCode: '',
    isAccountWide: true,
    orgUnitCodes: [],
    periodScheduleId: null,
    groupName: null,
  })
  const [cart, setCart] = useState<CartEntry[]>([])
  const [tailoring, setTailoring] = useState<Map<string, KpiTailoringValues>>(new Map())
  const [materializeNow, setMaterializeNow] = useState(true)
  const [showTailoringErrors, setShowTailoringErrors] = useState(false)

  const queryClient = useQueryClient()

  // Existing templates for deduplication
  const templatesQuery = useQuery({
    queryKey: ['kpi', 'assignment-templates'],
    queryFn: () => api.kpi.assignments.templates.list(),
    enabled: open,
    staleTime: 30_000,
  })

  // Phase A: existing template KPI codes for this account/scope+group
  // A KPI is "existing" if already covered in the same group by:
  //   - account-wide scope (effective on every site), OR
  //   - site-specific scope for ALL selected sites
  const existingKpiCodes = useMemo(() => {
    if (!context.accountCode) return new Set<string>()
    // Filter to same account, active, AND same group (NULL-safe)
    const templates = (templatesQuery.data?.items ?? []).filter(
      (t) =>
        t.accountCode === context.accountCode &&
        t.isActive &&
        (context.groupName === null
          ? t.assignmentGroupName === null
          : t.assignmentGroupName === context.groupName),
    )
    if (context.isAccountWide) {
      return new Set(templates.filter((t) => t.isAccountWide).map((t) => t.kpiCode))
    }
    if (context.orgUnitCodes.length === 0) return new Set<string>()
    // Account-wide templates (same group) are effective on every site — always block those KPIs
    const accountWideCodes = new Set(templates.filter((t) => t.isAccountWide).map((t) => t.kpiCode))
    // Site-specific: only block if already assigned to every selected site
    const siteSets = context.orgUnitCodes.map(
      (code) => new Set(templates.filter((t) => t.siteCode === code).map((t) => t.kpiCode)),
    )
    const siteIntersection = new Set<string>()
    if (siteSets.length > 0) {
      for (const code of Array.from(siteSets[0])) {
        if (siteSets.every((s) => s.has(code))) siteIntersection.add(code)
      }
    }
    // Union: blocked if covered account-wide OR already at all selected sites
    return new Set([...Array.from(accountWideCodes), ...Array.from(siteIntersection)])
  }, [templatesQuery.data, context])

  // Phase B: cart KPI codes
  const cartKpiCodes = useMemo(() => {
    const codes = new Set<string>()
    for (const entry of cart) {
      if (entry.type === 'kpi') codes.add(entry.kpiCode)
      else entry.kpiCodes.forEach((c) => codes.add(c))
    }
    return codes
  }, [cart])

  // Combined blocked set (blocks re-adding same kpi individually if already in a package)
  const blockedKpiCodes = useMemo(
    () => new Set([...Array.from(existingKpiCodes), ...Array.from(cartKpiCodes)]),
    [existingKpiCodes, cartKpiCodes],
  )

  // Effective KPIs in the cart (packages resolved + standalone), excluding already-assigned
  const effectiveKpis = useMemo<EffectiveKpi[]>(() => {
    const result: EffectiveKpi[] = []
    const seen = new Set<string>()
    for (const entry of cart) {
      if (entry.type === 'package') {
        for (const item of entry.kpiItems) {
          if (!seen.has(item.kpiCode) && !existingKpiCodes.has(item.kpiCode)) {
            seen.add(item.kpiCode)
            result.push({
              kpiCode: item.kpiCode,
              kpiName: item.kpiName,
              dataType: item.dataType,
              category: item.category,
              sourcePackageId: entry.packageId,
              sourcePackageName: entry.packageName,
            })
          }
        }
      } else {
        if (!seen.has(entry.kpiCode) && !existingKpiCodes.has(entry.kpiCode)) {
          seen.add(entry.kpiCode)
          result.push({
            kpiCode: entry.kpiCode,
            kpiName: entry.kpiName,
            dataType: entry.dataType,
            category: entry.category,
            sourcePackageId: null,
            sourcePackageName: null,
          })
        }
      }
    }
    return result
  }, [cart, existingKpiCodes])

  // Populate tailoring map when entering step 2
  useEffect(() => {
    if (step === 2) {
      setTailoring((prev) => {
        const next = new Map(prev)
        for (const kpi of effectiveKpis) {
          if (!next.has(kpi.kpiCode)) {
            next.set(kpi.kpiCode, defaultTailoring())
          }
        }
        return next
      })
    }
  }, [step, effectiveKpis])

  function updateContext(patch: Partial<WizardContext>) {
    setContext((prev) => ({ ...prev, ...patch }))
  }

  function handleAddPackage(detail: KpiPackageDetail) {
    const pkg = detail.package
    if (cart.some((e) => e.type === 'package' && e.packageId === pkg.kpiPackageId)) return
    setCart((prev) => [
      ...prev,
      {
        type: 'package',
        packageId: pkg.kpiPackageId,
        packageCode: pkg.packageCode,
        packageName: pkg.packageName,
        kpiCodes: detail.items.map((i) => i.kpiCode),
        kpiItems: detail.items.map((i) => ({
          kpiCode: i.kpiCode,
          kpiName: i.kpiName,
          dataType: i.dataType,
          category: i.category,
        })),
        tags: parsePackageTags(pkg.tagsRaw),
      },
    ])
  }

  function handleRemovePackage(packageId: number) {
    setCart((prev) => prev.filter((e) => !(e.type === 'package' && e.packageId === packageId)))
    setTailoring((prev) => {
      const next = new Map(prev)
      // Remove tailoring for KPIs that were only in this package
      const remainingCodes = new Set<string>()
      for (const entry of cart) {
        if (entry.type === 'package' && entry.packageId !== packageId) {
          entry.kpiCodes.forEach((c) => remainingCodes.add(c))
        } else if (entry.type === 'kpi') {
          remainingCodes.add(entry.kpiCode)
        }
      }
      const removedPkg = cart.find((e): e is CartPackageEntry => e.type === 'package' && e.packageId === packageId)
      if (removedPkg) {
        for (const code of removedPkg.kpiCodes) {
          if (!remainingCodes.has(code)) next.delete(code)
        }
      }
      return next
    })
  }

  function handleAddKpi(kpi: { kpiCode: string; kpiName: string; dataType: string; category: string | null }) {
    if (blockedKpiCodes.has(kpi.kpiCode)) return
    if (cart.some((e) => e.type === 'kpi' && e.kpiCode === kpi.kpiCode)) return
    setCart((prev) => [
      ...prev,
      {
        type: 'kpi',
        kpiCode: kpi.kpiCode,
        kpiName: kpi.kpiName,
        dataType: kpi.dataType,
        category: kpi.category,
      },
    ])
  }

  function handleRemoveKpi(kpiCode: string) {
    setCart((prev) => prev.filter((e) => !(e.type === 'kpi' && e.kpiCode === kpiCode)))
    setTailoring((prev) => {
      const next = new Map(prev)
      next.delete(kpiCode)
      return next
    })
  }

  function updateTailoring(kpiCode: string, patch: Partial<KpiTailoringValues>) {
    setTailoring((prev) => {
      const next = new Map(prev)
      next.set(kpiCode, { ...(prev.get(kpiCode) ?? defaultTailoring()), ...patch })
      return next
    })
  }

  function applyRequiredToAll(v: boolean) {
    setTailoring((prev) => {
      const next = new Map(prev)
      for (const kpi of effectiveKpis) {
        const current = prev.get(kpi.kpiCode) ?? defaultTailoring()
        next.set(kpi.kpiCode, { ...current, isRequired: v })
      }
      return next
    })
  }

  const isStep0Valid =
    !!context.accountCode &&
    !!context.periodScheduleId &&
    (context.isAccountWide || context.orgUnitCodes.length > 0)

  const isStep1Valid = effectiveKpis.length > 0

  const tailoringErrors = useMemo(() => {
    const map = new Map<string, string[]>()
    for (const kpi of effectiveKpis) {
      const errors = getTailoringErrors(kpi, tailoring.get(kpi.kpiCode) ?? defaultTailoring())
      if (errors.length > 0) map.set(kpi.kpiCode, errors)
    }
    return map
  }, [effectiveKpis, tailoring])

  const isStep2Valid = tailoringErrors.size === 0

  const commitMutation = useMutation({
    mutationFn: () => {
      const items: BatchKpiAssignmentTemplateItem[] = effectiveKpis.map((kpi) => {
        const t = tailoring.get(kpi.kpiCode) ?? defaultTailoring()
        return {
          kpiCode: kpi.kpiCode,
          kpiPackageId: kpi.sourcePackageId ?? null,
          isRequired: t.isRequired,
          targetValue: parseOptionalNumber(t.targetValue),
          thresholdGreen: parseOptionalNumber(t.thresholdGreen),
          thresholdAmber: parseOptionalNumber(t.thresholdAmber),
          thresholdRed: parseOptionalNumber(t.thresholdRed),
          thresholdDirection: t.thresholdDirection === 'none' ? null : t.thresholdDirection,
          submitterGuidance: t.submitterGuidance || null,
          customKpiName: t.overrideKpiName ? (t.customKpiName || null) : null,
          customKpiDescription: t.overrideKpiName ? (t.customKpiDescription || null) : null,
        }
      })
      return api.kpi.assignments.templates.batchCreate({
        periodScheduleId: context.periodScheduleId!,
        accountCode: context.accountCode,
        orgUnitCode: null,
        orgUnitCodes: context.isAccountWide ? undefined : context.orgUnitCodes,
        orgUnitType: context.isAccountWide ? 'Account' : 'Site',
        materializeNow,
        items,
        assignmentGroupName: context.groupName ?? null,
      })
    },
    onSuccess: (result) => {
      queryClient.invalidateQueries({ queryKey: ['kpi', 'assignment-templates'] })
      queryClient.invalidateQueries({ queryKey: ['kpi', 'assignments'] })
      const msg =
        result.skippedCount > 0
          ? `${result.createdCount} KPI${result.createdCount !== 1 ? 's' : ''} assigned. ${result.skippedCount} skipped (already assigned).`
          : `${result.createdCount} KPI${result.createdCount !== 1 ? 's' : ''} assigned successfully.`
      toast.success(msg)
      handleClose()
    },
    onError: (err: Error) => toast.error(err.message ?? 'Failed to assign KPIs.'),
  })

  function handleClose() {
    setOpen(false)
    setStep(0)
    setContext({ accountCode: '', isAccountWide: true, orgUnitCodes: [], periodScheduleId: null, groupName: null })
    setCart([])
    setTailoring(new Map())
    setMaterializeNow(true)
    setShowTailoringErrors(false)
    commitMutation.reset()
  }

  const assignableCount = effectiveKpis.length
  const skippedByExisting = cartKpiCodes.size - assignableCount

  return (
    <Sheet open={open} onOpenChange={(v) => { if (!v) handleClose(); else setOpen(true) }}>
      <SheetTrigger asChild>
        <Button>
          <Plus className="mr-2 h-4 w-4" />
          Assign KPIs
        </Button>
      </SheetTrigger>

      <SheetContent className="w-full sm:max-w-2xl flex flex-col p-0 gap-0">
        {/* Fixed header */}
        <SheetHeader className="px-6 pt-6 pb-4 border-b">
          <SheetTitle>Assign KPIs</SheetTitle>
          <StepIndicator current={step} steps={STEPS} />
        </SheetHeader>

        {/* Scrollable body */}
        <div className="flex-1 overflow-y-auto px-6 py-5">
          {step === 0 && (
            <StepContext context={context} onChange={updateContext} open={open} />
          )}
          {step === 1 && (
            <StepBuildKpiSet
              cart={cart}
              blockedKpiCodes={blockedKpiCodes}
              onAddPackage={handleAddPackage}
              onRemovePackage={handleRemovePackage}
              onAddKpi={handleAddKpi}
              onRemoveKpi={handleRemoveKpi}
              open={open}
            />
          )}
          {step === 2 && (
            <StepTailor
              effectiveKpis={effectiveKpis}
              tailoring={tailoring}
              materializeNow={materializeNow}
              onTailoringChange={updateTailoring}
              onMaterializeNowChange={setMaterializeNow}
              onApplyRequiredToAll={applyRequiredToAll}
              tailoringErrors={tailoringErrors}
              showErrors={showTailoringErrors}
            />
          )}
        </div>

        {/* Sticky footer */}
        <div className="border-t px-6 py-4 flex items-center justify-between gap-3 bg-background">
          <Button variant="outline" onClick={handleClose} disabled={commitMutation.isPending}>
            Cancel
          </Button>
          <div className="flex items-center gap-2">
            {step > 0 && (
              <Button
                variant="outline"
                onClick={() => {
                  setShowTailoringErrors(false)
                  setStep((s) => (s - 1) as 0 | 1 | 2)
                }}
                disabled={commitMutation.isPending}
              >
                Back
              </Button>
            )}
            {step < 2 ? (
              <Button
                onClick={() => setStep((s) => (s + 1) as 0 | 1 | 2)}
                disabled={step === 0 ? !isStep0Valid : step === 1 ? !isStep1Valid : false}
              >
                Next
              </Button>
            ) : (
              <Button
                onClick={() => {
                  if (!isStep2Valid) {
                    setShowTailoringErrors(true)
                    return
                  }
                  commitMutation.mutate()
                }}
                disabled={commitMutation.isPending || assignableCount === 0}
              >
                {commitMutation.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                {commitMutation.isPending
                  ? 'Assigning…'
                  : skippedByExisting > 0
                    ? `Assign ${assignableCount} KPI${assignableCount !== 1 ? 's' : ''} (${skippedByExisting} skipped)`
                    : `Assign ${assignableCount} KPI${assignableCount !== 1 ? 's' : ''}`}
              </Button>
            )}
          </div>
        </div>
      </SheetContent>
    </Sheet>
  )
}
