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

/**
 * Time KPIs (DataType === 'Time') store total seconds in the same numeric
 * column used by every other numeric KPI. The UI is responsible for parsing
 * HH:MM:SS strings on input and formatting seconds back on display.
 *
 * Accepted input forms (whitespace ignored, segments are decimal):
 *   "1:30:00"   → 5400        (H:M:S)
 *   "12:30"     → 750         (M:S)
 *   "45"        → 45          (S, plain seconds)
 *   "1.5"       → 1.5         (sub-second decimals are preserved)
 * Returns null if the input cannot be parsed.
 */
export function parseTimeToSeconds(input: string | null | undefined): number | null {
  if (input == null) return null
  const trimmed = String(input).trim()
  if (!trimmed) return null

  const parts = trimmed.split(':').map((p) => p.trim())
  if (parts.length > 3 || parts.some((p) => p === '')) return null

  const nums = parts.map((p) => Number(p))
  if (nums.some((n) => !Number.isFinite(n) || n < 0)) return null
  // The leading segment may exceed the usual ranges (e.g. 99:00:00),
  // but minutes/seconds in non-leading positions must be < 60.
  for (let i = 1; i < nums.length; i++) {
    if (nums[i] >= 60) return null
  }

  if (nums.length === 3) return nums[0] * 3600 + nums[1] * 60 + nums[2]
  if (nums.length === 2) return nums[0] * 60 + nums[1]
  return nums[0]
}

/**
 * Formats a number of seconds as `HH:MM:SS` (or `H:MM:SS` once the hours
 * spill over two digits). Negative or non-finite values render as '—'.
 * Decimals < 1s are rounded to the nearest second for display.
 */
export function formatSecondsAsTime(totalSeconds: number | null | undefined): string {
  if (totalSeconds == null || !Number.isFinite(totalSeconds) || totalSeconds < 0) return '—'
  const whole = Math.round(totalSeconds)
  const h = Math.floor(whole / 3600)
  const m = Math.floor((whole % 3600) / 60)
  const s = whole % 60
  const hh = h < 10 ? `0${h}` : String(h)
  const mm = m < 10 ? `0${m}` : String(m)
  const ss = s < 10 ? `0${s}` : String(s)
  return `${hh}:${mm}:${ss}`
}
