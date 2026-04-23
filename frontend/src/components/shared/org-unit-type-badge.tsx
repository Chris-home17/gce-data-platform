import { cn } from '@/lib/utils'

// Single source for the coloured type chip shown next to org-unit rows, shared
// geography rows, and the CSV import preview. Uses `dark:` variants so the
// chips remain legible under both themes — the previous triplicated
// `bg-blue-100` / `text-blue-700` literals stayed light in dark mode.
const TYPE_CLASSES: Record<string, string> = {
  Region:    'bg-blue-100    text-blue-700    border-blue-200    dark:bg-blue-950/40    dark:text-blue-300    dark:border-blue-900/60',
  SubRegion: 'bg-indigo-100  text-indigo-700  border-indigo-200  dark:bg-indigo-950/40  dark:text-indigo-300  dark:border-indigo-900/60',
  Cluster:   'bg-violet-100  text-violet-700  border-violet-200  dark:bg-violet-950/40  dark:text-violet-300  dark:border-violet-900/60',
  Country:   'bg-sky-100     text-sky-700     border-sky-200     dark:bg-sky-950/40     dark:text-sky-300     dark:border-sky-900/60',
  Area:      'bg-teal-100    text-teal-700    border-teal-200    dark:bg-teal-950/40    dark:text-teal-300    dark:border-teal-900/60',
  Branch:    'bg-orange-100  text-orange-700  border-orange-200  dark:bg-orange-950/40  dark:text-orange-300  dark:border-orange-900/60',
  Site:      'bg-emerald-100 text-emerald-700 border-emerald-200 dark:bg-emerald-950/40 dark:text-emerald-300 dark:border-emerald-900/60',
}

const FALLBACK = 'bg-muted text-muted-foreground border-border'

export function OrgUnitTypeBadge({ type }: { type: string }) {
  return (
    <span
      className={cn(
        'inline-flex items-center rounded border px-1.5 py-0.5 text-xs font-medium',
        TYPE_CLASSES[type] ?? FALLBACK,
      )}
    >
      {type}
    </span>
  )
}
