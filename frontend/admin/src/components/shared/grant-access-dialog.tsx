'use client'

import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { ShieldPlus } from 'lucide-react'
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
import type { GrantType } from '@/types/api'

const GRANT_TYPE_LABELS: Record<GrantType, string> = {
  GLOBAL_ALL:     'Global All — all accounts + all packages',
  GLOBAL_PACKAGE: 'Global Package — one package, all accounts',
  FULL_ACCOUNT:   'Full Account — all sites within one account',
  PATH_PREFIX:    'Path Prefix — org unit and its children',
  COUNTRY_ALL:    'Country — all sites in a country',
}

const schema = z
  .object({
    grantType:   z.enum(['GLOBAL_ALL', 'GLOBAL_PACKAGE', 'FULL_ACCOUNT', 'PATH_PREFIX', 'COUNTRY_ALL']),
    packageCode: z.string().optional(),
    accountCode: z.string().optional(),
    orgUnitCode: z.string().optional(),
    orgUnitType: z.string().optional(),
    countryCode: z.string().optional(),
  })
  .superRefine((d, ctx) => {
    if (d.grantType === 'GLOBAL_PACKAGE' && !d.packageCode)
      ctx.addIssue({ code: 'custom', path: ['packageCode'], message: 'Package is required' })
    if (d.grantType === 'FULL_ACCOUNT' && !d.accountCode)
      ctx.addIssue({ code: 'custom', path: ['accountCode'], message: 'Account is required' })
    if (d.grantType === 'PATH_PREFIX') {
      if (!d.accountCode)
        ctx.addIssue({ code: 'custom', path: ['accountCode'], message: 'Account is required' })
      if (!d.orgUnitCode)
        ctx.addIssue({ code: 'custom', path: ['orgUnitCode'], message: 'Org unit code is required' })
      if (!d.orgUnitType)
        ctx.addIssue({ code: 'custom', path: ['orgUnitType'], message: 'Org unit type is required' })
    }
    if (d.grantType === 'COUNTRY_ALL' && !d.countryCode)
      ctx.addIssue({ code: 'custom', path: ['countryCode'], message: 'Country code is required' })
  })

type FormValues = z.infer<typeof schema>

interface GrantAccessDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  principalType: 'USER' | 'ROLE'
  principalIdentifier: string  // UPN for users, RoleCode for roles
  invalidateKeys: string[][]   // query keys to invalidate on success
}

