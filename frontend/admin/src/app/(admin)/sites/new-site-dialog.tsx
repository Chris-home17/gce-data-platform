'use client'

import { useMemo, useState } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Plus } from 'lucide-react'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog'
import {
  Form,
  FormControl,
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
import { api } from '@/lib/api'
import type { OrgUnitType } from '@/types/api'

const GEO_TYPES = ['Region', 'SubRegion', 'Cluster', 'Country'] as const
const LOCAL_TYPES = ['Area', 'Branch', 'Site'] as const
const ORG_UNIT_TYPES = [...GEO_TYPES, ...LOCAL_TYPES] as const

const schema = z.object({
  accountCode: z.string().min(1, 'Account is required'),
  orgUnitType: z.enum(ORG_UNIT_TYPES, { required_error: 'Type is required' }),
  sharedGeoUnitId: z.string().optional(),
  orgUnitCode: z.string().optional(),
  orgUnitName: z.string().optional(),
  parentOrgUnitId: z.string().optional(),
  countrySharedGeoUnitId: z.string().optional(),
}).superRefine((values, ctx) => {
  if (GEO_TYPES.includes(values.orgUnitType as typeof GEO_TYPES[number])) {
    if (!values.sharedGeoUnitId) {
      ctx.addIssue({ code: z.ZodIssueCode.custom, path: ['sharedGeoUnitId'], message: 'Shared geography selection is required' })
    }
    if (values.orgUnitType !== 'Region' && (!values.parentOrgUnitId || values.parentOrgUnitId === '__none__')) {
      ctx.addIssue({ code: z.ZodIssueCode.custom, path: ['parentOrgUnitId'], message: 'Parent is required' })
    }
    return
  }

  if (!values.orgUnitCode?.trim()) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, path: ['orgUnitCode'], message: 'Code is required' })
  }
  if (!values.orgUnitName?.trim()) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, path: ['orgUnitName'], message: 'Name is required' })
  }
  if (!values.parentOrgUnitId || values.parentOrgUnitId === '__none__') {
    ctx.addIssue({ code: z.ZodIssueCode.custom, path: ['parentOrgUnitId'], message: 'Parent is required' })
  }
  if (values.orgUnitType === 'Site' && !values.countrySharedGeoUnitId) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, path: ['countrySharedGeoUnitId'], message: 'Country is required' })
  }
})

type FormValues = z.infer<typeof schema>

