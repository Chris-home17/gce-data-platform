'use client'

import { useEffect, useState } from 'react'
import { Input } from '@/components/ui/input'
import { cn } from '@/lib/utils'
import { formatSecondsAsTime, parseTimeToSeconds } from '@/lib/utils'

export interface TimeInputProps {
  value: number | null | undefined
  onChange: (seconds: number | null) => void
  placeholder?: string
  className?: string
  disabled?: boolean
  hasError?: boolean
}

// Text input that lets the user type a duration as `HH:MM:SS` (or `MM:SS`,
// or plain seconds) while the parent stores total seconds as a number — the
// canonical form for Time-typed KPIs. The input echoes whatever the user
// typed even when it doesn't yet parse, so they aren't fighting the field
// mid-edit; the parsed seconds are emitted via onChange.
export function TimeInput({
  value,
  onChange,
  placeholder = 'HH:MM:SS',
  className,
  disabled,
  hasError,
}: TimeInputProps) {
  const [raw, setRaw] = useState<string>(value != null ? formatSecondsAsTime(value) : '')

  // External value changes (form reset, switching rows) should refresh the
  // displayed text — but only when the current raw doesn't already represent
  // the same number. Otherwise typing fights the controlled value.
  useEffect(() => {
    const currentParsed = parseTimeToSeconds(raw)
    if (currentParsed !== value) {
      setRaw(value != null ? formatSecondsAsTime(value) : '')
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value])

  return (
    <Input
      type="text"
      inputMode="numeric"
      value={raw}
      placeholder={placeholder}
      disabled={disabled}
      onChange={(e) => {
        const next = e.target.value
        setRaw(next)
        if (next.trim() === '') {
          onChange(null)
          return
        }
        const parsed = parseTimeToSeconds(next)
        // Emit even when null so the form's value clears while invalid;
        // the placeholder/format hint signals the expected shape.
        onChange(parsed)
      }}
      onBlur={() => {
        // Snap valid input to canonical HH:MM:SS on blur for consistency.
        const parsed = parseTimeToSeconds(raw)
        if (parsed != null) setRaw(formatSecondsAsTime(parsed))
      }}
      className={cn('font-mono', hasError && 'border-destructive focus-visible:ring-destructive', className)}
    />
  )
}
