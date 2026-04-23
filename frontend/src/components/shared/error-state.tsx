interface ErrorStateProps {
  title: string
  error?: unknown
}

// Consistent destructive-bordered error block used by every list page when a
// TanStack Query returns isError. Keep it minimal: a headline plus the error
// message (or a generic fallback). Inline the block via this component rather
// than copy-pasting the Tailwind class triad.
export function ErrorState({ title, error }: ErrorStateProps) {
  const message = error instanceof Error ? error.message : 'An unexpected error occurred.'
  return (
    <div className="rounded-md border border-destructive/40 bg-destructive/5 p-6 text-center">
      <p className="text-sm font-medium text-destructive">{title}</p>
      <p className="mt-1 text-xs text-muted-foreground">{message}</p>
    </div>
  )
}
