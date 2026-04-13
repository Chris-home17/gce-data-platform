'use client'

import { useState } from 'react'
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
  packageCode: z.string().min(1, 'Package is required'),
  action: z.enum(['add', 'remove']),
})

type FormValues = z.infer<typeof schema>

export function AssignPackageDialog() {
  const [open, setOpen] = useState(false)
  const queryClient = useQueryClient()

  const { data: reports } = useQuery({
    queryKey: ['reports'],
    queryFn: () => api.reports.list(),
    enabled: open,
  })

  const { data: packages } = useQuery({
    queryKey: ['packages'],
    queryFn: () => api.packages.list(),
    enabled: open,
  })

  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { reportCode: '', packageCode: '', action: 'add' },
  })

  const mutation = useMutation({
    mutationFn: (values: FormValues) =>
      api.reports.assign({
        reportCode: values.reportCode,
        packageCode: values.packageCode,
        remove: values.action === 'remove',
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['reports'] })
      queryClient.invalidateQueries({ queryKey: ['packages'] })
      setOpen(false)
      form.reset()
    },
  })

  const action = form.watch('action')

  return (
    <>
      <Button size="sm" variant="outline" onClick={() => setOpen(true)}>
        <Link className="mr-1.5 h-4 w-4" />
        Assign to Package
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
                name="action"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Action</FormLabel>
                    <Select value={field.value} onValueChange={field.onChange}>
                      <FormControl>
                        <SelectTrigger>
                          <SelectValue />
                        </SelectTrigger>
                      </FormControl>
                      <SelectContent>
                        <SelectItem value="add">Add report to package</SelectItem>
                        <SelectItem value="remove">Remove report from package</SelectItem>
                      </SelectContent>
                    </Select>
                    <FormMessage />
                  </FormItem>
                )}
              />

              <FormField
                control={form.control}
                name="reportCode"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Report</FormLabel>
                    <Select value={field.value} onValueChange={field.onChange}>
                      <FormControl>
                        <SelectTrigger>
                          <SelectValue placeholder="Select report…" />
                        </SelectTrigger>
                      </FormControl>
                      <SelectContent>
                        {reports?.items.map((r) => (
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

              {mutation.isError && (
                <p className="text-sm text-destructive">
                  {mutation.error instanceof Error
                    ? mutation.error.message
                    : 'Operation failed.'}
                </p>
              )}

              <DialogFooter>
                <Button type="button" variant="outline" onClick={() => setOpen(false)} disabled={mutation.isPending}>
                  Cancel
                </Button>
                <Button
                  type="submit"
                  disabled={mutation.isPending}
                  variant={action === 'remove' ? 'destructive' : 'default'}
                >
                  {mutation.isPending
                    ? action === 'remove' ? 'Removing…' : 'Assigning…'
                    : action === 'remove' ? 'Remove' : 'Assign'}
                </Button>
              </DialogFooter>
            </form>
          </Form>
        </DialogContent>
      </Dialog>
    </>
  )
}
