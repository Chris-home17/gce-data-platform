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

const schema = z.object({
  reportCode: z
    .string()
    .min(1, 'Code is required')
    .max(100)
    .regex(/^[A-Z0-9_-]+$/, 'Only uppercase letters, numbers, hyphens and underscores'),
  reportName: z.string().min(1, 'Name is required').max(200),
  reportUri: z.string().max(500).optional(),
})

type FormValues = z.infer<typeof schema>

export function NewReportDialog() {
  const [open, setOpen] = useState(false)
  const queryClient = useQueryClient()

  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { reportCode: '', reportName: '', reportUri: '' },
  })

  const mutation = useMutation({
    mutationFn: (values: FormValues) =>
      api.reports.create({
        reportCode: values.reportCode,
        reportName: values.reportName,
        reportUri: values.reportUri || undefined,
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['reports'] })
      setOpen(false)
      form.reset()
    },
  })

  return (
    <>
      <Button size="sm" onClick={() => setOpen(true)}>
        <Plus className="mr-1.5 h-4 w-4" />
        New Report
      </Button>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>New BI Report</DialogTitle>
          </DialogHeader>

          <Form {...form}>
            <form onSubmit={form.handleSubmit((v) => mutation.mutate(v))} className="space-y-4">
              <FormField
                control={form.control}
                name="reportCode"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Code</FormLabel>
                    <FormControl>
                      <Input
                        placeholder="RPT-SAFETY-001"
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
                name="reportName"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Name</FormLabel>
                    <FormControl>
                      <Input placeholder="Monthly Safety Dashboard" {...field} />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />

              <FormField
                control={form.control}
                name="reportUri"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Report URI <span className="text-muted-foreground">(optional)</span></FormLabel>
                    <FormControl>
                      <Input
                        placeholder="powerbi://workspaces/..."
                        className="font-mono text-sm"
                        {...field}
                      />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />

              {mutation.isError && (
                <p className="text-sm text-destructive">
                  {mutation.error instanceof Error
                    ? mutation.error.message
                    : 'Failed to create report.'}
                </p>
              )}

              <DialogFooter>
                <Button type="button" variant="outline" onClick={() => setOpen(false)} disabled={mutation.isPending}>
                  Cancel
                </Button>
                <Button type="submit" disabled={mutation.isPending}>
                  {mutation.isPending ? 'Creating…' : 'Create Report'}
                </Button>
              </DialogFooter>
            </form>
          </Form>
        </DialogContent>
      </Dialog>
    </>
  )
}
