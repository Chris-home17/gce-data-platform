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
  FormDescription,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from '@/components/ui/form'
import { Input } from '@/components/ui/input'
import { api } from '@/lib/api'

// Code is locked from creation onward — uppercase alphanumeric, 1-20 chars.
// Auto-generated KPI codes use it as a prefix ({CODE}-001, {CODE}-002, ...).
const schema = z.object({
  code: z
    .string()
    .min(1, 'Code is required')
    .max(20, 'Code must be 20 chars or fewer')
    .regex(/^[A-Z0-9]+$/i, 'Letters and numbers only (no spaces or punctuation)'),
  name: z.string().min(1, 'Name is required').max(100),
  description: z.string().max(500).optional(),
})

type FormValues = z.infer<typeof schema>

export function NewCategoryDialog() {
  const [open, setOpen] = useState(false)
  const queryClient = useQueryClient()

  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { code: '', name: '', description: '' },
  })

  const mutation = useMutation({
    mutationFn: (values: FormValues) =>
      api.kpi.categories.create({
        code: values.code.toUpperCase(),
        name: values.name.trim(),
        description: values.description?.trim() || null,
        isActive: true,
      }),
    onSuccess: (cat) => {
      queryClient.invalidateQueries({ queryKey: ['kpi', 'categories'] })
      toast.success(`Category "${cat.code}" created.`)
      setOpen(false)
      form.reset()
    },
    onError: (err: Error) => toast.error(err.message ?? 'Failed to create category.'),
  })

  function handleOpenChange(value: boolean) {
    if (!value) {
      form.reset()
      mutation.reset()
    }
    setOpen(value)
  }

  return (
    <Sheet open={open} onOpenChange={handleOpenChange}>
      <SheetTrigger asChild>
        <Button>
          <Plus className="mr-2 h-4 w-4" />
          New category
        </Button>
      </SheetTrigger>

      <SheetContent className="w-full sm:max-w-md overflow-y-auto">
        <SheetHeader>
          <SheetTitle>New KPI category</SheetTitle>
          <SheetDescription>
            Categories are global — shared across all accounts. Code is locked once saved.
          </SheetDescription>
        </SheetHeader>

        <Form {...form}>
          <form onSubmit={form.handleSubmit((v) => mutation.mutate(v))} className="mt-6 space-y-4">
            <FormField
              control={form.control}
              name="code"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Code</FormLabel>
                  <FormControl>
                    <Input
                      placeholder="e.g. SAF"
                      maxLength={20}
                      {...field}
                      onChange={(e) => field.onChange(e.target.value.toUpperCase())}
                    />
                  </FormControl>
                  <FormDescription className="text-xs">
                    Uppercase alphanumeric, 1-20 chars. Used as a prefix for auto-generated KPI codes
                    (e.g. SAF-001). <strong>Cannot be changed later.</strong>
                  </FormDescription>
                  <FormMessage />
                </FormItem>
              )}
            />

            <FormField
              control={form.control}
              name="name"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Name</FormLabel>
                  <FormControl>
                    <Input placeholder="e.g. Safety" {...field} />
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
                  <FormLabel>Description <span className="text-muted-foreground">(optional)</span></FormLabel>
                  <FormControl>
                    <Input placeholder="What this category groups together" {...field} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />

            <SheetFooter className="pt-2">
              <Button type="button" variant="outline" onClick={() => handleOpenChange(false)} disabled={mutation.isPending}>
                Cancel
              </Button>
              <Button type="submit" disabled={mutation.isPending}>
                {mutation.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                {mutation.isPending ? 'Creating…' : 'Create category'}
              </Button>
            </SheetFooter>
          </form>
        </Form>
      </SheetContent>
    </Sheet>
  )
}
