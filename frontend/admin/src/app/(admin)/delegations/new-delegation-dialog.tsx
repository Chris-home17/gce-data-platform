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
import { PrincipalIdentifierTypeahead } from '@/components/shared/principal-identifier-typeahead'
import { api } from '@/lib/api'

const schema = z
  .object({
    delegatorType:       z.enum(['USER', 'ROLE']),
    delegatorIdentifier: z.string().min(1, 'Required'),
    delegateType:        z.enum(['USER', 'ROLE']),
    delegateIdentifier:  z.string().min(1, 'Required'),
    accessType:          z.enum(['ALL', 'ACCOUNT']),
    accountCode:         z.string().optional(),
    scopeType:           z.enum(['NONE', 'ORGUNIT']),
    orgUnitType:         z.string().optional(),
    orgUnitCode:         z.string().optional(),
    validFromDate:       z.string().optional(),
    validToDate:         z.string().optional(),
  })
  .superRefine((d, ctx) => {
    if (d.accessType === 'ACCOUNT' && !d.accountCode) {
      ctx.addIssue({ code: 'custom', path: ['accountCode'], message: 'Account is required' })
    }
    if (d.scopeType === 'ORGUNIT') {
      if (!d.orgUnitType)
        ctx.addIssue({ code: 'custom', path: ['orgUnitType'], message: 'Org unit type is required' })
      if (!d.orgUnitCode)
        ctx.addIssue({ code: 'custom', path: ['orgUnitCode'], message: 'Org unit code is required' })
    }
    if (d.validFromDate && d.validToDate && d.validToDate < d.validFromDate) {
      ctx.addIssue({ code: 'custom', path: ['validToDate'], message: 'End date must be on or after start date' })
    }
  })

type FormValues = z.infer<typeof schema>

