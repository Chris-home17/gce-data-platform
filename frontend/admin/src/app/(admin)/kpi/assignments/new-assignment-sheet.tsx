'use client'

import { useEffect, useMemo, useState } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { Loader2, Plus } from 'lucide-react'
import { Button } from '@/components/ui/button'
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetFooter,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from '@/components/ui/sheet'
import {
  Form,
  FormControl,
  FormDescription,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from '@/components/ui/form'
import { Input } from '@/components/ui/input'
import { Textarea } from '@/components/ui/textarea'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Switch } from '@/components/ui/switch'
import { api } from '@/lib/api'

const schema = z.object({
  kpiCode: z.string().min(1, 'Select a KPI'),
  periodScheduleId: z.number().int().positive('Select a schedule'),
  accountCode: z.string().min(1, 'Select an account'),
  isAccountWide: z.boolean(),
  orgUnitCode: z.string().optional(),
  isRequired: z.boolean(),
  targetValue: z.number().nullable().optional(),
  thresholdGreen: z.number().nullable().optional(),
  thresholdAmber: z.number().nullable().optional(),
  thresholdRed: z.number().nullable().optional(),
  thresholdDirection: z.enum(['Higher', 'Lower', 'none']).optional(),
  submitterGuidance: z.string().max(1000).optional(),
  overrideKpiName: z.boolean(),
  customKpiName: z.string().max(200).optional(),
  customKpiDescription: z.string().max(1000).optional(),
  materializeNow: z.boolean(),
}).superRefine((d, ctx) => {
  if (!d.isAccountWide && !d.orgUnitCode) {
    ctx.addIssue({ code: 'custom', path: ['orgUnitCode'], message: 'Select a site' })
  }
  if (d.overrideKpiName && !d.customKpiName?.trim()) {
    ctx.addIssue({ code: 'custom', path: ['customKpiName'], message: 'Display name is required when override is enabled' })
  }
})

type FormValues = z.infer<typeof schema>

function parseOptionalNumber(value: string): number | null {
  const n = parseFloat(value)
  return isNaN(n) ? null : n
}

function formatScheduleRef(periodScheduleId: number) {
  return `SCH-${periodScheduleId}`
}

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

