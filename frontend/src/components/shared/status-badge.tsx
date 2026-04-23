import { Badge } from '@/components/ui/badge'
import { cn } from '@/lib/utils'

type StatusValue =
  | 'Active'
  | 'Inactive'
  | 'Open'
  | 'Closed'
  | 'Draft'
  | 'Distributed'
  | 'Locked'
  | 'Green'
  | 'Amber'
  | 'Red'
  | (string & {}) // allow arbitrary strings with a graceful fallback

interface StatusBadgeProps {
  status: StatusValue
  className?: string
}

const SUCCESS = 'bg-success-muted text-success-muted-foreground border-success-border'
const DANGER = 'bg-danger-muted text-danger-muted-foreground border-danger-border'
const WARNING = 'bg-warning-muted text-warning-muted-foreground border-warning-border'
const INFO = 'bg-info-muted text-info-muted-foreground border-info-border'

const STATUS_STYLES: Record<string, string> = {
  // Green variants
  active: SUCCESS,
  open: SUCCESS,
  green: SUCCESS,

  // Red variants
  inactive: DANGER,
  closed: DANGER,
  red: DANGER,

  // Amber variants
  draft: WARNING,
  amber: WARNING,
  locked: WARNING,

  // Blue variants
  distributed: INFO,
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
