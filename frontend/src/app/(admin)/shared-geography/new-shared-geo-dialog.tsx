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
  DialogFooter,
  DialogHeader,
  DialogTitle,
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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { api } from '@/lib/api'
const SHARED_GEO_TYPES = ['Region', 'SubRegion', 'Cluster', 'Country'] as const

const schema = z.object({
  geoUnitType: z.enum(SHARED_GEO_TYPES, { required_error: 'Type is required' }),
  geoUnitCode: z.string().min(1, 'Code is required').max(50),
  geoUnitName: z.string().min(1, 'Name is required').max(200),
  countryCode: z.string().optional(),
}).superRefine((values, ctx) => {
  if (values.geoUnitType === 'Country') {
    if (!values.countryCode?.trim()) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['countryCode'],
        message: 'Country code is required',
      })
    } else if (values.countryCode.trim().length < 2 || values.countryCode.trim().length > 10) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['countryCode'],
        message: 'Country code must be between 2 and 10 characters',
      })
    }
  }
})

type FormValues = z.infer<typeof schema>

export function NewSharedGeoDialog() {
  const [open, setOpen] = useState(false)
  const queryClient = useQueryClient()

  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      geoUnitType: 'Region',
      geoUnitCode: '',
      geoUnitName: '',
      countryCode: '',
    },
  })

  const watchedType = form.watch('geoUnitType')

  const mutation = useMutation({
    mutationFn: (values: FormValues) =>
      api.sharedGeoUnits.create({
        geoUnitType: values.geoUnitType,
        geoUnitCode: values.geoUnitCode.trim().toUpperCase(),
        geoUnitName: values.geoUnitName.trim(),
        countryCode:
          values.geoUnitType === 'Country' ? values.countryCode?.trim().toUpperCase() : undefined,
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['shared-geo-units'] })
      queryClient.invalidateQueries({ queryKey: ['org-units'] })
      setOpen(false)
      form.reset({
        geoUnitType: 'Region',
        geoUnitCode: '',
        geoUnitName: '',
        countryCode: '',
      })
    },
  })

  return (
    <>
      <Button size="sm" onClick={() => setOpen(true)}>
        <Plus className="mr-1.5 h-4 w-4" />
        New Shared Geo
      </Button>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>New Shared Geography Item</DialogTitle>
          </DialogHeader>

          <Form {...form}>
            <form onSubmit={form.handleSubmit((values) => mutation.mutate(values))} className="space-y-4">
              <FormField
                control={form.control}
                name="geoUnitType"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Type</FormLabel>
                    <Select
                      value={field.value}
                      onValueChange={(value) => {
                        field.onChange(value)
                        if (value !== 'Country') form.setValue('countryCode', '')
                      }}
                    >
                      <FormControl>
                        <SelectTrigger>
                          <SelectValue placeholder="Select type..." />
                        </SelectTrigger>
                      </FormControl>
                      <SelectContent>
                        {SHARED_GEO_TYPES.map((type) => (
                          <SelectItem key={type} value={type}>
                            {type}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    <FormMessage />
                  </FormItem>
                )}
              />

              <div className="grid grid-cols-2 gap-3">
                <FormField
                  control={form.control}
                  name="geoUnitCode"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Code</FormLabel>
                      <FormControl>
                        <Input placeholder="EMEA" className="font-mono" {...field} />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
                <FormField
                  control={form.control}
                  name="geoUnitName"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Name</FormLabel>
                      <FormControl>
                        <Input placeholder="Europe, Middle East & Africa" {...field} />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
              </div>

              {watchedType === 'Country' && (
                <FormField
                  control={form.control}
                  name="countryCode"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Country Code</FormLabel>
                      <FormControl>
                        <Input placeholder="BE" className="font-mono" {...field} />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
              )}

              {mutation.isError && (
                <p className="text-sm text-destructive">
                  {mutation.error instanceof Error
                    ? mutation.error.message
                    : 'Failed to create shared geography item.'}
                </p>
              )}

              <DialogFooter>
                <Button
                  type="button"
                  variant="outline"
                  onClick={() => setOpen(false)}
                  disabled={mutation.isPending}
                >
                  Cancel
                </Button>
                <Button type="submit" disabled={mutation.isPending}>
                  {mutation.isPending ? 'Creating...' : 'Create Shared Geo'}
                </Button>
              </DialogFooter>
            </form>
          </Form>
        </DialogContent>
      </Dialog>
    </>
  )
}
