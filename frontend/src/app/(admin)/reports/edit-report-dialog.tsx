'use client'

import { useEffect } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { useMutation, useQueryClient } from '@tanstack/react-query'
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
import { Label } from '@/components/ui/label'
import { Button } from '@/components/ui/button'
import { api } from '@/lib/api'
import type { BiReport } from '@/types/api'

const schema = z.object({
  reportName: z.string().min(1, 'Name is required').max(200),
  reportUri: z.string().max(500).optional(),
})

type FormValues = z.infer<typeof schema>

interface EditReportDialogProps {
  report: BiReport
  open: boolean
  onOpenChange: (open: boolean) => void
}

export function EditReportDialog({ report, open, onOpenChange }: EditReportDialogProps) {
  const queryClient = useQueryClient()

  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      reportName: report.reportName,
      reportUri: report.reportUri ?? '',
    },
  })

  useEffect(() => {
    if (open) {
      form.reset({
        reportName: report.reportName,
        reportUri: report.reportUri ?? '',
      })
    }
  }, [open, report, form])

  const mutation = useMutation({
    mutationFn: (values: FormValues) =>
      api.reports.update(report.biReportId, {
        reportName: values.reportName,
        reportUri: values.reportUri || undefined,
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['reports'] })
      onOpenChange(false)
    },
  })

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Edit BI Report</DialogTitle>
        </DialogHeader>

        <Form {...form}>
          <form onSubmit={form.handleSubmit((v) => mutation.mutate(v))} className="space-y-4">
            <div className="space-y-2">
              <Label>Code</Label>
              <Input value={report.reportCode} disabled className="font-mono bg-muted" />
            </div>

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
                      placeholder="https://app.powerbi.com/groups/<workspace-id>/reports/<report-id>"
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
                  : 'Failed to update report.'}
              </p>
            )}

            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => onOpenChange(false)} disabled={mutation.isPending}>
                Cancel
              </Button>
              <Button type="submit" disabled={mutation.isPending}>
                {mutation.isPending ? 'Saving…' : 'Save Changes'}
              </Button>
            </DialogFooter>
          </form>
        </Form>
      </DialogContent>
    </Dialog>
  )
}
