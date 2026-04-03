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

const schema = z.object({
  accountCode: z.string().min(1, 'Account is required'),
  orgUnitCode: z.string().min(1, 'Platform org unit code is required'),
  orgUnitType: z.string().min(1, 'Org unit type is required'),
  sourceSystem: z.string().min(1, 'Source system is required').max(100),
  sourceOrgUnitId: z.string().min(1, 'Source ID is required').max(200),
  sourceOrgUnitName: z.string().optional(),
})

type FormValues = z.infer<typeof schema>

export function NewSourceMappingDialog() {
  const [open, setOpen] = useState(false)
  const queryClient = useQueryClient()

  const { data: accounts } = useQuery({
    queryKey: ['accounts'],
    queryFn: () => api.accounts.list(),
    enabled: open,
  })

  const accountCode = undefined // watched below after form init

  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      accountCode: '',
      orgUnitCode: '',
      orgUnitType: 'Site',
      sourceSystem: '',
      sourceOrgUnitId: '',
      sourceOrgUnitName: '',
    },
  })

  const watchedAccountCode = form.watch('accountCode')

  const { data: orgUnits } = useQuery({
    queryKey: ['org-units', watchedAccountCode],
    queryFn: () => {
      const account = accounts?.items.find((a) => a.accountCode === watchedAccountCode)
      return account ? api.orgUnits.list({ accountId: account.accountId }) : Promise.resolve(null)
    },
    enabled: open && !!watchedAccountCode && !!accounts,
  })

  const mutation = useMutation({
    mutationFn: (values: FormValues) =>
      api.sourceMappings.create({
        accountCode: values.accountCode,
        orgUnitCode: values.orgUnitCode,
        orgUnitType: values.orgUnitType,
        sourceSystem: values.sourceSystem,
        sourceOrgUnitId: values.sourceOrgUnitId,
        sourceOrgUnitName: values.sourceOrgUnitName || undefined,
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['source-mappings'] })
      setOpen(false)
      form.reset()
    },
  })

  return (
    <>
      <Button size="sm" onClick={() => setOpen(true)}>
        <Plus className="mr-1.5 h-4 w-4" />
        New Mapping
      </Button>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>New Source Mapping</DialogTitle>
          </DialogHeader>

          <Form {...form}>
            <form onSubmit={form.handleSubmit((v) => mutation.mutate(v))} className="space-y-4">
              <FormField
                control={form.control}
                name="accountCode"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Account</FormLabel>
                    <Select value={field.value} onValueChange={(v) => { field.onChange(v); form.setValue('orgUnitCode', ''); }}>
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

              <div className="grid grid-cols-2 gap-3">
                <FormField
                  control={form.control}
                  name="orgUnitCode"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Platform Org Unit</FormLabel>
                      <Select
                        value={field.value}
                        onValueChange={(v) => {
                          field.onChange(v)
                          const unit = orgUnits?.items.find((u) => u.orgUnitCode === v)
                          if (unit) form.setValue('orgUnitType', unit.orgUnitType)
                        }}
                        disabled={!watchedAccountCode}
                      >
                        <FormControl>
                          <SelectTrigger>
                            <SelectValue placeholder="Select unit…" />
                          </SelectTrigger>
                        </FormControl>
                        <SelectContent>
                          {orgUnits?.items.map((u) => (
                            <SelectItem key={u.orgUnitId} value={u.orgUnitCode}>
                              {u.orgUnitCode} — {u.orgUnitName}
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
                      <FormControl>
                        <Input placeholder="Site" {...field} />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
              </div>

              <FormField
                control={form.control}
                name="sourceSystem"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Source System</FormLabel>
                    <FormControl>
                      <Input placeholder="SAP / Salesforce / Oracle…" {...field} />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />

              <div className="grid grid-cols-2 gap-3">
                <FormField
                  control={form.control}
                  name="sourceOrgUnitId"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Source ID</FormLabel>
                      <FormControl>
                        <Input placeholder="EXT-001" className="font-mono" {...field} />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
                <FormField
                  control={form.control}
                  name="sourceOrgUnitName"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Source Name <span className="text-muted-foreground">(optional)</span></FormLabel>
                      <FormControl>
                        <Input placeholder="London Plant" {...field} />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
              </div>

              {mutation.isError && (
                <p className="text-sm text-destructive">
                  {mutation.error instanceof Error
                    ? mutation.error.message
                    : 'Failed to create mapping.'}
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
                  {mutation.isPending ? 'Creating…' : 'Create Mapping'}
                </Button>
              </DialogFooter>
            </form>
          </Form>
        </DialogContent>
      </Dialog>
    </>
  )
}
