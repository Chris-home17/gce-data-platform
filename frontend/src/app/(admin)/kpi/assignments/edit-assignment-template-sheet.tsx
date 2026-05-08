'use client'

import { useEffect } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { useMutation, useQueryClient } from '@tanstack/react-query'
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
      })
    }
  }, [open, template?.assignmentTemplateId]) // eslint-disable-line react-hooks/exhaustive-deps

  const watchDirection = form.watch('thresholdDirection')
  const overrideKpiName = form.watch('overrideKpiName')

  const mutation = useMutation({
    mutationFn: (values: FormValues) => {
      if (!template) throw new Error('No template selected')
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
