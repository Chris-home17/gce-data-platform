'use client'

import { useState } from 'react'
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

const ORG_UNIT_TYPES = ['Division', 'Region', 'Country', 'Area', 'Territory', 'Branch', 'Site'] as const

const schema = z.object({
  accountCode: z.string().min(1, 'Account is required'),
  orgUnitType: z.enum(ORG_UNIT_TYPES, { required_error: 'Type is required' }),
  orgUnitCode: z.string().min(1, 'Code is required').max(50),
  orgUnitName: z.string().min(1, 'Name is required').max(200),
  parentOrgUnitId: z.string().optional(), // orgUnitId as string from select; '__none__' = no parent
  countryCode: z.string().max(3).optional(),
})

type FormValues = z.infer<typeof schema>

export function NewSiteDialog() {
  const [open, setOpen] = useState(false)
  const queryClient = useQueryClient()

  const { data: accounts } = useQuery({
    queryKey: ['accounts'],
    queryFn: () => api.accounts.list(),
    enabled: open,
  })

  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      accountCode: '',
      orgUnitType: undefined,
      orgUnitCode: '',
      orgUnitName: '',
      parentOrgUnitId: '__none__',
      countryCode: '',
    },
  })

  const watchedAccountCode = form.watch('accountCode')
  const watchedType = form.watch('orgUnitType')

  // Load org units for the selected account to populate the parent dropdown
  const selectedAccount = accounts?.items.find((a) => a.accountCode === watchedAccountCode)
  const { data: existingUnits } = useQuery({
    queryKey: ['org-units', selectedAccount?.accountId],
    queryFn: () => api.orgUnits.list({ accountId: selectedAccount!.accountId }),
    enabled: open && !!selectedAccount,
  })

  const mutation = useMutation({
    mutationFn: (values: FormValues) => {
      const parentUnit = values.parentOrgUnitId && values.parentOrgUnitId !== '__none__'
        ? existingUnits?.items.find((u) => String(u.orgUnitId) === values.parentOrgUnitId)
        : undefined
      return api.orgUnits.create({
        accountCode: values.accountCode,
        orgUnitType: values.orgUnitType,
        orgUnitCode: values.orgUnitCode,
        orgUnitName: values.orgUnitName,
        parentOrgUnitType: parentUnit?.orgUnitType,
        parentOrgUnitCode: parentUnit?.orgUnitCode,
        countryCode: values.countryCode || undefined,
      })
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['org-units'] })
      queryClient.invalidateQueries({ queryKey: ['users'] })
      setOpen(false)
      form.reset()
    },
  })

  const showCountry = watchedType === 'Site' || watchedType === 'Country'

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
              {/* Account */}
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
                      }}
                    >
                      <FormControl>
                        <SelectTrigger>
                          <SelectValue placeholder="Select account…" />
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

              {/* Type */}
              <FormField
                control={form.control}
                name="orgUnitType"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Type</FormLabel>
                    <Select value={field.value} onValueChange={field.onChange}>
                      <FormControl>
                        <SelectTrigger>
                          <SelectValue placeholder="Select type…" />
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

              {/* Code + Name */}
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

              {/* Parent — only shown once an account is selected */}
              {watchedAccountCode && (
                <FormField
                  control={form.control}
                  name="parentOrgUnitId"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Parent <span className="text-muted-foreground">(optional)</span></FormLabel>
                      <Select value={field.value} onValueChange={field.onChange}>
                        <FormControl>
                          <SelectTrigger>
                            <SelectValue placeholder="None (root level)" />
                          </SelectTrigger>
                        </FormControl>
                        <SelectContent>
                          <SelectItem value="__none__">None (root level)</SelectItem>
                          {existingUnits?.items.map((u) => {
                            const depth = u.path.split('|').filter(Boolean).length - 1
                            const prefix = '\u00a0\u00a0'.repeat(depth)
                            return (
                              <SelectItem key={u.orgUnitId} value={String(u.orgUnitId)}>
                                {prefix}{u.orgUnitCode} — {u.orgUnitName}
                              </SelectItem>
                            )
                          })}
                        </SelectContent>
                      </Select>
                      <FormMessage />
                    </FormItem>
                  )}
                />
              )}

              {/* Country Code — only for Site or Country types */}
              {showCountry && (
                <FormField
                  control={form.control}
                  name="countryCode"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Country Code <span className="text-muted-foreground">(e.g. GB, AU)</span></FormLabel>
                      <FormControl>
                        <Input placeholder="GB" maxLength={3} className="font-mono w-24" {...field} />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
              )}

              {mutation.isError && (
                <p className="text-sm text-destructive">
                  {mutation.error instanceof Error
                    ? mutation.error.message
                    : 'Failed to create org unit.'}
                </p>
              )}

              <DialogFooter>
                <Button
                  type="button"
                  variant="outline"
                  onClick={() => setOpen(false)}
                  disabled={mutation.isPending}
                >
                  Cancel
                </Button>
                <Button type="submit" disabled={mutation.isPending}>
                  {mutation.isPending ? 'Creating…' : 'Create'}
                </Button>
              </DialogFooter>
            </form>
          </Form>
        </DialogContent>
      </Dialog>
    </>
  )
}