export function NewAssignmentSheet() {
  const [open, setOpen] = useState(false)
  const [kpiSearch, setKpiSearch] = useState('')
  const [categoryFilter, setCategoryFilter] = useState<string>('all')
  const queryClient = useQueryClient()

  const { data: defsData } = useQuery({
    queryKey: ['kpi', 'definitions'],
    queryFn: () => api.kpi.definitions.list(),
    enabled: open,
  })

  const { data: accountsData } = useQuery({
    queryKey: ['accounts'],
    queryFn: () => api.accounts.list(),
    enabled: open,
  })

  const { data: schedulesData } = useQuery({
    queryKey: ['kpi', 'period-schedules'],
    queryFn: () => api.kpi.periods.schedules.list(),
    enabled: open,
  })

  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      kpiCode: '',
      periodScheduleId: 0,
      accountCode: '',
      isAccountWide: true,
      orgUnitCode: '',
      isRequired: true,
      thresholdDirection: 'none',
      submitterGuidance: '',
      overrideKpiName: false,
      customKpiName: '',
      customKpiDescription: '',
      materializeNow: true,
    },
  })

  const watchedAccountCode = form.watch('accountCode')
  const isAccountWide = form.watch('isAccountWide')
  const overrideKpiName = form.watch('overrideKpiName')
  const selectedAccount = accountsData?.items.find((a) => a.accountCode === watchedAccountCode)

  const { data: sitesData } = useQuery({
    queryKey: ['org-units', 'sites', selectedAccount?.accountId],
    queryFn: () => api.orgUnits.list({ accountId: selectedAccount!.accountId }),
    enabled: open && !isAccountWide && !!selectedAccount,
  })

  const sites = sitesData?.items.filter((u) => u.orgUnitType === 'Site' && u.isActive) ?? []
  const activeSchedules = schedulesData?.items.filter((s) => s.isActive) ?? []
  const activeKpis = defsData?.items.filter((d) => d.isActive) ?? []
  const activeAccounts = accountsData?.items.filter((a) => a.isActive) ?? []
  const categories = useMemo(
    () => Array.from(new Set(activeKpis.map((k) => k.category).filter(Boolean))).sort(),
    [activeKpis],
  )
  const filteredKpis = useMemo(() => {
    const search = kpiSearch.trim().toLowerCase()
    return activeKpis.filter((k) => {
      const matchesCategory = categoryFilter === 'all' || k.category === categoryFilter
      if (!matchesCategory) return false
      if (!search) return true
      return k.kpiCode.toLowerCase().includes(search)
        || k.kpiName.toLowerCase().includes(search)
        || (k.category ?? '').toLowerCase().includes(search)
    })
  }, [activeKpis, categoryFilter, kpiSearch])

  const mutation = useMutation({
    mutationFn: (values: FormValues) =>
      api.kpi.assignments.templates.create({
        kpiCode: values.kpiCode,
        periodScheduleId: values.periodScheduleId,
        accountCode: values.accountCode,
        orgUnitCode: values.isAccountWide ? null : (values.orgUnitCode ?? null),
        orgUnitType: values.isAccountWide ? undefined : 'Site',
        isRequired: values.isRequired,
        targetValue: values.targetValue ?? null,
        thresholdGreen: values.thresholdGreen ?? null,
        thresholdAmber: values.thresholdAmber ?? null,
        thresholdRed: values.thresholdRed ?? null,
        thresholdDirection: values.thresholdDirection === 'none' ? null : values.thresholdDirection,
        submitterGuidance: values.submitterGuidance || undefined,
        customKpiName: values.overrideKpiName ? (values.customKpiName || null) : null,
        customKpiDescription: values.overrideKpiName ? (values.customKpiDescription || null) : null,
        materializeNow: values.materializeNow,
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['kpi', 'assignment-templates'] })
      queryClient.invalidateQueries({ queryKey: ['kpi', 'assignments'] })
      toast.success('Recurring KPI template saved.')
      setOpen(false)
      form.reset()
      setKpiSearch('')
      setCategoryFilter('all')
    },
    onError: (err: Error) => toast.error(err.message ?? 'Failed to save template.'),
  })

  function handleOpenChange(value: boolean) {
    if (!value) {
      form.reset()
      mutation.reset()
      setKpiSearch('')
      setCategoryFilter('all')
    }
    setOpen(value)
  }

  const selectedKpi = activeKpis.find((k) => k.kpiCode === form.watch('kpiCode'))
  const supportsThresholds = ['Numeric', 'Percentage', 'Currency'].includes(selectedKpi?.dataType ?? '')

  // Clear threshold fields when switching to a KPI that doesn't support them
  useEffect(() => {
    if (selectedKpi && !supportsThresholds) {
      form.resetField('targetValue')
      form.resetField('thresholdGreen')
      form.resetField('thresholdAmber')
      form.resetField('thresholdRed')
      form.resetField('thresholdDirection')
    }
  }, [selectedKpi?.dataType]) // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <Sheet open={open} onOpenChange={handleOpenChange}>
      <SheetTrigger asChild>
        <Button>
          <Plus className="mr-2 h-4 w-4" />
          New Template
        </Button>
      </SheetTrigger>

      <SheetContent className="w-full sm:max-w-xl overflow-y-auto">
        <SheetHeader>
          <SheetTitle>Recurring KPI Template</SheetTitle>
          <SheetDescription>
            Link a KPI to a cadence schedule once, then let the platform materialize the generated reporting instances automatically.
          </SheetDescription>
        </SheetHeader>

        <Form {...form}>
          <form onSubmit={form.handleSubmit((v) => mutation.mutate(v))} className="mt-6 space-y-4">

            {/* ── KPI ─────────────────────────────────────────── */}
            <SectionHeading>KPI</SectionHeading>

            <FormField
              control={form.control}
              name="kpiCode"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>KPI</FormLabel>
                  <div className="flex items-center gap-2 mb-1">
                    <Select value={categoryFilter} onValueChange={setCategoryFilter}>
                      <SelectTrigger className="h-8 w-44 text-xs">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="all">All categories</SelectItem>
                        {categories.map((category) => (
                          <SelectItem key={category} value={category!}>
                            {category}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    <span className="text-xs text-muted-foreground">
                      {filteredKpis.length} KPI{filteredKpis.length !== 1 ? 's' : ''}
                    </span>
                  </div>
                  <Select value={field.value} onValueChange={field.onChange}>
                    <FormControl>
                      <SelectTrigger>
                        <SelectValue placeholder="Select a KPI" />
                      </SelectTrigger>
                    </FormControl>
                    <SelectContent>
                      <div className="px-2 pb-2">
                        <Input
                          value={kpiSearch}
                          onChange={(e) => setKpiSearch(e.target.value)}
                          onKeyDown={(e) => e.stopPropagation()}
                          placeholder="Search KPIs…"
                        />
                      </div>
                      {filteredKpis.map((k) => (
                        <SelectItem key={k.kpiCode} value={k.kpiCode}>
                          <span className="mr-2 font-mono">{k.kpiCode}</span>
                          <span className="text-muted-foreground">{k.kpiName}</span>
                        </SelectItem>
                      ))}
                      {filteredKpis.length === 0 && (
                        <div className="px-2 py-2 text-sm text-muted-foreground">
                          No KPIs match the current filter.
                        </div>
                      )}
                    </SelectContent>
                  </Select>
                  <FormMessage />
                </FormItem>
              )}
            />

            {/* ── Scope ───────────────────────────────────────── */}
            <SectionHeading>Scope</SectionHeading>

            <FormField
              control={form.control}
              name="accountCode"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Account</FormLabel>
                  <Select
                    value={field.value}
                    onValueChange={(value) => {
                      field.onChange(value)
                      form.resetField('orgUnitCode')
                    }}
                  >
                    <FormControl>
                      <SelectTrigger>
                        <SelectValue placeholder="Select an account" />
                      </SelectTrigger>
                    </FormControl>
                    <SelectContent>
                      {activeAccounts.map((account) => (
                        <SelectItem key={account.accountCode} value={account.accountCode}>
                          <span className="mr-2 font-mono">{account.accountCode}</span>
                          <span className="text-muted-foreground">{account.accountName}</span>
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <FormMessage />
                </FormItem>
              )}
            />

            <FormField
              control={form.control}
              name="isAccountWide"
              render={({ field }) => (
                <FormItem className="flex items-center justify-between rounded-md border px-3 py-2">
                  <div>
                    <FormLabel className="text-sm">Account-wide</FormLabel>
                    <FormDescription className="text-xs">
                      Use one template for the whole account, or turn this off to target a single site.
                    </FormDescription>
                  </div>
                  <FormControl>
                    <Switch
                      checked={field.value}
                      onCheckedChange={(value) => {
                        field.onChange(value)
                        form.resetField('orgUnitCode')
                      }}
                    />
                  </FormControl>
                </FormItem>
              )}
            />

            {!isAccountWide && (
              <FormField
                control={form.control}
                name="orgUnitCode"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Site</FormLabel>
                    {!watchedAccountCode ? (
                      <p className="text-xs text-muted-foreground">Select an account first.</p>
                    ) : sites.length === 0 ? (
                      <p className="text-xs text-muted-foreground">No active sites for this account.</p>
                    ) : (
                      <Select value={field.value} onValueChange={field.onChange}>
                        <FormControl>
                          <SelectTrigger>
                            <SelectValue placeholder="Select a site" />
                          </SelectTrigger>
                        </FormControl>
                        <SelectContent>
                          {sites.map((site) => (
                            <SelectItem key={site.orgUnitCode} value={site.orgUnitCode}>
                              <span className="mr-2 font-mono">{site.orgUnitCode}</span>
                              <span className="text-muted-foreground">{site.orgUnitName}</span>
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    )}
                    <FormMessage />
                  </FormItem>
                )}
              />
            )}

            <FormField
              control={form.control}
              name="periodScheduleId"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Schedule</FormLabel>
                  <Select value={field.value ? String(field.value) : ''} onValueChange={(value) => field.onChange(parseInt(value, 10))}>
                    <FormControl>
                      <SelectTrigger>
                        <SelectValue placeholder="Select a cadence schedule" />
                      </SelectTrigger>
                    </FormControl>
                    <SelectContent>
                      {activeSchedules.map((schedule) => (
                        <SelectItem key={schedule.periodScheduleId} value={String(schedule.periodScheduleId)}>
                          {schedule.scheduleName} · {formatScheduleRef(schedule.periodScheduleId)}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <FormDescription>
                    Controls when instances are generated for this KPI.
                  </FormDescription>
                  <FormMessage />
                </FormItem>
              )}
            />

            <FormField
              control={form.control}
              name="isRequired"
              render={({ field }) => (
                <FormItem className="flex items-center justify-between rounded-md border px-3 py-2">
                  <div>
                    <FormLabel className="text-sm">Required</FormLabel>
                    <FormDescription className="text-xs">
                      Submitters must provide a value for this KPI each period.
                    </FormDescription>
                  </div>
                  <FormControl>
                    <Switch checked={field.value} onCheckedChange={field.onChange} />
                  </FormControl>
                </FormItem>
              )}
            />

            {/* ── Thresholds ──────────────────────────────────── */}
            <SectionHeading>Thresholds</SectionHeading>

            {!selectedKpi ? null : !supportsThresholds ? (
              <p className="text-xs text-muted-foreground rounded-md border border-dashed px-3 py-2">
                Thresholds (target, green/amber/red, direction) are not applicable for <strong>{selectedKpi.dataType}</strong> KPIs.
              </p>
            ) : (
              <>
                <div className="grid grid-cols-2 gap-3">
                  <FormField
                    control={form.control}
                    name="targetValue"
                    render={({ field }) => (
                      <FormItem>
                        <FormLabel>Target value</FormLabel>
                        <FormControl>
                          <Input type="number" step="0.01" value={field.value ?? ''} onChange={(e) => field.onChange(parseOptionalNumber(e.target.value))} />
                        </FormControl>
                        <FormMessage />
                      </FormItem>
                    )}
                  />

                  <FormField
                    control={form.control}
                    name="thresholdDirection"
                    render={({ field }) => (
                      <FormItem>
                        <FormLabel>Direction</FormLabel>
                        <Select value={field.value ?? 'none'} onValueChange={field.onChange}>
                          <FormControl>
                            <SelectTrigger>
                              <SelectValue />
                            </SelectTrigger>
                          </FormControl>
                          <SelectContent>
                            <SelectItem value="none">Use KPI default</SelectItem>
                            <SelectItem value="Higher">Higher is better</SelectItem>
                            <SelectItem value="Lower">Lower is better</SelectItem>
                          </SelectContent>
                        </Select>
                        <FormMessage />
                      </FormItem>
                    )}
                  />
                </div>

                <div className="grid grid-cols-3 gap-3">
                  <FormField
                    control={form.control}
                    name="thresholdGreen"
                    render={({ field }) => (
                      <FormItem>
                        <FormLabel>Green</FormLabel>
                        <FormControl>
                          <Input type="number" step="0.01" value={field.value ?? ''} onChange={(e) => field.onChange(parseOptionalNumber(e.target.value))} />
                        </FormControl>
                        <FormMessage />
                      </FormItem>
                    )}
                  />
                  <FormField
                    control={form.control}
                    name="thresholdAmber"
                    render={({ field }) => (
                      <FormItem>
                        <FormLabel>Amber</FormLabel>
                        <FormControl>
                          <Input type="number" step="0.01" value={field.value ?? ''} onChange={(e) => field.onChange(parseOptionalNumber(e.target.value))} />
                        </FormControl>
                        <FormMessage />
                      </FormItem>
                    )}
                  />
                  <FormField
                    control={form.control}
                    name="thresholdRed"
                    render={({ field }) => (
                      <FormItem>
                        <FormLabel>Red</FormLabel>
                        <FormControl>
                          <Input type="number" step="0.01" value={field.value ?? ''} onChange={(e) => field.onChange(parseOptionalNumber(e.target.value))} />
                        </FormControl>
                        <FormMessage />
                      </FormItem>
                    )}
                  />
                </div>
              </>
            )}

            {/* ── Display ─────────────────────────────────────── */}
            <SectionHeading>Display</SectionHeading>

            <FormField
              control={form.control}
              name="overrideKpiName"
              render={({ field }) => (
                <FormItem className="flex items-center justify-between rounded-md border px-3 py-2">
                  <div>
                    <FormLabel className="text-sm">Override KPI display name</FormLabel>
                    <FormDescription className="text-xs">
                      Use a custom name and description for this account instead of the library default.
                    </FormDescription>
                  </div>
                  <FormControl>
                    <Switch
                      checked={field.value}
                      onCheckedChange={(value) => {
                        field.onChange(value)
                        if (value && selectedKpi) {
                          form.setValue('customKpiName', selectedKpi.kpiName)
                          form.setValue('customKpiDescription', '')
                        } else if (!value) {
                          form.resetField('customKpiName')
                          form.resetField('customKpiDescription')
                        }
                      }}
                    />
                  </FormControl>
                </FormItem>
              )}
            />

            {overrideKpiName && (
              <>
                <FormField
                  control={form.control}
                  name="customKpiName"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Display name</FormLabel>
                      <FormControl>
                        <Input placeholder="Name shown to submitters and in reports" {...field} />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
                <FormField
                  control={form.control}
                  name="customKpiDescription"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Display description <span className="text-muted-foreground font-normal">(optional)</span></FormLabel>
                      <FormControl>
                        <Textarea
                          placeholder="Custom description for this account"
                          className="resize-none"
                          rows={3}
                          {...field}
                        />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
              </>
            )}

            <FormField
              control={form.control}
              name="submitterGuidance"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Submitter guidance <span className="text-muted-foreground font-normal">(optional)</span></FormLabel>
                  <FormControl>
                    <Textarea
                      placeholder="Instructions shown to submitters when entering this KPI"
                      className="resize-none"
                      rows={3}
                      {...field}
                    />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />

            {/* ── Options ─────────────────────────────────────── */}
            <SectionHeading>Options</SectionHeading>

            <FormField
              control={form.control}
              name="materializeNow"
              render={({ field }) => (
                <FormItem className="flex items-center justify-between rounded-md border px-3 py-2">
                  <div>
                    <FormLabel className="text-sm">Materialize now</FormLabel>
                    <FormDescription className="text-xs">
                      Immediately generate reporting instances for existing periods produced by the selected schedule.
                    </FormDescription>
                  </div>
                  <FormControl>
                    <Switch checked={field.value} onCheckedChange={field.onChange} />
                  </FormControl>
                </FormItem>
              )}
            />

            <SheetFooter>
              <Button type="button" variant="outline" onClick={() => handleOpenChange(false)} disabled={mutation.isPending}>
                Cancel
              </Button>
              <Button type="submit" disabled={mutation.isPending}>
                {mutation.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                {mutation.isPending ? 'Saving…' : 'Save Template'}
              </Button>
            </SheetFooter>
          </form>
        </Form>
      </SheetContent>
    </Sheet>
  )
}
