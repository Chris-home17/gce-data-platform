'use client'

import { useState } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { useMutation, useQueryClient } from '@tanstack/react-query'
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
import type { ApiList, Policy } from '@/types/api'

const ORG_UNIT_TYPES = ['Region', 'SubRegion', 'Cluster', 'Country', 'Area', 'Branch', 'Site'] as const

const schema = z
  .object({
    policyName: z.string().min(1, 'Policy name is required').max(200),
    roleCodeTemplate: z
      .string()
      .min(1, 'Role code template is required')
      .max(100)
      .regex(/^[\{A-Z0-9_\}]+$/, 'Only uppercase letters, numbers, underscores and {tokens}'),
    roleNameTemplate: z.string().min(1, 'Role name template is required').max(200),
    scopeType: z.enum(['NONE', 'ORGUNIT']),
    orgUnitType: z.enum(ORG_UNIT_TYPES).optional(),
    orgUnitCode: z.string().optional(),
    expandPerOrgUnit: z.boolean(),
    applyNow: z.boolean(),
  })
  .refine(
    (data) => {
      if (data.scopeType === 'ORGUNIT') {
        if (!data.orgUnitType) {
          return false
        }

        if (data.expandPerOrgUnit) {
          return true
        }

        return !!data.orgUnitCode
      }
      return true
    },
    {
      message: 'OrgUnit Type is required. OrgUnit Code is required unless per-org-unit expansion is enabled.',
      path: ['orgUnitType'],
    }
  )
  .refine(
    (data) => {
      if (!data.expandPerOrgUnit) {
        return true
      }

      const hasOrgUnitCodeToken = /\{ORGUNITCODE\}|\{OrgUnitCode\}/.test(data.roleCodeTemplate)
      const hasOrgUnitNameToken = /\{ORGUNITNAME\}|\{OrgUnitName\}/.test(data.roleCodeTemplate)
      return hasOrgUnitCodeToken || hasOrgUnitNameToken
    },
    {
      message: 'Role code template must include {OrgUnitCode} or {OrgUnitName} when expansion is enabled.',
      path: ['roleCodeTemplate'],
    }
  )
  .refine(
    (data) => {
      if (!data.expandPerOrgUnit) {
        return true
      }

      const hasOrgUnitCodeToken = /\{OrgUnitCode\}|\{ORGUNITCODE\}/.test(data.roleNameTemplate)
      const hasOrgUnitNameToken = /\{OrgUnitName\}|\{ORGUNITNAME\}/.test(data.roleNameTemplate)
      return hasOrgUnitCodeToken || hasOrgUnitNameToken
    },
    {
      message: 'Role name template must include {OrgUnitCode} or {OrgUnitName} when expansion is enabled.',
      path: ['roleNameTemplate'],
    }
  )

type FormValues = z.infer<typeof schema>