export function NewDelegationDialog() {
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
      delegatorType:       'USER',
      delegatorIdentifier: '',
      delegateType:        'USER',
      delegateIdentifier:  '',
      accessType:          'ALL',
      accountCode:         '',
      scopeType:           'NONE',
      orgUnitType:         '',
      orgUnitCode:         '',
      validFromDate:       '',
      validToDate:         '',
    },
  })

  const accessType = form.watch('accessType')
  const scopeType  = form.watch('scopeType')
  const delegatorType = form.watch('delegatorType')
  const delegateType = form.watch('delegateType')

  const mutation = useMutation({
    mutationFn: (values: FormValues) =>
      api.delegations.create({
        delegatorType:       values.delegatorType,
        delegatorIdentifier: values.delegatorIdentifier.trim(),
        delegateType:        values.delegateType,
        delegateIdentifier:  values.delegateIdentifier.trim(),
        accessType:          values.accessType,
        accountCode:         values.accessType === 'ACCOUNT' ? values.accountCode : undefined,
        scopeType:           values.scopeType,
        orgUnitType:         values.scopeType === 'ORGUNIT' ? values.orgUnitType : undefined,
        orgUnitCode:         values.scopeType === 'ORGUNIT' ? values.orgUnitCode : undefined,
        validFromDate:       values.validFromDate || undefined,
        validToDate:         values.validToDate || undefined,
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['delegations'] })
      queryClient.invalidateQueries({ queryKey: ['coverage'] })
      setOpen(false)
      form.reset()
    },
  })

  return (
    <>
      <Button size="sm" onClick={() => setOpen(true)}>
        <Plus className="mr-1.5 h-4 w-4" />
        New Delegation
      </Button>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>New Delegation</DialogTitle>
          </DialogHeader>

          <Form {...form}>
            <form onSubmit={form.handleSubmit((v) => mutation.mutate(v))} className="space-y-4">

              {/* Delegator */}
              <div className="grid grid-cols-3 gap-3">
                <FormField
                  control={form.control}
                  name="delegatorType"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Delegator Type</FormLabel>
                      <Select value={field.value} onValueChange={(value) => {
                        field.onChange(value)
                        form.resetField('delegatorIdentifier')
                      }}>
                        <FormControl>
                          <SelectTrigger><SelectValue /></SelectTrigger>
                        </FormControl>
                        <SelectContent>
                          <SelectItem value="USER">User</SelectItem>
                          <SelectItem value="ROLE">Role</SelectItem>
                        </SelectContent>
                      </Select>
                      <FormMessage />
                    </FormItem>
                  )}
                />
                <FormField
                  control={form.control}
                  name="delegatorIdentifier"
                  render={({ field }) => (
                    <FormItem className="col-span-2">
                      <FormLabel>Delegator (UPN or Role Code)</FormLabel>
                      <FormControl>
                        <PrincipalIdentifierTypeahead
                          principalType={delegatorType}
                          value={field.value}
                          onChange={field.onChange}
                          open={open}
                          disabled={mutation.isPending}
                        />
                      </FormControl>
                      <p className="text-xs text-muted-foreground">
                        Search by user name/email or role name/code.
                      </p>
                      <FormMessage />
                    </FormItem>
                  )}
                />
              </div>

              {/* Delegate */}
              <div className="grid grid-cols-3 gap-3">
                <FormField
                  control={form.control}
                  name="delegateType"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Delegate Type</FormLabel>
                      <Select value={field.value} onValueChange={(value) => {
                        field.onChange(value)
                        form.resetField('delegateIdentifier')
                      }}>
                        <FormControl>
                          <SelectTrigger><SelectValue /></SelectTrigger>
                        </FormControl>
                        <SelectContent>
                          <SelectItem value="USER">User</SelectItem>
                          <SelectItem value="ROLE">Role</SelectItem>
                        </SelectContent>
                      </Select>
                      <FormMessage />
                    </FormItem>
                  )}
                />
                <FormField
                  control={form.control}
                  name="delegateIdentifier"
                  render={({ field }) => (
                    <FormItem className="col-span-2">
                      <FormLabel>Delegate (UPN or Role Code)</FormLabel>
                      <FormControl>
                        <PrincipalIdentifierTypeahead
                          principalType={delegateType}
                          value={field.value}
                          onChange={field.onChange}
                          open={open}
                          disabled={mutation.isPending}
                        />
                      </FormControl>
                      <p className="text-xs text-muted-foreground">
                        Search by user name/email or role name/code.
                      </p>
                      <FormMessage />
                    </FormItem>
                  )}
                />
              </div>

              {/* Access type */}
              <FormField
                control={form.control}
                name="accessType"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Access Type</FormLabel>
                    <Select
                      value={field.value}
                      onValueChange={(v) => {
                        field.onChange(v)
                        form.resetField('accountCode')
                        form.resetField('scopeType')
                        form.resetField('orgUnitType')
                        form.resetField('orgUnitCode')
                      }}
                    >
                      <FormControl>
                        <SelectTrigger><SelectValue /></SelectTrigger>
                      </FormControl>
                      <SelectContent>
                        <SelectItem value="ALL">All Accounts</SelectItem>
                        <SelectItem value="ACCOUNT">Specific Account</SelectItem>
                      </SelectContent>
                    </Select>
                    <FormMessage />
                  </FormItem>
                )}
              />

              {/* Account picker (ACCOUNT only) */}
              {accessType === 'ACCOUNT' && (
                <FormField
                  control={form.control}
                  name="accountCode"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Account</FormLabel>
                      <Select value={field.value} onValueChange={field.onChange}>
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
              )}

              {/* Scope type */}
              <FormField
                control={form.control}
                name="scopeType"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Scope</FormLabel>
                    <Select
                      value={field.value}
                      onValueChange={(v) => {
                        field.onChange(v)
                        form.resetField('orgUnitType')
                        form.resetField('orgUnitCode')
                      }}
                    >
                      <FormControl>
                        <SelectTrigger><SelectValue /></SelectTrigger>
                      </FormControl>
                      <SelectContent>
                        <SelectItem value="NONE">None</SelectItem>
                        <SelectItem value="ORGUNIT">Org Unit</SelectItem>
                      </SelectContent>
                    </Select>
                    <FormMessage />
                  </FormItem>
                )}
              />

              {/* Org unit fields (ORGUNIT only) */}
              {scopeType === 'ORGUNIT' && (
                <div className="grid grid-cols-2 gap-3">
                  <FormField
                    control={form.control}
                    name="orgUnitType"
                    render={({ field }) => (
                      <FormItem>
                        <FormLabel>Org Unit Type</FormLabel>
                        <FormControl>
                          <Input placeholder="Site" className="font-mono" {...field} />
                        </FormControl>
                        <FormMessage />
                      </FormItem>
                    )}
                  />
                  <FormField
                    control={form.control}
                    name="orgUnitCode"
                    render={({ field }) => (
                      <FormItem>
                        <FormLabel>Org Unit Code</FormLabel>
                        <FormControl>
                          <Input placeholder="AU-SYD-01" className="font-mono" {...field} />
                        </FormControl>
                        <FormMessage />
                      </FormItem>
                    )}
                  />
                </div>
              )}

              <div className="grid grid-cols-2 gap-3">
                <FormField
                  control={form.control}
                  name="validFromDate"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Valid From</FormLabel>
                      <FormControl>
                        <Input type="date" {...field} />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
                <FormField
                  control={form.control}
                  name="validToDate"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Valid To</FormLabel>
                      <FormControl>
                        <Input type="date" {...field} />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
              </div>

              {mutation.isError && (
                <p className="text-sm text-destructive">
                  {mutation.error instanceof Error ? mutation.error.message : 'Failed to create delegation.'}
                </p>
              )}

              <DialogFooter>
                <Button type="button" variant="outline" onClick={() => setOpen(false)} disabled={mutation.isPending}>
                  Cancel
                </Button>
                <Button type="submit" disabled={mutation.isPending}>
                  {mutation.isPending ? 'Saving…' : 'Create Delegation'}
                </Button>
              </DialogFooter>
            </form>
          </Form>
        </DialogContent>
      </Dialog>
    </>
  )
}
