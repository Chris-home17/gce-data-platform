'use client'

import { useEffect, useState, useMemo } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { Loader2, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetFooter,
  SheetHeader,
  SheetTitle,
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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Switch } from '@/components/ui/switch'
import { Badge } from '@/components/ui/badge'
import { api } from '@/lib/api'
import type { KpiDefinition } from '@/types/api'

function parseTagsRaw(raw: string | null): Array<{ id: number; name: string }> {
  if (!raw) return []
  return raw.split('|').map((part) => {
    const [id, ...rest] = part.split(':')
    return { id: parseInt(id), name: rest.join(':') }
  })
}

const schema = z.object({
  kpiName: z.string().min(2).max(200),
  kpiDescription: z.string().max(1000).optional(),
  category: z.string().max(100).optional(),
  unit: z.string().max(50).optional(),
  dataType: z.enum(['Numeric', 'Percentage', 'Boolean', 'Text', 'Currency', 'DropDown']),
  allowMultiValue: z.boolean().default(false),
  collectionType: z.enum(['Manual', 'Automated', 'BulkUpload']),
  thresholdDirection: z.enum(['Higher', 'Lower', 'none']).optional(),
})

type FormValues = z.infer<typeof schema>

function SectionHeading({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex items-center gap-3 pt-2">
      <span className="text-xs font-semibold uppercase tracking-wider text-muted-foreground whitespace-nowrap">
        {children}
      </span>
      <div className="flex-1 border-t" />
    </div>
  )
}

interface EditDefinitionSheetProps {
  kpi: KpiDefinition
  open: boolean
  onClose: () => void
}

