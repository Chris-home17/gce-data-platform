'use client'

import { useState } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { Loader2, Plus } from 'lucide-react'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog'
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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Switch } from '@/components/ui/switch'
import { api } from '@/lib/api'

const FREQUENCY_OPTIONS = [
  { value: 'Monthly', label: 'Monthly' },
  { value: 'EveryNMonths', label: 'Every N months' },
  { value: 'Quarterly', label: 'Quarterly' },
  { value: 'SemiAnnual', label: 'Semi-annual' },
  { value: 'Annual', label: 'Annual' },
] as const

const scheduleSchema = z.object({
  scheduleName: z.string().min(3, 'Enter a schedule name'),
  frequencyType: z.enum(['Monthly', 'EveryNMonths', 'Quarterly', 'SemiAnnual', 'Annual']),
  frequencyInterval: z.number().int().min(2).max(12).nullable().optional(),
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Use YYYY-MM-DD format'),
  endDate: z.string().optional(),
  submissionOpenDay: z.number().int().min(1).max(28),
  submissionCloseDay: z.number().int().min(1).max(31),
  generateMonthsAhead: z.number().int().min(1).max(24),
  notes: z.string().max(500).optional(),
  generateNow: z.boolean(),
}).superRefine((value, ctx) => {
  if (value.endDate && value.endDate < value.startDate) {
    ctx.addIssue({ code: 'custom', path: ['endDate'], message: 'End date must be on or after the start date.' })
  }

  if (value.submissionCloseDay < value.submissionOpenDay) {
    ctx.addIssue({ code: 'custom', path: ['submissionCloseDay'], message: 'Close day must be on or after open day.' })
  }

  if (value.frequencyType === 'EveryNMonths' && !value.frequencyInterval) {
    ctx.addIssue({ code: 'custom', path: ['frequencyInterval'], message: 'Provide the number of months for this cadence.' })
  }

  if (value.frequencyType !== 'EveryNMonths' && value.frequencyInterval) {
    ctx.addIssue({ code: 'custom', path: ['frequencyInterval'], message: 'Only Every N months schedules use an interval.' })
  }
})

type ScheduleValues = z.infer<typeof scheduleSchema>

