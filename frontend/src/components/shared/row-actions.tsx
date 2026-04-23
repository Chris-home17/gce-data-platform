'use client'

import { useMutation, useQueryClient } from '@tanstack/react-query'
import { MoreHorizontal, CheckCircle, XCircle } from 'lucide-react'
import { Button } from '@/components/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'

interface RowActionsProps {
  isActive: boolean
  onToggle: () => Promise<void>
  invalidateKeys: unknown[][]
  entityLabel?: string
}

export function RowActions({ isActive, onToggle, invalidateKeys, entityLabel: _entityLabel = 'item' }: RowActionsProps) {
  const queryClient = useQueryClient()

  const mutation = useMutation({
    mutationFn: onToggle,
    onSuccess: () => {
      invalidateKeys.forEach((key) => queryClient.invalidateQueries({ queryKey: key }))
    },
  })

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          variant="ghost"
          size="sm"
          className="h-7 w-7 p-0 data-[state=open]:bg-muted"
          disabled={mutation.isPending}
          onClick={(e) => e.stopPropagation()}
        >
          <MoreHorizontal className="h-4 w-4" />
          <span className="sr-only">Actions</span>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        {isActive ? (
          <DropdownMenuItem
            className="text-destructive focus:text-destructive"
            onClick={(e) => { e.stopPropagation(); mutation.mutate() }}
          >
            <XCircle className="mr-2 h-4 w-4" />
            Deactivate
          </DropdownMenuItem>
        ) : (
          <DropdownMenuItem
            onClick={(e) => { e.stopPropagation(); mutation.mutate() }}
          >
            <CheckCircle className="mr-2 h-4 w-4 text-success" />
            Activate
          </DropdownMenuItem>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