export function EditDefinitionSheet({ kpi, open, onClose }: EditDefinitionSheetProps) {
  const queryClient = useQueryClient()

  const [dropDownOptions, setDropDownOptions] = useState<string[]>([])
  const [newOption, setNewOption] = useState('')
  const [selectedTagIds, setSelectedTagIds] = useState<Set<number>>(new Set())

  const tagsQuery = useQuery({
    queryKey: ['tags'],
    queryFn: () => api.tags.list(),
    enabled: open,
  })
  const activeTags = useMemo(
    () => (tagsQuery.data?.items ?? []).filter((t) => t.isActive),
    [tagsQuery.data]
  )

  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      kpiName: kpi.kpiName,
      kpiDescription: kpi.kpiDescription ?? '',
      category: kpi.category ?? '',
      unit: kpi.unit ?? '',
      dataType: kpi.dataType as FormValues['dataType'],
      allowMultiValue: kpi.allowMultiValue,
      collectionType: kpi.collectionType as FormValues['collectionType'],
      thresholdDirection: (kpi.thresholdDirection as FormValues['thresholdDirection']) ?? 'none',
    },
  })

  // Re-populate form and dropdown options whenever the KPI changes (row re-opened)
  useEffect(() => {
    if (open) {
      form.reset({
        kpiName: kpi.kpiName,
        kpiDescription: kpi.kpiDescription ?? '',
        category: kpi.category ?? '',
        unit: kpi.unit ?? '',
        dataType: kpi.dataType as FormValues['dataType'],
        allowMultiValue: kpi.allowMultiValue,
        collectionType: kpi.collectionType as FormValues['collectionType'],
        thresholdDirection: (kpi.thresholdDirection as FormValues['thresholdDirection']) ?? 'none',
      })
      setDropDownOptions(
        kpi.dropDownOptionsRaw ? kpi.dropDownOptionsRaw.split('||').filter(Boolean) : []
      )
      setNewOption('')
      setSelectedTagIds(new Set(parseTagsRaw(kpi.tagsRaw).map((t) => t.id)))
    }
  }, [open, kpi.kpiId]) // eslint-disable-line react-hooks/exhaustive-deps

  const watchedDataType = form.watch('dataType')
  const isDropDown = watchedDataType === 'DropDown'

  const mutation = useMutation({
    mutationFn: (values: FormValues) =>
      api.kpi.definitions.update(kpi.kpiId, {
        ...values,
        thresholdDirection: values.thresholdDirection === 'none' ? null : values.thresholdDirection,
        kpiDescription: values.kpiDescription || undefined,
        category: values.category || undefined,
        unit: values.unit || undefined,
        dropDownOptions: isDropDown ? dropDownOptions : null,
        tagIds: Array.from(selectedTagIds),
      }),
    onSuccess: (updated) => {
      queryClient.invalidateQueries({ queryKey: ['kpi', 'definitions'] })
      toast.success(`KPI "${updated.kpiCode}" updated.`)
      onClose()
    },
    onError: (err: Error) => toast.error(err.message ?? 'Failed to update KPI definition.'),
  })

  function addOption() {
    const trimmed = newOption.trim()
    if (!trimmed || dropDownOptions.includes(trimmed)) return
    setDropDownOptions((prev) => [...prev, trimmed])
    setNewOption('')
  }

  function removeOption(idx: number) {
    setDropDownOptions((prev) => prev.filter((_, i) => i !== idx))
  }

  function handleOpenChange(value: boolean) {
    if (!value) {
      mutation.reset()
      onClose()
    }
  }

  return (
    <Sheet open={open} onOpenChange={handleOpenChange}>
      <SheetContent className="w-full sm:max-w-lg overflow-y-auto">
        <SheetHeader>
          <SheetTitle>Edit KPI Definition</SheetTitle>
          <SheetDescription>
            <span className="font-mono">{kpi.kpiCode}</span> — KPI code cannot be changed.
          </SheetDescription>
        </SheetHeader>

        <Form {...form}>
          <form onSubmit={form.handleSubmit((v) => mutation.mutate(v))} className="mt-6 space-y-4">

            {/* ── Identity ─────────────────────────────── */}
            <SectionHeading>Identity</SectionHeading>

            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-2">
                <p className="text-sm font-medium leading-none">Code</p>
                <p className="h-9 flex items-center px-3 rounded-md border bg-muted text-sm font-mono text-muted-foreground">
                  {kpi.kpiCode}
                </p>
              </div>
              <FormField
                control={form.control}
                name="category"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Category <span className="text-muted-foreground">(optional)</span></FormLabel>
                    <FormControl>
                      <Input placeholder="e.g. Safety" {...field} />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />
            </div>

            <FormField
              control={form.control}
              name="kpiName"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Name</FormLabel>
                  <FormControl>
                    <Input placeholder="e.g. Vehicle Incident Rate" {...field} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />

            <FormField
              control={form.control}
              name="kpiDescription"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Description <span className="text-muted-foreground">(optional)</span></FormLabel>
                  <FormControl>
                    <Input placeholder="How to calculate / collect this KPI" {...field} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />

            {/* ── Data shape ───────────────────────────── */}
            <SectionHeading>Data shape</SectionHeading>

            <div className="grid grid-cols-2 gap-3">
              <FormField
                control={form.control}
                name="dataType"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Data Type</FormLabel>
                    <Select value={field.value} onValueChange={field.onChange}>
                      <FormControl><SelectTrigger><SelectValue /></SelectTrigger></FormControl>
                      <SelectContent>
                        {(['Numeric', 'Percentage', 'Boolean', 'Text', 'Currency', 'DropDown'] as const).map((v) => (
                          <SelectItem key={v} value={v}>{v}</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    {kpi.assignmentCount > 0 && (
                      <p className="text-xs text-amber-600">
                        {kpi.assignmentCount} assignment{kpi.assignmentCount !== 1 ? 's' : ''} exist — changing type may affect existing data.
                      </p>
                    )}
                    <FormMessage />
                  </FormItem>
                )}
              />
              <FormField
                control={form.control}
                name="unit"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Unit <span className="text-muted-foreground">(optional)</span></FormLabel>
                    <FormControl>
                      <Input placeholder="e.g. %, count, EUR" {...field} />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />
            </div>

            {/* ── DropDown-specific ────────────────────── */}
            {isDropDown && (
              <>
                <FormField
                  control={form.control}
                  name="allowMultiValue"
                  render={({ field }) => (
                    <FormItem className="flex items-center justify-between rounded-md border px-3 py-2.5 space-y-0">
                      <div>
                        <FormLabel className="font-medium">Allow multiple selections</FormLabel>
                        <FormDescription className="text-xs">
                          Users can pick more than one option when submitting.
                        </FormDescription>
                      </div>
                      <FormControl>
                        <Switch checked={field.value} onCheckedChange={field.onChange} />
                      </FormControl>
                    </FormItem>
                  )}
                />

                <div className="space-y-2">
                  <p className="text-sm font-medium leading-none">Options</p>
                  <p className="text-xs text-muted-foreground">
                    Choices shown when filling in this KPI. Can be overridden per assignment template.
                  </p>

                  {dropDownOptions.length > 0 && (
                    <div className="flex flex-wrap gap-1.5">
                      {dropDownOptions.map((opt, idx) => (
                        <span
                          key={idx}
                          className="inline-flex items-center gap-1 rounded-md border bg-background px-2 py-0.5 text-xs"
                        >
                          {opt}
                          <button
                            type="button"
                            onClick={() => removeOption(idx)}
                            className="text-muted-foreground hover:text-destructive transition-colors"
                          >
                            <X className="h-3 w-3" />
                          </button>
                        </span>
                      ))}
                    </div>
                  )}

                  <div className="flex gap-2">
                    <Input
                      value={newOption}
                      onChange={(e) => setNewOption(e.target.value)}
                      onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); addOption() } }}
                      placeholder="Add an option…"
                      className="text-sm h-8"
                    />
                    <Button
                      type="button"
                      variant="outline"
                      size="sm"
                      className="h-8 shrink-0"
                      onClick={addOption}
                      disabled={!newOption.trim()}
                    >
                      Add
                    </Button>
                  </div>
                </div>
              </>
            )}

            {/* ── Collection ───────────────────────────── */}
            <SectionHeading>Collection</SectionHeading>

            <div className="grid grid-cols-2 gap-3">
              <FormField
                control={form.control}
                name="collectionType"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Collection type</FormLabel>
                    <Select value={field.value} onValueChange={field.onChange}>
                      <FormControl><SelectTrigger><SelectValue /></SelectTrigger></FormControl>
                      <SelectContent>
                        {(['Manual', 'Automated', 'BulkUpload'] as const).map((v) => (
                          <SelectItem key={v} value={v}>{v}</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    <FormMessage />
                  </FormItem>
                )}
              />
              <FormField
                control={form.control}
                name="thresholdDirection"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Default direction</FormLabel>
                    <Select value={field.value ?? 'none'} onValueChange={field.onChange}>
                      <FormControl><SelectTrigger><SelectValue placeholder="—" /></SelectTrigger></FormControl>
                      <SelectContent>
                        <SelectItem value="none">Not set</SelectItem>
                        <SelectItem value="Higher">↑ Higher is better</SelectItem>
                        <SelectItem value="Lower">↓ Lower is better</SelectItem>
                      </SelectContent>
                    </Select>
                    <FormDescription>Can be overridden per assignment.</FormDescription>
                    <FormMessage />
                  </FormItem>
                )}
              />
            </div>

            {/* ── Tags ─────────────────────────────────── */}
            {activeTags.length > 0 && (
              <>
                <SectionHeading>Tags</SectionHeading>
                <div className="flex flex-wrap gap-1.5">
                  {activeTags.map((tag) => {
                    const selected = selectedTagIds.has(tag.tagId)
                    return (
                      <button
                        key={tag.tagId}
                        type="button"
                        onClick={() => {
                          setSelectedTagIds((prev) => {
                            const next = new Set(prev)
                            if (next.has(tag.tagId)) next.delete(tag.tagId)
                            else next.add(tag.tagId)
                            return next
                          })
                        }}
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
              </>
            )}

            <SheetFooter className="pt-2">
              <Button type="button" variant="outline" onClick={onClose} disabled={mutation.isPending}>
                Cancel
              </Button>
              <Button
                type="submit"
                disabled={mutation.isPending || (isDropDown && dropDownOptions.length === 0)}
              >
                {mutation.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                {mutation.isPending ? 'Saving…' : 'Save Changes'}
              </Button>
            </SheetFooter>
          </form>
        </Form>
      </SheetContent>
    </Sheet>
  )
}
