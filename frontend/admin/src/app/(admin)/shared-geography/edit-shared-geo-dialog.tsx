'use client'

import { useEffect } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { useMutation, useQueryClient } from '@tanstack/react-query'
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
import { Button } from '@/components/ui/button'
import { api } from '@/lib/api'
import type { ApiList, SharedGeoUnit } from '@/types/api'

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

interface EditSharedGeoDialogProps {
  unit: SharedGeoUnit | null
  open: boolean
  onOpenChange: (open: boolean) => void
}

export function EditSharedGeoDialog({ unit, open, onOpenChange }: EditSharedGeoDialogProps) {
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

  useEffect(() => {
    if (unit && open) {
      form.reset({
        geoUnitType: unit.geoUnitType,
        geoUnitCode: unit.geoUnitCode,
        geoUnitName: unit.geoUnitName,
        countryCode: unit.countryCode ?? '',
      })
    }
  }, [unit, open, form])

  const watchedType = form.watch('geoUnitType')

  const mutation = useMutation({
    mutationFn: (values: FormValues) =>
      api.sharedGeoUnits.update(unit!.sharedGeoUnitId, {
        geoUnitType: values.geoUnitType,
        geoUnitCode: values.geoUnitCode.trim().toUpperCase(),
        geoUnitName: values.geoUnitName.trim(),
        countryCode:
          values.geoUnitType === 'Country' ? values.countryCode?.trim().toUpperCase() : undefined,
      }),
    onSuccess: (updated) => {
      queryClient.setQueryData<ApiList<SharedGeoUnit>>(['shared-geo-units'], (old) =>
        old
          ? {
              ...old,
              items: old.items.map((item) =>
                item.sharedGeoUnitId === updated.sharedGeoUnitId ? updated : item
              ),
            }
          : old
      )
      queryClient.invalidateQueries({ queryKey: ['shared-geo-units'] })
      queryClient.invalidateQueries({ queryKey: ['org-units'] })
      onOpenChange(false)
    },
  })

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Edit Shared Geography Item</DialogTitle>
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
                  : 'Failed to update shared geography item.'}
              </p>
            )}

            <DialogFooter>
              <Button
                type="button"
                variant="outline"
                onClick={() => onOpenChange(false)}
                disabled={mutation.isPending}
              >
                Cancel
              </Button>
              <Button type="submit" disabled={mutation.isPending}>
                {mutation.isPending ? 'Saving...' : 'Save Changes'}
              </Button>
            </DialogFooter>
          </form>
        </Form>
      </DialogContent>
    </Dialog>
  )
}