function allowedParentTypes(type?: OrgUnitType): OrgUnitType[] {
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

export function NewSiteDialog() {
  const [open, setOpen] = useState(false)
  const queryClient = useQueryClient()

  const { data: accounts } = useQuery({
    queryKey: ['accounts'],
    queryFn: () => api.accounts.list(),
    enabled: open,
  })

  const { data: sharedGeoUnits } = useQuery({
    queryKey: ['shared-geo-units'],
    queryFn: () => api.sharedGeoUnits.list(),
    enabled: open,
  })

  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      accountCode: '',
      orgUnitType: undefined,
      sharedGeoUnitId: '',
      orgUnitCode: '',
      orgUnitName: '',
      parentOrgUnitId: '__none__',
      countrySharedGeoUnitId: '',
    },
  })

  const watchedAccountCode = form.watch('accountCode')
  const watchedType = form.watch('orgUnitType')

  const selectedAccount = accounts?.items.find((a) => a.accountCode === watchedAccountCode)
  const { data: existingUnits } = useQuery({
    queryKey: ['org-units', selectedAccount?.accountId],
    queryFn: () => api.orgUnits.list({ accountId: selectedAccount!.accountId }),
    enabled: open && !!selectedAccount,
  })

  const parentOptions = useMemo(() => {
    const allowed = new Set(allowedParentTypes(watchedType))
    return (existingUnits?.items ?? []).filter((u) => allowed.has(u.orgUnitType))
  }, [existingUnits?.items, watchedType])

  const countryOptions = useMemo(() => {
    return (existingUnits?.items ?? []).filter((u) => u.orgUnitType === 'Country' && u.sharedGeoUnitId != null)
  }, [existingUnits?.items])

  const sharedGeoOptions = useMemo(() => {
    return (sharedGeoUnits?.items ?? []).filter((u) => u.geoUnitType === watchedType)
  }, [sharedGeoUnits?.items, watchedType])

  const mutation = useMutation({
    mutationFn: (values: FormValues) => {
      const parentUnit = values.parentOrgUnitId && values.parentOrgUnitId !== '__none__'
        ? existingUnits?.items.find((u) => String(u.orgUnitId) === values.parentOrgUnitId)
        : undefined

      return api.orgUnits.create({
        accountCode: values.accountCode,
        orgUnitType: values.orgUnitType,
        orgUnitCode: values.orgUnitCode || undefined,
        orgUnitName: values.orgUnitName || undefined,
        parentOrgUnitType: parentUnit?.orgUnitType,
        parentOrgUnitCode: parentUnit?.orgUnitCode,
        sharedGeoUnitId: values.sharedGeoUnitId ? Number(values.sharedGeoUnitId) : undefined,
        countrySharedGeoUnitId: values.countrySharedGeoUnitId ? Number(values.countrySharedGeoUnitId) : undefined,
      })
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['org-units'] })
      queryClient.invalidateQueries({ queryKey: ['accounts'] })
      setOpen(false)
      form.reset()
    },
  })

  const isGeoType = GEO_TYPES.includes((watchedType ?? '') as typeof GEO_TYPES[number])
  const isLocalType = LOCAL_TYPES.includes((watchedType ?? '') as typeof LOCAL_TYPES[number])
  const requiresCountrySelection = watchedType === 'Site'

  return (
    <>
      <Button size="sm" onClick={() => setOpen(true)}>
        <Plus className="mr-1.5 h-4 w-4" />
        New Org Unit
      </Button>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>New Org Unit</DialogTitle>
          </DialogHeader>

          <Form {...form}>
            <form onSubmit={form.handleSubmit((v) => mutation.mutate(v))} className="space-y-4">
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
                        form.setValue('parentOrgUnitId', '__none__')
                        form.setValue('countrySharedGeoUnitId', '')
                      }}
                    >
                      <FormControl>
                        <SelectTrigger>
                          <SelectValue placeholder="Select account..." />
                        </SelectTrigger>
                      </FormControl>
                      <SelectContent>
                        {accounts?.items.map((a) => (
                          <SelectItem key={a.accountId} value={a.accountCode}>
                            {a.accountName} ({a.accountCode})
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
                name="orgUnitType"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Type</FormLabel>
                    <Select
                      value={field.value}
                      onValueChange={(v) => {
                        field.onChange(v as FormValues['orgUnitType'])
                        form.setValue('sharedGeoUnitId', '')
                        form.setValue('parentOrgUnitId', '__none__')
                      }}
                    >
                      <FormControl>
                        <SelectTrigger>
                          <SelectValue placeholder="Select type..." />
                        </SelectTrigger>
                      </FormControl>
                      <SelectContent>
                        {ORG_UNIT_TYPES.map((t) => (
                          <SelectItem key={t} value={t}>{t}</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    <FormMessage />
                  </FormItem>
                )}
              />

              {isGeoType && (
                <>
                  <FormField
                    control={form.control}
                    name="sharedGeoUnitId"
                    render={({ field }) => (
                      <FormItem>
                        <FormLabel>{watchedType} Repository Item</FormLabel>
                        <Select value={field.value} onValueChange={field.onChange}>
                          <FormControl>
                            <SelectTrigger>
                              <SelectValue placeholder={`Select ${watchedType?.toLowerCase()}...`} />
                            </SelectTrigger>
                          </FormControl>
                          <SelectContent>
                            {sharedGeoOptions.map((u) => (
                              <SelectItem key={u.sharedGeoUnitId} value={String(u.sharedGeoUnitId)}>
                                {u.geoUnitCode} - {u.geoUnitName}
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                        <FormMessage />
                      </FormItem>
                    )}
                  />

                  {watchedType !== 'Region' && (
                    <FormField
                      control={form.control}
                      name="parentOrgUnitId"
                      render={({ field }) => (
                        <FormItem>
                          <FormLabel>Parent</FormLabel>
                          <Select value={field.value} onValueChange={field.onChange} disabled={!watchedAccountCode}>
                            <FormControl>
                              <SelectTrigger>
                                <SelectValue placeholder="Select parent..." />
                              </SelectTrigger>
                            </FormControl>
                            <SelectContent>
                              <SelectItem value="__none__">Select parent...</SelectItem>
                              {parentOptions.map((u) => (
                                <SelectItem key={u.orgUnitId} value={String(u.orgUnitId)}>
                                  {u.orgUnitType} - {u.orgUnitCode} - {u.orgUnitName}
                                </SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                          <FormMessage />
                        </FormItem>
                      )}
                    />
                  )}
                </>
              )}

              {isLocalType && (
                <>
                  <div className="grid grid-cols-2 gap-3">
                    <FormField
                      control={form.control}
                      name="orgUnitCode"
                      render={({ field }) => (
                        <FormItem>
                          <FormLabel>Code</FormLabel>
                          <FormControl>
                            <Input placeholder="SITE-001" className="font-mono" {...field} />
                          </FormControl>
                          <FormMessage />
                        </FormItem>
                      )}
                    />
                    <FormField
                      control={form.control}
                      name="orgUnitName"
                      render={({ field }) => (
                        <FormItem>
                          <FormLabel>Name</FormLabel>
                          <FormControl>
                            <Input placeholder="London Operations Centre" {...field} />
                          </FormControl>
                          <FormMessage />
                        </FormItem>
                      )}
                    />
                  </div>

                  {requiresCountrySelection && (
                    <FormField
                      control={form.control}
                      name="countrySharedGeoUnitId"
                      render={({ field }) => (
                        <FormItem>
                          <FormLabel>Country</FormLabel>
                          <Select value={field.value} onValueChange={field.onChange} disabled={!watchedAccountCode}>
                            <FormControl>
                              <SelectTrigger>
                                <SelectValue placeholder="Select country..." />
                              </SelectTrigger>
                            </FormControl>
                            <SelectContent>
                              {countryOptions.map((u) => (
                                <SelectItem key={u.orgUnitId} value={String(u.sharedGeoUnitId)}>
                                  {u.orgUnitCode} - {u.orgUnitName}
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
                    name="parentOrgUnitId"
                    render={({ field }) => (
                      <FormItem>
                        <FormLabel>Parent</FormLabel>
                        <Select value={field.value} onValueChange={field.onChange} disabled={!watchedAccountCode}>
                          <FormControl>
                            <SelectTrigger>
                              <SelectValue placeholder="Select parent..." />
                            </SelectTrigger>
                          </FormControl>
                          <SelectContent>
                            <SelectItem value="__none__">Select parent...</SelectItem>
                            {parentOptions.map((u) => (
                              <SelectItem key={u.orgUnitId} value={String(u.orgUnitId)}>
                                {u.orgUnitType} - {u.orgUnitCode} - {u.orgUnitName}
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                        <FormMessage />
                      </FormItem>
                    )}
                  />
                </>
              )}

              {mutation.isError && (
                <p className="text-sm text-destructive">
                  {mutation.error instanceof Error
                    ? mutation.error.message
                    : 'Failed to create org unit.'}
                </p>
              )}

              <DialogFooter>
                <Button type="button" variant="outline" onClick={() => setOpen(false)} disabled={mutation.isPending}>
                  Cancel
                </Button>
                <Button type="submit" disabled={mutation.isPending}>
                  {mutation.isPending ? 'Creating...' : 'Create Org Unit'}
                </Button>
              </DialogFooter>
            </form>
          </Form>
        </DialogContent>
      </Dialog>
    </>
  )
}
