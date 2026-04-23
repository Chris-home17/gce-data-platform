import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'
import { format, parseISO, isValid } from 'date-fns'

/**
 * Merges Tailwind CSS class names, resolving conflicts correctly.
 */
export function cn(...inputs: ClassValue[]): string {
  return twMerge(clsx(inputs))
}

/**
 * Formats an ISO 8601 date string into a human-readable date.
 * Returns an empty string if the input is null, undefined, or invalid.
 */
export function formatDate(iso: string | null | undefined): string {
  if (!iso) return ''
  try {
    const date = parseISO(iso)
    if (!isValid(date)) return ''
    return format(date, 'dd MMM yyyy')
  } catch {
    return ''
  }
}

/**
 * Formats an ISO 8601 datetime string into a human-readable datetime.
 */
export function formatDateTime(iso: string | null | undefined): string {
  if (!iso) return ''
  try {
    const date = parseISO(iso)
    if (!isValid(date)) return ''
    return format(date, 'dd MMM yyyy HH:mm')
  } catch {
    return ''
  }
}

/**
 * Formats a decimal number as a percentage string with one decimal place.
 * Expects a value between 0 and 100 (not 0–1).
 */
export function formatPercent(n: number): string {
  return `${n.toFixed(1)}%`
}
