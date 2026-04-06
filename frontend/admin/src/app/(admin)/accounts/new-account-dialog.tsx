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
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from '@/components/ui/form'
import { Input } from '@/components/ui/input'
import { api } from '@/lib/api'
import { usePermissions } from '@/hooks/usePermissions'
import { PERMISSIONS } from '@/types/api'

// ---------------------------------------------------------------------------
// Zod schema
// ---------------------------------------------------------------------------

const createAccountSchema = z.object({
  accountCode: z
    .string()
    .min(2, 'Account code must be at least 2 characters')
    .max(20, 'Account code must be 20 characters or fewer')
    .regex(/^[A-Z0-9_-]+$/i, 'Only letters, numbers, hyphens and underscores are allowed'),
  accountName: z
    .string()
    .min(2, 'Account name must be at least 2 characters')
    .max(100, 'Account name must be 100 characters or fewer'),
})

type CreateAccountValues = z.infer<typeof createAccountSchema>

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function NewAccountDialog() {
  const { can } = usePermissions()
  const [open, setOpen] = useState(false)
  const queryClient = useQueryClient()

  const form = useForm<CreateAccountValues>({
    resolver: zodResolver(createAccountSchema),
    defaultValues: {
      accountCode: '',
      accountName: '',
    },
  })

  const mutation = useMutation({
    mutationFn: (values: CreateAccountValues) => api.accounts.create(values),
    onSuccess: (newAccount) => {
      // Invalidate the accounts list so it refetches with the new entry
      queryClient.invalidateQueries({ queryKey: ['accounts'] })
      toast.success(`Account "${newAccount.accountName}" created successfully.`)
      setOpen(false)
      form.reset()
    },
    onError: (error: Error) => {
      toast.error(error.message ?? 'Failed to create account. Please try again.')
    },
  })

  function onSubmit(values: CreateAccountValues) {
    mutation.mutate(values)
  }

  function handleOpenChange(value: boolean) {
    if (!value) {
      form.reset()
      mutation.reset()
    }
    setOpen(value)
  }

  if (!can(PERMISSIONS.ACCOUNTS_MANAGE)) return null

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogTrigger asChild>
        <Button>
          <Plus className="mr-2 h-4 w-4" />
          New Account
        </Button>
      </DialogTrigger>

      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>New Account</DialogTitle>
          <DialogDescription>
            Create a new account on the GCE Data Platform. Account codes must be unique.
          </DialogDescription>
        </DialogHeader>

        <Form {...form}>
          <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4">
            <FormField
              control={form.control}
              name="accountCode"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Account Code</FormLabel>
                  <FormControl>
                    <Input
                      placeholder="e.g. ACME-001"
                      autoComplete="off"
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
              name="accountName"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Account Name</FormLabel>
                  <FormControl>
                    <Input placeholder="e.g. Acme Corporation" autoComplete="off" {...field} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />

            <DialogFooter>
              <Button
                type="button"
                variant="outline"
                onClick={() => handleOpenChange(false)}
                disabled={mutation.isPending}
              >
                Cancel
              </Button>
              <Button type="submit" disabled={mutation.isPending}>
                {mutation.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                {mutation.isPending ? 'Creating…' : 'Create Account'}
              </Button>
            </DialogFooter>
          </form>
        </Form>
      </DialogContent>
    </Dialog>
  )
}
