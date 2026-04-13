'use client'

import { useEffect, useId, useMemo, useRef, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Check, Loader2, Search, User as UserIcon } from 'lucide-react'
import { Input } from '@/components/ui/input'
import { api } from '@/lib/api'

interface UserUpnTypeaheadProps {
  value: string
  onChange: (value: string) => void
  disabled?: boolean
  open?: boolean
  placeholder?: string
  excludeUpns?: string[]
}

export function UserUpnTypeahead({
  value,
  onChange,
  disabled,
  open = true,
  placeholder = 'Type a name or email',
  excludeUpns = [],
}: UserUpnTypeaheadProps) {
  const listId = useId()
  const blurTimeoutRef = useRef<number | null>(null)
  const [isFocused, setIsFocused] = useState(false)
  const [highlightedIndex, setHighlightedIndex] = useState(0)
  const normalizedValue = value.trim().toLowerCase()
  const excluded = useMemo(() => new Set(excludeUpns.map((item) => item.toLowerCase())), [excludeUpns])

  const { data, isLoading } = useQuery({
    queryKey: ['users'],
    queryFn: () => api.users.list(),
    enabled: open,
    staleTime: 60_000,
  })

  const matches = useMemo(() => {
    const users = data?.items ?? []

    return users
      .filter((user) => user.isActive)
      .filter((user) => !excluded.has(user.upn.toLowerCase()))
      .filter((user) => {
        if (!normalizedValue) return true
        const displayName = (user.displayName ?? '').toLowerCase()
        const upn = user.upn.toLowerCase()
        return displayName.includes(normalizedValue) || upn.includes(normalizedValue)
      })
      .slice(0, 8)
  }, [data?.items, excluded, normalizedValue])

  useEffect(() => {
    setHighlightedIndex(0)
  }, [normalizedValue])

  useEffect(() => {
    return () => {
      if (blurTimeoutRef.current !== null) {
        window.clearTimeout(blurTimeoutRef.current)
      }
    }
  }, [])

  const hasQuery = normalizedValue.length > 0
  const showDropdown = open && !disabled && isFocused
  const showSuggestions = showDropdown && matches.length > 0
  const showEmptyState = showDropdown && hasQuery && !isLoading && matches.length === 0

  function selectUser(upn: string) {
    onChange(upn)
    setIsFocused(false)
  }

  return (
    <div className="relative">
      <div className="relative">
        <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          value={value}
          onChange={(event) => {
            onChange(event.target.value)
            setIsFocused(true)
          }}
          placeholder={placeholder}
          className="pl-9 pr-9"
          autoComplete="off"
          disabled={disabled}
          onFocus={() => {
            if (blurTimeoutRef.current !== null) {
              window.clearTimeout(blurTimeoutRef.current)
            }
            setIsFocused(true)
          }}
          onBlur={() => {
            blurTimeoutRef.current = window.setTimeout(() => setIsFocused(false), 120)
          }}
          onKeyDown={(event) => {
            if (!showDropdown || matches.length === 0) {
              if (event.key === 'Escape') setIsFocused(false)
              return
            }

            if (event.key === 'ArrowDown') {
              event.preventDefault()
              setHighlightedIndex((current) => (current + 1) % matches.length)
            }

            if (event.key === 'ArrowUp') {
              event.preventDefault()
              setHighlightedIndex((current) => (current - 1 + matches.length) % matches.length)
            }

            if (event.key === 'Enter') {
              event.preventDefault()
              selectUser(matches[highlightedIndex]?.upn ?? matches[0].upn)
            }

            if (event.key === 'Escape') {
              event.preventDefault()
              setIsFocused(false)
            }
          }}
          aria-controls={showDropdown ? listId : undefined}
          aria-expanded={showDropdown}
          aria-autocomplete="list"
          aria-activedescendant={
            showSuggestions ? `${listId}-option-${highlightedIndex}` : undefined
          }
        />
        {isLoading && open ? (
          <Loader2 className="absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 animate-spin text-muted-foreground" />
        ) : null}
      </div>

      {showDropdown ? (
        <div
          id={listId}
          role="listbox"
          className="absolute left-0 right-0 top-full z-50 mt-2 overflow-hidden rounded-md border bg-popover shadow-md"
        >
          {showSuggestions ? (
            <div className="max-h-64 overflow-y-auto py-1">
              {matches.map((user, index) => {
                const selected = user.upn.toLowerCase() === normalizedValue
                const highlighted = index === highlightedIndex

                return (
                  <button
                    key={user.userId}
                    id={`${listId}-option-${index}`}
                    type="button"
                    role="option"
                    aria-selected={selected}
                    className={[
                      'flex w-full items-center justify-between gap-3 px-3 py-2 text-left transition-colors',
                      highlighted ? 'bg-muted' : 'hover:bg-muted/50',
                    ].join(' ')}
                    onMouseDown={(event) => event.preventDefault()}
                    onMouseEnter={() => setHighlightedIndex(index)}
                    onClick={() => selectUser(user.upn)}
                  >
                    <div className="min-w-0">
                      <div className="flex items-center gap-2">
                        <UserIcon className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
                        <span className="truncate text-sm font-medium">
                          {user.displayName || user.upn}
                        </span>
                      </div>
                      <p className="truncate pl-5 text-xs text-muted-foreground">{user.upn}</p>
                    </div>
                    {selected ? <Check className="h-4 w-4 shrink-0 text-primary" /> : null}
                  </button>
                )
              })}
            </div>
          ) : null}

          {showEmptyState ? (
            <div className="px-3 py-3 text-sm text-muted-foreground">
              No matching users found.
            </div>
          ) : null}
        </div>
      ) : null}
    </div>
  )
}
