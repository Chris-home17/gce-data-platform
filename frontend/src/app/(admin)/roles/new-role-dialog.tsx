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
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from '@/components/ui/form'
import { Input } from '@/components/ui/input'
import { api } from '@/lib/api'
import { usePermissions } from '@/hooks/usePermissions'
import { PERMISSIONS } from '@/types/api'

const schema = z.object({
  roleCode: z
    .string()
    .min(1, 'Role code is required')
    .max(100)
    .regex(/^[A-Z0-9_]+$/, 'Only uppercase letters, numbers and underscores'),
  roleName: z.string().min(1, 'Role name is required').max(200),
  description: z.string().max(400).optional(),
})

type FormValues = z.infer<typeof schema>

export function NewRoleDialog() {
  const { can } = usePermissions()
  const [open, setOpen] = useState(false)
  const queryClient = useQueryClient()

  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { roleCode: '', roleName: '', description: '' },
  })

  const mutation = useMutation({
    mutationFn: (values: FormValues) =>
      api.roles.create({
        roleCode: values.roleCode,
        roleName: values.roleName,
        description: values.description || undefined,
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['roles'] })
      queryClient.invalidateQueries({ queryKey: ['coverage'] })
      setOpen(false)
      form.reset()
    },
  })

  function onSubmit(values: FormValues) {
    mutation.mutate(values)
  }

  if (!can(PERMISSIONS.PLATFORM_ROLES_MANAGE)) return null

  return (
    <>
      <Button size="sm" onClick={() => setOpen(true)}>
        <Plus className="mr-1.5 h-4 w-4" />
        New Role
      </Button>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>New Role</DialogTitle>
          </DialogHeader>

          <Form {...form}>
            <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4">
              <FormField
                control={form.control}
                name="roleCode"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Role Code</FormLabel>
                    <FormControl>
                      <Input
                        placeholder="ACCOUNT_ADMIN"
                        className="font-mono uppercase"
                        {...field}
                        onChange={(e) =>
                          field.onChange(e.target.value.toUpperCase())
                        }
                      />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />

              <FormField
                control={form.control}
                name="roleName"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Role Name</FormLabel>
                    <FormControl>
                      <Input placeholder="Account Administrator" {...field} />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />

              <FormField
                control={form.control}
                name="description"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>
                      Description{' '}
                      <span className="text-muted-foreground font-normal">(optional)</span>
                    </FormLabel>
                    <FormControl>
                      <Input placeholder="Full administrative access to an account" {...field} />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />

              {mutation.isError && (
                <p className="text-sm text-destructive">
                  {mutation.error instanceof Error
                    ? mutation.error.message
                    : 'Failed to create role.'}
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
                  {mutation.isPending ? 'Creating…' : 'Create Role'}
                </Button>
              </DialogFooter>
            </form>
          </Form>
        </DialogContent>
      </Dialog>
    </>
  )
}
