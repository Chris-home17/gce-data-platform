'use client'

import { useState, useMemo } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { Loader2, Package } from 'lucide-react'
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
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from '@/components/ui/form'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Switch } from '@/components/ui/switch'
import { Badge } from '@/components/ui/badge'
import { api } from '@/lib/api'
import { parsePackageTags } from '@/types/api'

const schema = z.object({
  packageId: z.string().min(1, 'Select a package'),
  periodScheduleId: z.string().min(1, 'Select a schedule'),
  accountCode: z.string().min(1, 'Select an account'),
  isAccountWide: z.boolean(),
  orgUnitCode: z.string().optional(),
  materializeNow: z.boolean(),
}).superRefine((d, ctx) => {
  if (!d.isAccountWide && !d.orgUnitCode) {
    ctx.addIssue({ code: 'custom', path: ['orgUnitCode'], message: 'Select a site or enable account-wide' })
  }
})

type FormValues = z.infer<typeof schema>

export function AssignPackageSheet() {
  const [open, setOpen] = useState(false)
  const queryClient = useQueryClient()

  const packagesQuery = useQuery({
    queryKey: ['kpi', 'packages'],
    queryFn: () => api.kpi.packages.list(),
    enabled: open,
  })
  const schedulesQuery = useQuery({
    queryKey: ['kpi', 'period-schedules'],
    queryFn: () => api.kpi.periods.schedules.list(),
    enabled: open,
  })
  const accountsQuery = useQuery({
    queryKey: ['accounts'],
    queryFn: () => api.accounts.list(),
    enabled: open,
  })
  const orgUnitsQuery = useQuery({
    queryKey: ['org-units'],
    queryFn: () => api.orgUnits.list(),
    enabled: open,
  })

  const activePackages = useMemo(
    () => (packagesQuery.data?.items ?? []).filter((p) => p.isActive),
    [packagesQuery.data]
  )
  const activeSchedules = useMemo(
    () => (schedulesQuery.data?.items ?? []).filter((s) => s.isActive),
    [schedulesQuery.data]
  )
  const activeAccounts = useMemo(
    () => (accountsQuery.data?.items ?? []).filter((a) => a.isActive),
    [accountsQuery.data]
  )

  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      packageId: '',
      periodScheduleId: '',
      accountCode: '',
      isAccountWide: true,
      orgUnitCode: '',
      materializeNow: true,
    },
  })

  const watchedAccountCode = form.watch('accountCode')
  const watchedIsAccountWide = form.watch('isAccountWide')
  const watchedPackageId = form.watch('packageId')

  const sites = useMemo(() => {
    if (!watchedAccountCode) return []
    return (orgUnitsQuery.data?.items ?? []).filter(
      (u) => u.accountCode === watchedAccountCode && u.orgUnitType === 'Site' && u.isActive
    )
  }, [orgUnitsQuery.data, watchedAccountCode])

  const selectedPackage = useMemo(
    () => activePackages.find((p) => String(p.kpiPackageId) === watchedPackageId),
    [activePackages, watchedPackageId]
  )

  const mutation = useMutation({
    mutationFn: (values: FormValues) =>
      api.kpi.packages.assignTemplates(parseInt(values.packageId), {
        kpiPackageId: parseInt(values.packageId),
        periodScheduleId: parseInt(values.periodScheduleId),
        accountCode: values.accountCode,
        orgUnitCode: values.isAccountWide ? null : values.orgUnitCode,
        orgUnitType: values.isAccountWide ? 'Account' : 'Site',
        isRequired: false,
        materializeNow: values.materializeNow,
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['kpi', 'assignment-templates'] })
      queryClient.invalidateQueries({ queryKey: ['kpi', 'assignments'] })
      toast.success('Package assigned successfully.')
      setOpen(false)
      form.reset()
    },
    onError: (err: Error) => toast.error(err.message ?? 'Failed to assign package.'),
  })

  function handleOpenChange(value: boolean) {
    if (!value) { form.reset(); mutation.reset() }
    setOpen(value)
  }

  return (
    <Sheet open={open} onOpenChange={handleOpenChange}>
      <SheetTrigger asChild>
        <Button variant="outline">
          <Package className="mr-2 h-4 w-4" />
          Assign Package
        </Button>
      </SheetTrigger>

      <SheetContent className="w-full sm:max-w-lg overflow-y-auto">
        <SheetHeader>
          <SheetTitle>Assign KPI Package</SheetTitle>
          <SheetDescription>
            Assign all KPIs in a package to a site or account in one action.
          </SheetDescription>
        </SheetHeader>

        <Form {...form}>
          <form onSubmit={form.handleSubmit((v) => mutation.mutate(v))} className="mt-6 space-y-4">

            <FormField
              control={form.control}
              name="packageId"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Package</FormLabel>
                  <Select value={field.value} onValueChange={field.onChange}>
                    <FormControl>
                      <SelectTrigger>
                        <SelectValue placeholder="Select a package…" />
                      </SelectTrigger>
                    </FormControl>
                    <SelectContent>
                      {activePackages.map((p) => (
                        <SelectItem key={p.kpiPackageId} value={String(p.kpiPackageId)}>
                          {p.packageName}
                          <span className="ml-1.5 text-muted-foreground text-xs">({p.kpiCount} KPIs)</span>
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <FormMessage />
                  {selectedPackage && (
                    <div className="flex flex-wrap gap-1 pt-1">
                      {parsePackageTags(selectedPackage.tagsRaw).map((t) => (
                        <Badge key={t.tagId} variant="secondary" className="text-xs">{t.tagName}</Badge>
                      ))}
                      <span className="text-xs text-muted-foreground">
                        {selectedPackage.kpiCount} KPI{selectedPackage.kpiCount !== 1 ? 's' : ''} will be assigned
                      </span>
                    </div>
                  )}
                </FormItem>
              )}
            />

            <FormField
              control={form.control}
              name="periodScheduleId"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Period Schedule</FormLabel>
                  <Select value={field.value} onValueChange={field.onChange}>
                    <FormControl>
                      <SelectTrigger>
                        <SelectValue placeholder="Select a schedule…" />
                      </SelectTrigger>
                    </FormControl>
                    <SelectContent>
                      {activeSchedules.map((s) => (
                        <SelectItem key={s.periodScheduleId} value={String(s.periodScheduleId)}>
                          {s.scheduleName}
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
              name="accountCode"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Account</FormLabel>
                  <Select
                    value={field.value}
                    onValueChange={(v) => {
                      field.onChange(v)
                      form.setValue('orgUnitCode', '')
                    }}
                  >
                    <FormControl>
                      <SelectTrigger>
                        <SelectValue placeholder="Select an account…" />
                      </SelectTrigger>
                    </FormControl>
                    <SelectContent>
                      {activeAccounts.map((a) => (
                        <SelectItem key={a.accountCode} value={a.accountCode}>
                          {a.accountName}
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
                <FormItem className="flex items-center justify-between rounded-md border px-3 py-2.5 space-y-0">
                  <FormLabel className="font-medium">Account-wide</FormLabel>
                  <FormControl>
                    <Switch checked={field.value} onCheckedChange={(v) => {
                      field.onChange(v)
                      if (v) form.setValue('orgUnitCode', '')
                    }} />
                  </FormControl>
                </FormItem>
              )}
            />

            {!watchedIsAccountWide && (
              <FormField
                control={form.control}
                name="orgUnitCode"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Site</FormLabel>
                    <Select value={field.value} onValueChange={field.onChange} disabled={!watchedAccountCode}>
                      <FormControl>
                        <SelectTrigger>
                          <SelectValue placeholder={watchedAccountCode ? 'Select a site…' : 'Select an account first'} />
                        </SelectTrigger>
                      </FormControl>
                      <SelectContent>
                        {sites.map((s) => (
                          <SelectItem key={s.orgUnitCode} value={s.orgUnitCode}>
                            {s.orgUnitCode} — {s.orgUnitName}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    <FormMessage />
                  </FormItem>
                )}
              />
            )}

            <FormField
              control={form.control}
              name="materializeNow"
              render={({ field }) => (
                <FormItem className="flex items-center justify-between rounded-md border px-3 py-2.5 space-y-0">
                  <div>
                    <FormLabel className="font-medium">Materialize immediately</FormLabel>
                    <p className="text-xs text-muted-foreground mt-0.5">Generate assignment instances for open periods now.</p>
                  </div>
                  <FormControl>
                    <Switch checked={field.value} onCheckedChange={field.onChange} />
                  </FormControl>
                </FormItem>
              )}
            />

            <SheetFooter className="pt-2">
              <Button type="button" variant="outline" onClick={() => handleOpenChange(false)} disabled={mutation.isPending}>
                Cancel
              </Button>
              <Button type="submit" disabled={mutation.isPending}>
                {mutation.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                {mutation.isPending ? 'Assigning…' : 'Assign Package'}
              </Button>
            </SheetFooter>
          </form>
        </Form>
      </SheetContent>
    </Sheet>
  )
}