export function NewPeriodDialog() {
  const [open, setOpen] = useState(false)
  const queryClient = useQueryClient()

  const form = useForm<ScheduleValues>({
    resolver: zodResolver(scheduleSchema),
    defaultValues: {
      scheduleName: 'Monthly KPI Submission Calendar',
      frequencyType: 'Monthly',
      frequencyInterval: null,
      startDate: '',
      endDate: '',
      submissionOpenDay: 1,
      submissionCloseDay: 28,
      generateMonthsAhead: 6,
      notes: '',
      generateNow: true,
    },
  })

  const mutation = useMutation({
    mutationFn: (values: ScheduleValues) =>
      api.kpi.periods.schedules.create({
        scheduleName: values.scheduleName,
        frequencyType: values.frequencyType,
        frequencyInterval: values.frequencyType === 'EveryNMonths' ? (values.frequencyInterval ?? null) : null,
        startDate: values.startDate,
        endDate: values.endDate || null,
        submissionOpenDay: values.submissionOpenDay,
        submissionCloseDay: values.submissionCloseDay,
        generateMonthsAhead: values.generateMonthsAhead,
        notes: values.notes || undefined,
        generateNow: values.generateNow,
      }),
    onSuccess: (schedule) => {
      queryClient.invalidateQueries({ queryKey: ['kpi', 'period-schedules'] })
      queryClient.invalidateQueries({ queryKey: ['kpi', 'periods'] })
      queryClient.invalidateQueries({ queryKey: ['kpi', 'assignments'] })
      queryClient.invalidateQueries({ queryKey: ['kpi', 'assignment-templates'] })
      toast.success(`Schedule ${schedule.scheduleName} created.`)
      setOpen(false)
      form.reset()
    },
    onError: (err: Error) => {
      toast.error(err.message ?? 'Failed to save schedule.')
    },
  })

  function handleOpenChange(value: boolean) {
    if (!value) {
      form.reset()
      mutation.reset()
    }
    setOpen(value)
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogTrigger asChild>
        <Button>
          <Plus className="mr-2 h-4 w-4" />
          New Schedule
        </Button>
      </DialogTrigger>

      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>New KPI Period Schedule</DialogTitle>
          <DialogDescription>
            Create a new cadence, then let the platform generate the reporting periods and downstream KPI instances automatically. Schedule names are labels, not unique keys.
          </DialogDescription>
        </DialogHeader>

        <Form {...form}>
          <form onSubmit={form.handleSubmit((v) => mutation.mutate(v))} className="space-y-4">
            <FormField
              control={form.control}
              name="scheduleName"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Schedule name</FormLabel>
                  <FormControl>
                    <Input placeholder="Monthly KPI Submission Calendar" {...field} />
                  </FormControl>
                  <FormDescription>
                    You can reuse the same label on multiple schedules when needed.
                  </FormDescription>
                  <FormMessage />
                </FormItem>
              )}
            />

            <div className="grid grid-cols-2 gap-3">
              <FormField
                control={form.control}
                name="frequencyType"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Cadence</FormLabel>
                    <Select value={field.value} onValueChange={field.onChange}>
                      <FormControl>
                        <SelectTrigger>
                          <SelectValue placeholder="Select cadence" />
                        </SelectTrigger>
                      </FormControl>
                      <SelectContent>
                        {FREQUENCY_OPTIONS.map((option) => (
                          <SelectItem key={option.value} value={option.value}>
                            {option.label}
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
                name="frequencyInterval"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Interval</FormLabel>
                    <FormControl>
                      <Input
                        type="number"
                        min={2}
                        max={12}
                        value={field.value ?? ''}
                        disabled={form.watch('frequencyType') !== 'EveryNMonths'}
                        placeholder={form.watch('frequencyType') === 'EveryNMonths' ? '2-12' : 'Not used'}
                        onChange={(e) => field.onChange(e.target.value ? parseInt(e.target.value, 10) : null)}
                      />
                    </FormControl>
                    <FormDescription>
                      {form.watch('frequencyType') === 'EveryNMonths'
                        ? 'Example: 2 means every 2 months.'
                        : 'Only used for Every N months schedules.'}
                    </FormDescription>
                    <FormMessage />
                  </FormItem>
                )}
              />
            </div>

            <div className="grid grid-cols-2 gap-3">
              <FormField
                control={form.control}
                name="startDate"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Start date</FormLabel>
                    <FormControl>
                      <Input type="date" {...field} />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />

              <FormField
                control={form.control}
                name="endDate"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>End date</FormLabel>
                    <FormControl>
                      <Input type="date" {...field} value={field.value ?? ''} />
                    </FormControl>
                  <FormDescription>Leave empty for an open-ended contract.</FormDescription>
                    <FormMessage />
                  </FormItem>
                )}
              />
            </div>

            <div className="grid grid-cols-3 gap-3">
              <FormField
                control={form.control}
                name="submissionOpenDay"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Open day</FormLabel>
                    <FormControl>
                      <Input
                        type="number"
                        min={1}
                        max={28}
                        {...field}
                        onChange={(e) => field.onChange(parseInt(e.target.value, 10))}
                      />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />

              <FormField
                control={form.control}
                name="submissionCloseDay"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Close day</FormLabel>
                    <FormControl>
                      <Input
                        type="number"
                        min={1}
                        max={31}
                        {...field}
                        onChange={(e) => field.onChange(parseInt(e.target.value, 10))}
                      />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />

              <FormField
                control={form.control}
                name="generateMonthsAhead"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Months ahead</FormLabel>
                    <FormControl>
                      <Input
                        type="number"
                        min={1}
                        max={24}
                        {...field}
                        onChange={(e) => field.onChange(parseInt(e.target.value, 10))}
                      />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />
            </div>

            <FormField
              control={form.control}
              name="notes"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Notes <span className="text-muted-foreground">(optional)</span></FormLabel>
                  <FormControl>
                    <Input placeholder="Internal notes about this schedule" {...field} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />

            <FormField
              control={form.control}
              name="generateNow"
              render={({ field }) => (
                <FormItem className="flex items-center justify-between rounded-md border px-3 py-2">
                  <div>
                    <FormLabel className="text-sm">Generate periods now</FormLabel>
                    <FormDescription className="text-xs">
                      Immediately create missing periods and materialize active recurring assignment templates.
                    </FormDescription>
                  </div>
                  <FormControl>
                    <Switch checked={field.value} onCheckedChange={field.onChange} />
                  </FormControl>
                </FormItem>
              )}
            />

            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => handleOpenChange(false)} disabled={mutation.isPending}>
                Cancel
              </Button>
              <Button type="submit" disabled={mutation.isPending}>
                {mutation.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                {mutation.isPending ? 'Saving…' : 'Save Schedule'}
              </Button>
            </DialogFooter>
          </form>
        </Form>
      </DialogContent>
    </Dialog>
  )
}
