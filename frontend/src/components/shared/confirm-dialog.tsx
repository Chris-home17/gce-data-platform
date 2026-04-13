'use client'

import { Loader2 } from 'lucide-react'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from '@/components/ui/alert-dialog'
import { buttonVariants } from '@/components/ui/button'
import { cn } from '@/lib/utils'
import type { ReactNode } from 'react'

interface ConfirmDialogProps {
  /** The trigger element that opens the dialog */
  trigger: ReactNode
  title: string
  description: string
  confirmLabel?: string
  cancelLabel?: string
  isLoading?: boolean
  onConfirm: () => void
}

/**
 * Reusable confirmation dialog for destructive or irreversible actions.
 *
 * Wraps shadcn AlertDialog and handles the loading state on the confirm button.
 * The trigger element is controlled externally so the dialog can be wired to
 * any UI element without imposing a specific button style.
 */
export function ConfirmDialog({
  trigger,
  title,
  description,
  confirmLabel = 'Confirm',
  cancelLabel = 'Cancel',
  isLoading = false,
  onConfirm,
}: ConfirmDialogProps) {
  return (
    <AlertDialog>
      <AlertDialogTrigger asChild>{trigger}</AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>{title}</AlertDialogTitle>
          <AlertDialogDescription>{description}</AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel disabled={isLoading}>{cancelLabel}</AlertDialogCancel>
          <AlertDialogAction
            className={cn(buttonVariants({ variant: 'destructive' }))}
            onClick={(e) => {
              e.preventDefault()
              onConfirm()
            }}
            disabled={isLoading}
          >
            {isLoading && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            {confirmLabel}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  )
}
