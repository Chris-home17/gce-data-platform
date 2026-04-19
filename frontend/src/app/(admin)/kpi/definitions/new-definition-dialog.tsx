'use client'

import { useState, useMemo } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { Loader2, Plus, X } from 'lucide-react'
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

const schema = z.object({
  kpiCode: z
    .string()
    .min(2)
    .max(50)
    .regex(/^[A-Z0-9_-]+$/i, 'Only letters, numbers, hyphens and underscores'),
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

export function NewDefinitionDialog() {
  const [open, setOpen] = useState(false)
  const [dropDownOptions, setDropDownOptions] = useState<string[]>([])
  const [newOption, setNewOption] = useState('')
  const [selectedTagIds, setSelectedTagIds] = useState<Set<number>>(new Set())
  const queryClient = useQueryClient()

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
      kpiCode: '',
      kpiName: '',
      kpiDescription: '',
      category: '',
      unit: '',
      dataType: 'Numeric',
      allowMultiValue: false,
      collectionType: 'Manual',
      thresholdDirection: 'none',
    },
  })

  const watchedDataType = form.watch('dataType')
  const isDropDown = watchedDataType === 'DropDown'

  const mutation = useMutation({
    mutationFn: (values: FormValues) =>
      api.kpi.definitions.create({
        ...values,
        kpiCode: values.kpiCode.toUpperCase(),
        thresholdDirection: values.thresholdDirection === 'none' ? null : values.thresholdDirection,
        kpiDescription: values.kpiDescription || undefined,
        category: values.category || undefined,
        unit: values.unit || undefined,
        dropDownOptions: isDropDown ? dropDownOptions : undefined,
        tagIds: selectedTagIds.size > 0 ? Array.from(selectedTagIds) : undefined,
      }),
    onSuccess: (def) => {
      queryClient.invalidateQueries({ queryKey: ['kpi', 'definitions'] })
      toast.success(`KPI "${def.kpiCode}" created.`)
      setOpen(false)
      form.reset()
      setDropDownOptions([])
      setNewOption('')
      setSelectedTagIds(new Set())
    },
    onError: (err: Error) => toast.error(err.message ?? 'Failed to create KPI definition.'),
  })

  function handleOpenChange(value: boolean) {
    if (!value) {
      form.reset()
      mutation.reset()
      setDropDownOptions([])
      setNewOption('')
      setSelectedTagIds(new Set())
    }
    setOpen(value)
  }

  function addOption() {
    const trimmed = newOption.trim()
    if (!trimmed || dropDownOptions.includes(trimmed)) return
    setDropDownOptions((prev) => [...prev, trimmed])
    setNewOption('')
  }

  function removeOption(idx: number) {
    setDropDownOptions((prev) => prev.filter((_, i) => i !== idx))
  }

  return (
    <Sheet open={open} onOpenChange={handleOpenChange}>
      <SheetTrigger asChild>
        <Button>
          <Plus className="mr-2 h-4 w-4" />
          New KPI
        </Button>
      </SheetTrigger>

      <SheetContent className="w-full sm:max-w-lg overflow-y-auto">
        <SheetHeader>
          <SheetTitle>New KPI Definition</SheetTitle>
          <SheetDescription>
            Add a KPI to the platform catalogue. Thresholds are set per assignment, not here.
          </SheetDescription>
        </SheetHeader>

        <Form {...form}>
          <form onSubmit={form.handleSubmit((v) => mutation.mutate(v))} className="mt-6 space-y-4">

            {/* ── Identity ─────────────────────────────── */}
            <SectionHeading>Identity</SectionHeading>

            <div className="grid grid-cols-2 gap-3">
              <FormField
                control={form.control}
                name="kpiCode"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Code</FormLabel>
                    <FormControl>
                      <Input
                        placeholder="e.g. S-005"
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
              <Button type="button" variant="outline" onClick={() => handleOpenChange(false)} disabled={mutation.isPending}>
                Cancel
              </Button>
              <Button
                type="submit"
                disabled={mutation.isPending || (isDropDown && dropDownOptions.length === 0)}
              >
                {mutation.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                {mutation.isPending ? 'Creating…' : 'Create KPI'}
              </Button>
            </SheetFooter>
          </form>
        </Form>
      </SheetContent>
    </Sheet>
  )
}
