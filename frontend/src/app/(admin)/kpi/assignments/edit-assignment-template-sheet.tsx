'use client'

import { useEffect } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { Loader2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetFooter,
  SheetHeader,
  SheetTitle,
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
import { TimeInput } from '@/components/shared/time-input'
import { ThresholdHelp } from '@/components/shared/threshold-help'
import { api } from '@/lib/api'
import type { KpiAssignmentTemplate } from '@/types/api'

interface OptionPointsRow {
  optionValue: string
  points: number | null
  sortOrder?: number | null
}

// Parse the JSON optionPointsRaw column into a typed array. Returns [] on
// missing / malformed JSON so callers can blindly merge with catalog defaults.
function parseOptionPoints(raw: string | null | undefined): OptionPointsRow[] {
  if (!raw) return []
  try {
    const parsed = JSON.parse(raw) as Array<{ value?: string; points?: number; sortOrder?: number }>
    return parsed
      .filter((r) => typeof r.value === 'string' && r.value.length > 0)
      .map((r) => ({
        optionValue: r.value!,
        points: typeof r.points === 'number' ? r.points : 0,
        sortOrder: typeof r.sortOrder === 'number' ? r.sortOrder : null,
      }))
  } catch {
    return []
  }
}

const optionPointsRow = z.object({
  optionValue: z.string().min(1, 'Required'),
  points: z.number().nullable(),
})

const schema = z.object({
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
  // Scoring (Phase 1, KPI scoring layer)
  kpiWeight: z.number().min(0).max(100).optional(),
  scoringMode: z.enum(['Band', 'Linear']).optional(),
  bandPointsGreen: z.number().nullable().optional(),
  bandPointsAmber: z.number().nullable().optional(),
  bandPointsRed: z.number().nullable().optional(),
  booleanYesPoints: z.number().nullable().optional(),
  booleanNoPoints: z.number().nullable().optional(),
  multiSelectScoreRule: z.enum(['Sum', 'Avg', 'Max']).optional(),
  penaliseMissingOnScore: z.boolean(),
  optionPoints: z.array(optionPointsRow).optional(),
}).superRefine((d, ctx) => {
  if (d.overrideKpiName && !d.customKpiName?.trim()) {
    ctx.addIssue({ code: 'custom', path: ['customKpiName'], message: 'Display name is required when override is enabled' })
  }
})

type FormValues = z.infer<typeof schema>

function parseOptionalNumber(value: string): number | null {
  const n = parseFloat(value)
  return isNaN(n) ? null : n
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

export interface EditAssignmentTemplateSheetProps {
  template: KpiAssignmentTemplate | null
  open: boolean
  onClose: () => void
}

// Edits an existing recurring template. The natural-key fields (KPI / schedule /
// account / scope / group name) are read-only — they identify the template and
// can't change. Mutable values cascade to every unsubmitted assignment that
// references this template; submitted rows keep their per-submission threshold
// snapshot, so RAG history is frozen.
export function EditAssignmentTemplateSheet({ template, open, onClose }: EditAssignmentTemplateSheetProps) {
  const queryClient = useQueryClient()

  const supportsThresholds = template
    ? ['Numeric', 'Percentage', 'Currency', 'Time'].includes(template.dataType ?? '')
    : false
  const isTimeKpi = template?.dataType === 'Time'
  const isBooleanKpi = template?.dataType === 'Boolean'
  const isDropDownKpi = template?.dataType === 'DropDown'
  const isTextKpi = template?.dataType === 'Text'

  // KPI definitions catalog — used as the fallback option list when a DropDown
  // template has no per-option points stored yet.
  const { data: kpiDefsData } = useQuery({
    queryKey: ['kpi', 'definitions'],
    queryFn: () => api.kpi.definitions.list(),
    enabled: open && isDropDownKpi,
  })

  // Compute the option list to seed the form with: template's saved options
  // win; fall back to KPI definition catalog options at points=0.
  function seedDropDownOptions(): OptionPointsRow[] {
    if (!template) return []
    const saved = parseOptionPoints(template.optionPointsRaw)
    if (saved.length > 0) return saved
    const def = kpiDefsData?.items.find((k) => k.kpiCode === template.kpiCode)
    return (def?.dropDownOptionsRaw ?? '')
      .split('|')
      .map((o) => o.trim())
      .filter(Boolean)
      .map((optionValue, idx) => ({ optionValue, points: 0, sortOrder: idx }))
  }

  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      isRequired: template?.isRequired ?? true,
      targetValue: template?.targetValue ?? null,
      thresholdGreen: template?.thresholdGreen ?? null,
      thresholdAmber: template?.thresholdAmber ?? null,
      thresholdRed: template?.thresholdRed ?? null,
      thresholdDirection: (template?.effectiveThresholdDirection as FormValues['thresholdDirection']) ?? 'none',
      submitterGuidance: '',
      overrideKpiName: !!template?.customKpiName,
      customKpiName: template?.customKpiName ?? '',
      customKpiDescription: template?.customKpiDescription ?? '',
      kpiWeight: template?.kpiWeight ?? 1,
      scoringMode: (template?.scoringMode as FormValues['scoringMode']) ?? 'Band',
      bandPointsGreen: template?.bandPointsGreen ?? 100,
      bandPointsAmber: template?.bandPointsAmber ?? 50,
      bandPointsRed: template?.bandPointsRed ?? 0,
      booleanYesPoints: template?.booleanYesPoints ?? 100,
      booleanNoPoints: template?.booleanNoPoints ?? 0,
      multiSelectScoreRule: (template?.multiSelectScoreRule as FormValues['multiSelectScoreRule']) ?? 'Sum',
      penaliseMissingOnScore: template?.penaliseMissingOnScore ?? true,
      optionPoints: parseOptionPoints(template?.optionPointsRaw),
    },
  })

  // Re-populate when the user opens a different template (parent reuses the sheet).
  useEffect(() => {
    if (open && template) {
      form.reset({
        isRequired: template.isRequired,
        targetValue: template.targetValue,
        thresholdGreen: template.thresholdGreen,
        thresholdAmber: template.thresholdAmber,
        thresholdRed: template.thresholdRed,
        thresholdDirection: (template.effectiveThresholdDirection as FormValues['thresholdDirection']) ?? 'none',
        submitterGuidance: '',
        overrideKpiName: !!template.customKpiName,
        customKpiName: template.customKpiName ?? '',
        customKpiDescription: template.customKpiDescription ?? '',
        kpiWeight: template.kpiWeight ?? 1,
        scoringMode: (template.scoringMode as FormValues['scoringMode']) ?? 'Band',
        bandPointsGreen: template.bandPointsGreen ?? 100,
        bandPointsAmber: template.bandPointsAmber ?? 50,
        bandPointsRed: template.bandPointsRed ?? 0,
        booleanYesPoints: template.booleanYesPoints ?? 100,
        booleanNoPoints: template.booleanNoPoints ?? 0,
        multiSelectScoreRule: (template.multiSelectScoreRule as FormValues['multiSelectScoreRule']) ?? 'Sum',
        penaliseMissingOnScore: template.penaliseMissingOnScore ?? true,
        optionPoints: parseOptionPoints(template.optionPointsRaw),
      })
    }
  }, [open, template?.assignmentTemplateId]) // eslint-disable-line react-hooks/exhaustive-deps

  // For DropDown templates with no saved option-points, seed from the KPI
  // catalog the first time the catalog data arrives. Skip if the user has
  // already typed values in.
  useEffect(() => {
    if (!open || !isDropDownKpi || !kpiDefsData) return
    if ((form.getValues('optionPoints') ?? []).length > 0) return
    const seeded = seedDropDownOptions()
    if (seeded.length > 0) form.setValue('optionPoints', seeded, { shouldDirty: false })
  }, [open, isDropDownKpi, kpiDefsData, template?.assignmentTemplateId]) // eslint-disable-line react-hooks/exhaustive-deps

  const watchDirection = form.watch('thresholdDirection')
  const overrideKpiName = form.watch('overrideKpiName')

  const mutation = useMutation({
    mutationFn: (values: FormValues) => {
      if (!template) throw new Error('No template selected')
      const allowMulti = isDropDownKpi // multi-select rule only meaningful for dropdown KPIs
      return api.kpi.assignments.templates.update(template.assignmentTemplateId, {
        isRequired: values.isRequired,
        targetValue: supportsThresholds ? (values.targetValue ?? null) : null,
        thresholdGreen: supportsThresholds ? (values.thresholdGreen ?? null) : null,
        thresholdAmber: supportsThresholds ? (values.thresholdAmber ?? null) : null,
        thresholdRed: supportsThresholds ? (values.thresholdRed ?? null) : null,
        thresholdDirection: values.thresholdDirection === 'none' ? null : values.thresholdDirection,
        submitterGuidance: values.submitterGuidance || undefined,
        customKpiName: values.overrideKpiName ? (values.customKpiName || null) : null,
        customKpiDescription: values.overrideKpiName ? (values.customKpiDescription || null) : null,
        // Scoring — only send the fields applicable to this KPI's data type.
        kpiWeight: isTextKpi ? null : (values.kpiWeight ?? 1),
        scoringMode: supportsThresholds ? (values.scoringMode ?? 'Band') : null,
        bandPointsGreen: supportsThresholds ? (values.bandPointsGreen ?? 100) : null,
        bandPointsAmber: supportsThresholds ? (values.bandPointsAmber ?? 50) : null,
        bandPointsRed:   supportsThresholds ? (values.bandPointsRed   ?? 0)   : null,
        booleanYesPoints: isBooleanKpi ? (values.booleanYesPoints ?? 100) : null,
        booleanNoPoints:  isBooleanKpi ? (values.booleanNoPoints  ?? 0)   : null,
        multiSelectScoreRule: allowMulti ? (values.multiSelectScoreRule ?? 'Sum') : null,
        penaliseMissingOnScore: isTextKpi ? null : values.penaliseMissingOnScore,
        optionPoints: isDropDownKpi && (values.optionPoints?.length ?? 0) > 0
          ? values.optionPoints!.map((o) => ({ optionValue: o.optionValue, points: o.points ?? 0 }))
          : null,
      })
    },
    onSuccess: (updated) => {
      queryClient.invalidateQueries({ queryKey: ['kpi', 'assignment-templates'] })
      queryClient.invalidateQueries({ queryKey: ['kpi', 'assignments'] })
      toast.success(`Template "${updated.kpiCode}" updated. Future scoring uses the new thresholds; history is preserved.`)
      onClose()
    },
    onError: (err: Error) => toast.error(err.message ?? 'Failed to update template.'),
  })

  function handleOpenChange(value: boolean) {
    if (!value) {
      mutation.reset()
      onClose()
    }
  }

  if (!template) return null

  return (
    <Sheet open={open} onOpenChange={handleOpenChange}>
      <SheetContent className="w-full sm:max-w-xl overflow-y-auto">
        <SheetHeader>
          <SheetTitle>Edit Recurring Template</SheetTitle>
          <SheetDescription>
            Already-submitted rows keep their original RAG thresholds. New thresholds apply to
            unsubmitted assignments and every future period.
          </SheetDescription>
        </SheetHeader>

        <Form {...form}>
          <form onSubmit={form.handleSubmit((v) => mutation.mutate(v))} className="mt-6 space-y-4">

            {/* ── Identity (read-only) ────────────────────── */}
            <SectionHeading>Identity</SectionHeading>

            <div className="grid grid-cols-2 gap-3 text-sm">
              <div>
                <p className="text-xs font-medium text-muted-foreground">KPI</p>
                <p className="font-mono">{template.kpiCode}</p>
                <p className="text-xs text-muted-foreground">{template.kpiName}</p>
              </div>
              <div>
                <p className="text-xs font-medium text-muted-foreground">Account / Site</p>
                <p className="font-mono">{template.accountCode}</p>
                <p className="text-xs text-muted-foreground">
                  {template.isAccountWide ? 'Account-wide' : `${template.siteCode} — ${template.siteName}`}
                </p>
              </div>
              <div>
                <p className="text-xs font-medium text-muted-foreground">Schedule</p>
                <p>{template.scheduleName ?? '—'}</p>
              </div>
              <div>
                <p className="text-xs font-medium text-muted-foreground">Group</p>
                <p>{template.assignmentGroupName ?? <span className="text-muted-foreground">—</span>}</p>
              </div>
            </div>

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

            {/* ── Thresholds ──────────────────────────────── */}
            <SectionHeading>Thresholds</SectionHeading>

            {!supportsThresholds ? (
              <p className="text-xs text-muted-foreground rounded-md border border-dashed px-3 py-2">
                Thresholds (target, green/amber/red, direction) are not applicable for{' '}
                <strong>{template.dataType}</strong> KPIs.
              </p>
            ) : (
              <>
                <ThresholdHelp
                  direction={watchDirection === 'none' ? null : (watchDirection as 'Higher' | 'Lower')}
                  isTime={isTimeKpi}
                />

                <div className="grid grid-cols-2 gap-3">
                  <FormField
                    control={form.control}
                    name="targetValue"
                    render={({ field }) => (
                      <FormItem>
                        <FormLabel>Target value</FormLabel>
                        <FormControl>
                          {isTimeKpi ? (
                            <TimeInput value={field.value ?? null} onChange={field.onChange} />
                          ) : (
                            <Input type="number" step="0.01" value={field.value ?? ''} onChange={(e) => field.onChange(parseOptionalNumber(e.target.value))} />
                          )}
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
                          {isTimeKpi ? (
                            <TimeInput value={field.value ?? null} onChange={field.onChange} />
                          ) : (
                            <Input type="number" step="0.01" value={field.value ?? ''} onChange={(e) => field.onChange(parseOptionalNumber(e.target.value))} />
                          )}
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
                          {isTimeKpi ? (
                            <TimeInput value={field.value ?? null} onChange={field.onChange} />
                          ) : (
                            <Input type="number" step="0.01" value={field.value ?? ''} onChange={(e) => field.onChange(parseOptionalNumber(e.target.value))} />
                          )}
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
                          {isTimeKpi ? (
                            <TimeInput value={field.value ?? null} onChange={field.onChange} />
                          ) : (
                            <Input type="number" step="0.01" value={field.value ?? ''} onChange={(e) => field.onChange(parseOptionalNumber(e.target.value))} />
                          )}
                        </FormControl>
                        <FormMessage />
                      </FormItem>
                    )}
                  />
                </div>
              </>
            )}

            {/* ── Scoring ─────────────────────────────────── */}
            <SectionHeading>Scoring</SectionHeading>

            {isTextKpi ? (
              <p className="text-xs text-muted-foreground rounded-md border border-dashed px-3 py-2">
                Text KPIs are informational and excluded from the composite score.
              </p>
            ) : (
              <>
                <FormField
                  control={form.control}
                  name="kpiWeight"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>KPI weight</FormLabel>
                      <FormControl>
                        <Input
                          type="number"
                          step="0.1"
                          min={0}
                          value={field.value ?? ''}
                          onChange={(e) => field.onChange(parseOptionalNumber(e.target.value) ?? 1)}
                        />
                      </FormControl>
                      <FormDescription className="text-xs">
                        Multiplier applied to this KPI&apos;s score before category roll-up. 1.0 = standard.
                      </FormDescription>
                      <FormMessage />
                    </FormItem>
                  )}
                />

                {supportsThresholds && (
                  <>
                    <FormField
                      control={form.control}
                      name="scoringMode"
                      render={({ field }) => (
                        <FormItem>
                          <FormLabel>Scoring mode</FormLabel>
                          <Select value={field.value ?? 'Band'} onValueChange={field.onChange}>
                            <FormControl>
                              <SelectTrigger>
                                <SelectValue />
                              </SelectTrigger>
                            </FormControl>
                            <SelectContent>
                              <SelectItem value="Band">Banded — flat per RAG band</SelectItem>
                              <SelectItem value="Linear">Linear — interpolate between bands</SelectItem>
                            </SelectContent>
                          </Select>
                          <FormMessage />
                        </FormItem>
                      )}
                    />
                    <div className="grid grid-cols-3 gap-3">
                      <FormField
                        control={form.control}
                        name="bandPointsGreen"
                        render={({ field }) => (
                          <FormItem>
                            <FormLabel>Green pts</FormLabel>
                            <FormControl>
                              <Input
                                type="number"
                                step="1"
                                value={field.value ?? ''}
                                onChange={(e) => field.onChange(parseOptionalNumber(e.target.value))}
                              />
                            </FormControl>
                            <FormMessage />
                          </FormItem>
                        )}
                      />
                      <FormField
                        control={form.control}
                        name="bandPointsAmber"
                        render={({ field }) => (
                          <FormItem>
                            <FormLabel>Amber pts</FormLabel>
                            <FormControl>
                              <Input
                                type="number"
                                step="1"
                                value={field.value ?? ''}
                                onChange={(e) => field.onChange(parseOptionalNumber(e.target.value))}
                              />
                            </FormControl>
                            <FormMessage />
                          </FormItem>
                        )}
                      />
                      <FormField
                        control={form.control}
                        name="bandPointsRed"
                        render={({ field }) => (
                          <FormItem>
                            <FormLabel>Red pts</FormLabel>
                            <FormControl>
                              <Input
                                type="number"
                                step="1"
                                value={field.value ?? ''}
                                onChange={(e) => field.onChange(parseOptionalNumber(e.target.value))}
                              />
                            </FormControl>
                            <FormMessage />
                          </FormItem>
                        )}
                      />
                    </div>
                  </>
                )}

                {isBooleanKpi && (
                  <div className="grid grid-cols-2 gap-3">
                    <FormField
                      control={form.control}
                      name="booleanYesPoints"
                      render={({ field }) => (
                        <FormItem>
                          <FormLabel>Yes pts</FormLabel>
                          <FormControl>
                            <Input
                              type="number"
                              step="1"
                              value={field.value ?? ''}
                              onChange={(e) => field.onChange(parseOptionalNumber(e.target.value))}
                            />
                          </FormControl>
                          <FormMessage />
                        </FormItem>
                      )}
                    />
                    <FormField
                      control={form.control}
                      name="booleanNoPoints"
                      render={({ field }) => (
                        <FormItem>
                          <FormLabel>No pts</FormLabel>
                          <FormControl>
                            <Input
                              type="number"
                              step="1"
                              value={field.value ?? ''}
                              onChange={(e) => field.onChange(parseOptionalNumber(e.target.value))}
                            />
                          </FormControl>
                          <FormMessage />
                        </FormItem>
                      )}
                    />
                  </div>
                )}

                {isDropDownKpi && (
                  <>
                    <FormField
                      control={form.control}
                      name="multiSelectScoreRule"
                      render={({ field }) => (
                        <FormItem>
                          <FormLabel>Multi-select rule</FormLabel>
                          <Select value={field.value ?? 'Sum'} onValueChange={field.onChange}>
                            <FormControl>
                              <SelectTrigger>
                                <SelectValue />
                              </SelectTrigger>
                            </FormControl>
                            <SelectContent>
                              <SelectItem value="Sum">Sum (capped at 100)</SelectItem>
                              <SelectItem value="Avg">Average of selected</SelectItem>
                              <SelectItem value="Max">Max of selected</SelectItem>
                            </SelectContent>
                          </Select>
                          <FormDescription className="text-xs">
                            How points combine when the submitter picks more than one option (only relevant
                            for multi-select dropdowns).
                          </FormDescription>
                          <FormMessage />
                        </FormItem>
                      )}
                    />

                    <div className="space-y-1.5">
                      <FormLabel className="text-sm">Option points</FormLabel>
                      <FormDescription className="text-xs">
                        Score awarded when the submitter selects each option. Values default to 0 and can be
                        any number; the multi-select rule above decides how they combine.
                      </FormDescription>
                      {(form.watch('optionPoints') ?? []).length === 0 ? (
                        <p className="text-xs text-muted-foreground rounded-md border border-dashed px-3 py-2">
                          This KPI has no dropdown options defined in the catalog. Add options on the KPI
                          definition first, then reopen this sheet.
                        </p>
                      ) : (
                        <div className="space-y-2">
                          {(form.watch('optionPoints') ?? []).map((opt, idx) => (
                            <div key={idx} className="grid grid-cols-[1fr_120px] gap-2 items-center">
                              <Input value={opt.optionValue} readOnly className="font-mono text-sm" />
                              <Input
                                type="number"
                                step="1"
                                value={opt.points ?? ''}
                                onChange={(e) => {
                                  const next = [...(form.getValues('optionPoints') ?? [])]
                                  next[idx] = { ...next[idx], points: parseOptionalNumber(e.target.value) }
                                  form.setValue('optionPoints', next, { shouldDirty: true })
                                }}
                              />
                            </div>
                          ))}
                        </div>
                      )}
                    </div>
                  </>
                )}

                <FormField
                  control={form.control}
                  name="penaliseMissingOnScore"
                  render={({ field }) => (
                    <FormItem className="flex items-center justify-between rounded-md border px-3 py-2">
                      <div>
                        <FormLabel className="text-sm">Penalise missing submissions</FormLabel>
                        <FormDescription className="text-xs">
                          When on, an unsubmitted required assignment counts as 0 points (still in the denominator).
                          When off, it&apos;s excluded from scoring entirely.
                        </FormDescription>
                      </div>
                      <FormControl>
                        <Switch checked={field.value} onCheckedChange={field.onChange} />
                      </FormControl>
                    </FormItem>
                  )}
                />

                {/* Read-only category-weight snapshot for this template */}
                <div className="rounded-md border bg-muted/40 px-3 py-2 text-xs text-muted-foreground">
                  <span className="font-medium">Category weight: </span>
                  <span className="font-mono text-foreground">
                    {template.categoryWeightSnapshot?.toFixed(2) ?? '—'}
                  </span>
                  {template.category && <> ({template.category})</>}
                  <span> — snapshotted when this template was created. Edit on the Category Weights page and click <strong>Re-apply to existing templates</strong> to push a new value to this template&apos;s unsubmitted assignments.</span>
                </div>
              </>
            )}

            {/* ── Display ─────────────────────────────────── */}
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
                        if (value && !form.getValues('customKpiName')) {
                          form.setValue('customKpiName', template.kpiName)
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

            <SheetFooter className="pt-2">
              <Button type="button" variant="outline" onClick={onClose} disabled={mutation.isPending}>
                Cancel
              </Button>
              <Button type="submit" disabled={mutation.isPending}>
                {mutation.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                {mutation.isPending ? 'Saving…' : 'Save Changes'}
              </Button>
            </SheetFooter>
          </form>
        </Form>
      </SheetContent>
    </Sheet>
  )
}
