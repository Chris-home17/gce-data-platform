'use client'

import { useEffect, useState } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { Loader2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import {
  Form,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
  FormControl,
} from '@/components/ui/form'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { api } from '@/lib/api'
import { parsePackageTags } from '@/types/api'
import type { KpiPackage } from '@/types/api'

const schema = z.object({
  packageName: z.string().min(1).max(200),
})

type FormValues = z.infer<typeof schema>

interface Props {
  pkg: KpiPackage
  open: boolean
  onClose: () => void
}

export function EditPackageDialog({ pkg, open, onClose }: Props) {
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
    defaultValues: { packageName: pkg.packageName },
  })

  useEffect(() => {
    if (open) {
      form.reset({ packageName: pkg.packageName })
      const currentTagIds = new Set(parsePackageTags(pkg.tagsRaw).map((t) => t.tagId))
      setSelectedTagIds(currentTagIds)
    }
  }, [open, pkg, form])

  const mutation = useMutation({
    mutationFn: (values: FormValues) =>
      api.kpi.packages.update(pkg.kpiPackageId, {
        packageName: values.packageName,
        tagIds: Array.from(selectedTagIds),
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['kpi', 'packages'] })
      toast.success('Package updated.')
      onClose()
    },
    onError: (err: Error) => toast.error(err.message ?? 'Failed to update package.'),
  })

  function toggleTag(tagId: number) {
    setSelectedTagIds((prev) => {
      const next = new Set(prev)
      if (next.has(tagId)) next.delete(tagId)
      else next.add(tagId)
      return next
    })
  }

  return (
    <Dialog open={open} onOpenChange={(v) => { if (!v) onClose() }}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Edit Package</DialogTitle>
          <DialogDescription>
            Code <span className="font-mono font-medium">{pkg.packageCode}</span> is immutable.
          </DialogDescription>
        </DialogHeader>

        <Form {...form}>
          <form onSubmit={form.handleSubmit((v) => mutation.mutate(v))} className="space-y-4 py-2">
            <FormField
              control={form.control}
              name="packageName"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Name</FormLabel>
                  <FormControl>
                    <Input {...field} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />

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
              <Button type="button" variant="outline" onClick={onClose} disabled={mutation.isPending}>
                Cancel
              </Button>
              <Button type="submit" disabled={mutation.isPending}>
                {mutation.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                {mutation.isPending ? 'Saving…' : 'Save Changes'}
              </Button>
            </DialogFooter>
          </form>
        </Form>
      </DialogContent>
    </Dialog>
  )
}