export function GrantAccessDialog({
  open,
  onOpenChange,
  principalType,
  principalIdentifier,
  invalidateKeys,
}: GrantAccessDialogProps) {
  const queryClient = useQueryClient()

  const { data: accounts } = useQuery({
    queryKey: ['accounts'],
    queryFn: () => api.accounts.list(),
    enabled: open,
  })

  const { data: packages } = useQuery({
    queryKey: ['packages'],
    queryFn: () => api.packages.list(),
    enabled: open,
  })

  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      grantType: 'FULL_ACCOUNT',
      packageCode: '',
      accountCode: '',
      orgUnitCode: '',
      orgUnitType: '',
      countryCode: '',
    },
  })

  const grantType = form.watch('grantType')
  const watchedAccountCode = form.watch('accountCode')

  const { data: orgUnits } = useQuery({
    queryKey: ['org-units-for-grant', watchedAccountCode],
    queryFn: () => {
      const acct = accounts?.items.find((a) => a.accountCode === watchedAccountCode)
      return acct ? api.orgUnits.list({ accountId: acct.accountId }) : Promise.resolve(null)
    },
    enabled: open && grantType === 'PATH_PREFIX' && !!watchedAccountCode && !!accounts,
  })

  const mutation = useMutation({
    mutationFn: (values: FormValues) =>
      api.grants.grant({
        principalType,
        principalIdentifier,
        grantType: values.grantType,
        packageCode: values.packageCode || undefined,
        accountCode: values.accountCode || undefined,
        orgUnitType: values.orgUnitType || undefined,
        orgUnitCode: values.orgUnitCode || undefined,
        countryCode: values.countryCode || undefined,
      }),
    onSuccess: () => {
      invalidateKeys.forEach((key) => queryClient.invalidateQueries({ queryKey: key }))
      onOpenChange(false)
      form.reset()
    },
  })

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Grant Access</DialogTitle>
        </DialogHeader>

        <Form {...form}>
          <form onSubmit={form.handleSubmit((v) => mutation.mutate(v))} className="space-y-4">
            {/* Grant type */}
            <FormField
              control={form.control}
              name="grantType"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Grant Type</FormLabel>
                  <Select value={field.value} onValueChange={(v) => { field.onChange(v); form.resetField('packageCode'); form.resetField('accountCode'); form.resetField('orgUnitCode'); form.resetField('orgUnitType'); form.resetField('countryCode') }}>
                    <FormControl>
                      <SelectTrigger>
                        <SelectValue />
                      </SelectTrigger>
                    </FormControl>
                    <SelectContent>
                      {(Object.entries(GRANT_TYPE_LABELS) as [GrantType, string][]).map(([v, label]) => (
                        <SelectItem key={v} value={v}>{label}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <FormMessage />
                </FormItem>
              )}
            />

            {/* GLOBAL_PACKAGE — package picker */}
            {grantType === 'GLOBAL_PACKAGE' && (
              <FormField
                control={form.control}
                name="packageCode"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Package</FormLabel>
                    <Select value={field.value} onValueChange={field.onChange}>
                      <FormControl>
                        <SelectTrigger>
                          <SelectValue placeholder="Select package…" />
                        </SelectTrigger>
                      </FormControl>
                      <SelectContent>
                        {packages?.items.map((p) => (
                          <SelectItem key={p.packageId} value={p.packageCode}>
                            <span className="font-mono text-xs mr-2">{p.packageCode}</span>
                            {p.packageName}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    <FormMessage />
                  </FormItem>
                )}
              />
            )}

            {/* FULL_ACCOUNT / PATH_PREFIX — account picker */}
            {(grantType === 'FULL_ACCOUNT' || grantType === 'PATH_PREFIX') && (
              <FormField
                control={form.control}
                name="accountCode"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Account</FormLabel>
                    <Select value={field.value} onValueChange={(v) => { field.onChange(v); form.resetField('orgUnitCode'); form.resetField('orgUnitType') }}>
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

            {/* PATH_PREFIX — org unit picker */}
            {grantType === 'PATH_PREFIX' && watchedAccountCode && (
              <FormField
                control={form.control}
                name="orgUnitCode"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Org Unit (root of subtree)</FormLabel>
                    <Select
                      value={field.value}
                      onValueChange={(v) => {
                        field.onChange(v)
                        const unit = orgUnits?.items.find((u) => u.orgUnitCode === v)
                        if (unit) form.setValue('orgUnitType', unit.orgUnitType)
                      }}
                    >
                      <FormControl>
                        <SelectTrigger>
                          <SelectValue placeholder="Select org unit…" />
                        </SelectTrigger>
                      </FormControl>
                      <SelectContent>
                        {orgUnits?.items.map((u) => {
                          const depth = u.path.split('|').filter(Boolean).length - 1
                          const indent = '\u00a0\u00a0'.repeat(depth)
                          return (
                            <SelectItem key={u.orgUnitId} value={u.orgUnitCode}>
                              {indent}{u.orgUnitCode} — {u.orgUnitName}
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

            {/* COUNTRY_ALL — country code */}
            {grantType === 'COUNTRY_ALL' && (
              <FormField
                control={form.control}
                name="countryCode"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Country Code (e.g. GB, AU)</FormLabel>
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
                {mutation.error instanceof Error ? mutation.error.message : 'Failed to grant access.'}
              </p>
            )}

            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => onOpenChange(false)} disabled={mutation.isPending}>
                Cancel
              </Button>
              <Button type="submit" disabled={mutation.isPending}>
                {mutation.isPending ? 'Granting…' : 'Grant Access'}
              </Button>
            </DialogFooter>
          </form>
        </Form>
      </DialogContent>
    </Dialog>
  )
}
