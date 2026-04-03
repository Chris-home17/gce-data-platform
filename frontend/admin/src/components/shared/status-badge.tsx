import { Badge } from '@/components/ui/badge'
import { cn } from '@/lib/utils'

type StatusValue =
  | 'Active'
  | 'Inactive'
  | 'Open'
  | 'Closed'
  | 'Draft'
  | 'Distributed'
  | 'Green'
  | 'Amber'
  | 'Red'
  | (string & {}) // allow arbitrary strings with a graceful fallback

interface StatusBadgeProps {
  status: StatusValue
  className?: string
}

const STATUS_STYLES: Record<string, string> = {
  // Green variants
  active: 'bg-green-100 text-green-800 border-green-200 dark:bg-green-900/30 dark:text-green-400 dark:border-green-800',
  open: 'bg-green-100 text-green-800 border-green-200 dark:bg-green-900/30 dark:text-green-400 dark:border-green-800',
  green: 'bg-green-100 text-green-800 border-green-200 dark:bg-green-900/30 dark:text-green-400 dark:border-green-800',

  // Red variants
  inactive: 'bg-red-100 text-red-800 border-red-200 dark:bg-red-900/30 dark:text-red-400 dark:border-red-800',
  closed: 'bg-red-100 text-red-800 border-red-200 dark:bg-red-900/30 dark:text-red-400 dark:border-red-800',
  red: 'bg-red-100 text-red-800 border-red-200 dark:bg-red-900/30 dark:text-red-400 dark:border-red-800',

  // Amber variants
  draft: 'bg-amber-100 text-amber-800 border-amber-200 dark:bg-amber-900/30 dark:text-amber-400 dark:border-amber-800',
  amber: 'bg-amber-100 text-amber-800 border-amber-200 dark:bg-amber-900/30 dark:text-amber-400 dark:border-amber-800',

  // Blue variants
  distributed: 'bg-blue-100 text-blue-800 border-blue-200 dark:bg-blue-900/30 dark:text-blue-400 dark:border-blue-800',
}

const FALLBACK_STYLE =
  'bg-secondary text-secondary-foreground border-secondary'

/**
 * Visual badge for entity status values.
 * Maps common status strings to semantic colour schemes.
 */
export function StatusBadge({ status, className }: StatusBadgeProps) {
  const key = status.toLowerCase()
  const style = STATUS_STYLES[key] ?? FALLBACK_STYLE

  return (
    <Badge
      variant="outline"
      className={cn('border font-medium', style, className)}
    >
      {status}
    </Badge>
  )
}
