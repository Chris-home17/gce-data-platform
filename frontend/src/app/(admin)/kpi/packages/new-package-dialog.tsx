'use client'

import { useState } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
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
import { Badge } from '@/components/ui/badge'
import { api } from '@/lib/api'

const schema = z.object({
  packageCode: z
    .string()
    .min(1)
    .max(50)
    .regex(/^[A-Z0-9_-]+$/i, 'Alphanumeric, hyphens and underscores only'),
  packageName: z.string().min(1).max(200),
})

type FormValues = z.infer<typeof schema>

export function NewPackageDialog() {
  const [open, setOpen] = useState(false)
  const [selectedTagIds, setSelectedTagIds] = useState<Set<number>>(new Set())
  const queryClient = useQueryClient()

  const tagsQuery = useQuery({
    queryKey: ['tags'],
    queryFn: () => api.tags.list(),
    enabled: open,
  })
  const activeTags = tagsQuery.data?.items.filter((t) => t.isActive) ?? []

  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { packageCode: '', packageName: '' },
  })

  const mutation = useMutation({
    mutationFn: (values: FormValues) =>
      api.kpi.packages.create({
        packageCode: values.packageCode.toUpperCase(),
        packageName: values.packageName,
        tagIds: Array.from(selectedTagIds),
      }),
    onSuccess: (pkg) => {
      queryClient.invalidateQueries({ queryKey: ['kpi', 'packages'] })
      toast.success(`Package "${pkg.packageCode}" created.`)
      setOpen(false)
      form.reset()
      setSelectedTagIds(new Set())
    },
    onError: (err: Error) => toast.error(err.message ?? 'Failed to create package.'),
  })

  function handleOpenChange(value: boolean) {
    if (!value) { form.reset(); mutation.reset(); setSelectedTagIds(new Set()) }
    setOpen(value)
  }

  function toggleTag(tagId: number) {
    setSelectedTagIds((prev) => {
      const next = new Set(prev)
      if (next.has(tagId)) next.delete(tagId)
      else next.add(tagId)
      return next
    })
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogTrigger asChild>
        <Button>
          <Plus className="mr-2 h-4 w-4" />
          New Package
        </Button>
      </DialogTrigger>

      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>New KPI Package</DialogTitle>
          <DialogDescription>
            A named bundle of KPIs that can be assigned to sites together.
          </DialogDescription>
        </DialogHeader>

        <Form {...form}>
          <form onSubmit={form.handleSubmit((v) => mutation.mutate(v))} className="space-y-4 py-2">
            <div className="grid grid-cols-2 gap-3">
              <FormField
                control={form.control}
                name="packageCode"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Code</FormLabel>
                    <FormControl>
                      <Input
                        placeholder="e.g. SAFETY-2026"
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
                name="packageName"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Name</FormLabel>
                    <FormControl>
                      <Input placeholder="e.g. Safety KPIs 2026" {...field} />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />
            </div>

            {activeTags.length > 0 && (
              <div className="space-y-1.5">
                <p className="text-sm font-medium">Tags <span className="text-muted-foreground font-normal">(optional)</span></p>
                <div className="flex flex-wrap gap-1.5">
                  {activeTags.map((tag) => {
                    const selected = selectedTagIds.has(tag.tagId)
                    return (
                      <button
                        key={tag.tagId}
                        type="button"
                        onClick={() => toggleTag(tag.tagId)}
                      >
                        <Badge
                          variant={selected ? 'default' : 'outline'}
                          className="cursor-pointer transition-colors"
                        >
                          {tag.tagName}
                        </Badge>
                      </button>
                    )
                  })}
                </div>
              </div>
            )}

            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => handleOpenChange(false)} disabled={mutation.isPending}>
                Cancel
              </Button>
              <Button type="submit" disabled={mutation.isPending}>
                {mutation.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                {mutation.isPending ? 'Creating…' : 'Create Package'}
              </Button>
            </DialogFooter>
          </form>
        </Form>
      </DialogContent>
    </Dialog>
  )
}
