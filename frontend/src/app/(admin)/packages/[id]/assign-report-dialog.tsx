'use client'

import { useMemo, useState } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Link } from 'lucide-react'
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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { api } from '@/lib/api'

const schema = z.object({
  reportCode: z.string().min(1, 'Report is required'),
})

type FormValues = z.infer<typeof schema>

interface AssignReportDialogProps {
  packageId: number
  packageCode: string
}

export function AssignReportDialog({ packageId, packageCode }: AssignReportDialogProps) {
  const [open, setOpen] = useState(false)
  const queryClient = useQueryClient()

  const { data: allReports } = useQuery({
    queryKey: ['reports'],
    queryFn: () => api.reports.list(),
    enabled: open,
  })

  const { data: packageReports } = useQuery({
    queryKey: ['packages', packageId, 'reports'],
    queryFn: () => api.packages.reports(packageId),
    enabled: open,
  })

  const availableReports = useMemo(() => {
    if (!allReports) return []
    const assigned = new Set((packageReports?.items ?? []).map((r) => r.biReportId))
    return allReports.items.filter((r) => !assigned.has(r.biReportId))
  }, [allReports, packageReports])

  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { reportCode: '' },
  })

  const mutation = useMutation({
    mutationFn: (values: FormValues) =>
      api.reports.assign({
        reportCode: values.reportCode,
        packageCode,
        remove: false,
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['packages', packageId, 'reports'] })
      queryClient.invalidateQueries({ queryKey: ['packages', packageId] })
      queryClient.invalidateQueries({ queryKey: ['reports'] })
      setOpen(false)
      form.reset()
    },
  })

  return (
    <>
      <Button size="sm" variant="outline" onClick={() => setOpen(true)}>
        <Link className="mr-1.5 h-4 w-4" />
        Assign Report
      </Button>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Assign Report to Package</DialogTitle>
          </DialogHeader>

          <Form {...form}>
            <form onSubmit={form.handleSubmit((v) => mutation.mutate(v))} className="space-y-4">
              <FormField
                control={form.control}
                name="reportCode"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Report</FormLabel>
                    <Select value={field.value} onValueChange={field.onChange} disabled={availableReports.length === 0}>
                      <FormControl>
                        <SelectTrigger>
                          <SelectValue
                            placeholder={
                              availableReports.length === 0
                                ? 'All reports are already in this package'
                                : 'Select report…'
                            }
                          />
                        </SelectTrigger>
                      </FormControl>
                      <SelectContent>
                        {availableReports.map((r) => (
                          <SelectItem key={r.biReportId} value={r.reportCode}>
                            <span className="font-mono text-xs mr-2">{r.reportCode}</span>
                            {r.reportName}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    <FormMessage />
                  </FormItem>
                )}
              />

              {mutation.isError && (
                <p className="text-sm text-destructive">
                  {mutation.error instanceof Error
                    ? mutation.error.message
                    : 'Failed to assign report.'}
                </p>
              )}

              <DialogFooter>
                <Button type="button" variant="outline" onClick={() => setOpen(false)} disabled={mutation.isPending}>
                  Cancel
                </Button>
                <Button type="submit" disabled={mutation.isPending || availableReports.length === 0}>
                  {mutation.isPending ? 'Assigning…' : 'Assign'}
                </Button>
              </DialogFooter>
            </form>
          </Form>
        </DialogContent>
      </Dialog>
    </>
  )
}