export function NewPolicyDialog() {
  const [open, setOpen] = useState(false)
  const queryClient = useQueryClient()

  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      policyName: '',
      roleCodeTemplate: '',
      roleNameTemplate: '',
      scopeType: 'NONE',
      orgUnitType: undefined,
      orgUnitCode: '',
      expandPerOrgUnit: false,
      applyNow: true,
    },
  })

  const scopeType = form.watch('scopeType')
  const expandPerOrgUnit = form.watch('expandPerOrgUnit')

  const mutation = useMutation({
    mutationFn: (values: FormValues) =>
      api.policies.create({
        policyName: values.policyName,
        roleCodeTemplate: values.roleCodeTemplate,
        roleNameTemplate: values.roleNameTemplate,
        scopeType: values.scopeType,
        orgUnitType: values.scopeType === 'ORGUNIT' ? values.orgUnitType : undefined,
        orgUnitCode: values.scopeType === 'ORGUNIT' && !values.expandPerOrgUnit ? values.orgUnitCode : undefined,
        expandPerOrgUnit: values.scopeType === 'ORGUNIT' ? values.expandPerOrgUnit : false,
        applyNow: values.applyNow,
      }),
    onSuccess: (created) => {
      // Immediately insert the new policy returned by the server so the table
      // updates without waiting for the background refetch to complete.
      queryClient.setQueryData<ApiList<Policy>>(['policies'], (old) =>
        old
          ? { items: [...old.items, created], totalCount: old.totalCount + 1 }
          : { items: [created], totalCount: 1 }
      )
      queryClient.invalidateQueries({ queryKey: ['policies'] })
      queryClient.invalidateQueries({ queryKey: ['roles'] })
      queryClient.invalidateQueries({ queryKey: ['accounts'] })
      queryClient.invalidateQueries({ queryKey: ['users'] })
      queryClient.invalidateQueries({ queryKey: ['coverage'] })
      setOpen(false)
      form.reset()
    },
  })

  return (
    <>
      <Button size="sm" onClick={() => setOpen(true)}>
        <Plus className="mr-1.5 h-4 w-4" />
        New Policy
      </Button>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>New Role Policy</DialogTitle>
          </DialogHeader>

          <Form {...form}>
            <form onSubmit={form.handleSubmit((v) => mutation.mutate(v))} className="space-y-4">
              <FormField
                control={form.control}
                name="policyName"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Policy Name</FormLabel>
                    <FormControl>
                      <Input placeholder="Global Account Director" {...field} />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />

              <div className="grid grid-cols-2 gap-3">
                <FormField
                  control={form.control}
                  name="roleCodeTemplate"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Role Code Template</FormLabel>
                      <FormControl>
                        <Input
                          placeholder="{AccountCode}_GAD"
                          className="font-mono"
                          {...field}
                          onChange={(e) => field.onChange(e.target.value.toUpperCase())}
                        />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />

                <FormField
                  control={form.control}
                  name="roleNameTemplate"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Role Name Template</FormLabel>
                      <FormControl>
                        <Input placeholder="{AccountName} Global Director" {...field} />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
              </div>

              <p className="text-xs text-muted-foreground -mt-2">
                Use <code className="font-mono bg-muted px-1 rounded">{'{AccountCode}'}</code> and{' '}
                <code className="font-mono bg-muted px-1 rounded">{'{AccountName}'}</code> as tokens.
                {scopeType === 'ORGUNIT' && (
                  <>
                    {' '}Per-org-unit policies can also use <code className="font-mono bg-muted px-1 rounded">{'{OrgUnitCode}'}</code> and{' '}
                    <code className="font-mono bg-muted px-1 rounded">{'{OrgUnitName}'}</code>.
                  </>
                )}
              </p>

              <FormField
                control={form.control}
                name="scopeType"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Scope</FormLabel>
                    <Select value={field.value} onValueChange={field.onChange}>
                      <FormControl>
                        <SelectTrigger>
                          <SelectValue />
                        </SelectTrigger>
                      </FormControl>
                      <SelectContent>
                        <SelectItem value="NONE">Global (no org unit scope)</SelectItem>
                        <SelectItem value="ORGUNIT">Org Unit scoped</SelectItem>
                      </SelectContent>
                    </Select>
                    <FormMessage />
                  </FormItem>
                )}
              />

              {scopeType === 'ORGUNIT' && (
                <>
                  <div className="grid grid-cols-2 gap-3">
                    <FormField
                      control={form.control}
                      name="orgUnitType"
                      render={({ field }) => (
                        <FormItem>
                          <FormLabel>Org Unit Type</FormLabel>
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
                    <FormField
                      control={form.control}
                      name="orgUnitCode"
                      render={({ field }) => (
                        <FormItem>
                          <FormLabel>Org Unit Code</FormLabel>
                          <FormControl>
                            <Input
                              placeholder={expandPerOrgUnit ? 'Optional exact code filter' : 'Required exact code'}
                              {...field}
                            />
                          </FormControl>
                          <FormMessage />
                        </FormItem>
                      )}
                    />
                  </div>

                  <FormField
                    control={form.control}
                    name="expandPerOrgUnit"
                    render={({ field }) => (
                      <FormItem className="flex items-center justify-between rounded-md border px-3 py-2">
                        <div>
                          <FormLabel className="text-sm">Create one role per matching org unit</FormLabel>
                          <FormDescription className="text-xs">
                            For example, one supervisor role per site. When enabled, the code filter becomes optional.
                          </FormDescription>
                        </div>
                        <FormControl>
                          <Switch checked={field.value} onCheckedChange={field.onChange} />
                        </FormControl>
                      </FormItem>
                    )}
                  />
                </>
              )}

              <FormField
                control={form.control}
                name="applyNow"
                render={({ field }) => (
                  <FormItem className="flex items-center justify-between rounded-md border px-3 py-2">
                    <div>
                      <FormLabel className="text-sm">Apply now</FormLabel>
                      <FormDescription className="text-xs">
                        Re-apply active policies across existing accounts immediately after creation.
                      </FormDescription>
                    </div>
                    <FormControl>
                      <Switch checked={field.value} onCheckedChange={field.onChange} />
                    </FormControl>
                  </FormItem>
                )}
              />

              {mutation.isError && (
                <p className="text-sm text-destructive">
                  {mutation.error instanceof Error
                    ? mutation.error.message
                    : 'Failed to create policy.'}
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
                  {mutation.isPending ? 'Creating…' : 'Create Policy'}
                </Button>
              </DialogFooter>
            </form>
          </Form>
        </DialogContent>
      </Dialog>
    </>
  )
}
