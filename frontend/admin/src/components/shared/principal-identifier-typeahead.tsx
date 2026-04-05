'use client'

import { useEffect, useId, useMemo, useRef, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Check, Loader2, Search, Shield, User as UserIcon } from 'lucide-react'
import { Input } from '@/components/ui/input'
import { api } from '@/lib/api'

interface PrincipalIdentifierTypeaheadProps {
  principalType: 'USER' | 'ROLE'
  value: string
  onChange: (value: string) => void
  disabled?: boolean
  open?: boolean
}

export function PrincipalIdentifierTypeahead({
  principalType,
  value,
  onChange,
  disabled,
  open = true,
}: PrincipalIdentifierTypeaheadProps) {
  const listId = useId()
  const blurTimeoutRef = useRef<number | null>(null)
  const [isFocused, setIsFocused] = useState(false)
  const [highlightedIndex, setHighlightedIndex] = useState(0)
  const normalizedValue = value.trim().toLowerCase()

  const usersQuery = useQuery({
    queryKey: ['users'],
    queryFn: () => api.users.list(),
    enabled: open && principalType === 'USER',
    staleTime: 60_000,
  })

  const rolesQuery = useQuery({
    queryKey: ['roles'],
    queryFn: () => api.roles.list(),
    enabled: open && principalType === 'ROLE',
    staleTime: 60_000,
  })

  const options = useMemo(() => {
    if (principalType === 'USER') {
      return (usersQuery.data?.items ?? [])
        .filter((user) => user.isActive)
        .filter((user) => {
          if (!normalizedValue) return true
          return (
            user.upn.toLowerCase().includes(normalizedValue) ||
            (user.displayName ?? '').toLowerCase().includes(normalizedValue)
          )
        })
        .slice(0, 8)
        .map((user) => ({
          id: `user-${user.userId}`,
          value: user.upn,
          label: user.displayName || user.upn,
          hint: user.upn,
        }))
    }

    return (rolesQuery.data?.items ?? [])
      .filter((role) => role.isActive)
      .filter((role) => {
        if (!normalizedValue) return true
        return (
          role.roleCode.toLowerCase().includes(normalizedValue) ||
          role.roleName.toLowerCase().includes(normalizedValue)
        )
      })
      .slice(0, 8)
      .map((role) => ({
        id: `role-${role.roleId}`,
        value: role.roleCode,
        label: role.roleName,
        hint: role.roleCode,
      }))
  }, [normalizedValue, principalType, rolesQuery.data?.items, usersQuery.data?.items])

  const isLoading = principalType === 'USER' ? usersQuery.isLoading : rolesQuery.isLoading

  useEffect(() => {
    setHighlightedIndex(0)
  }, [normalizedValue, principalType])

  useEffect(() => {
    return () => {
      if (blurTimeoutRef.current !== null) {
        window.clearTimeout(blurTimeoutRef.current)
      }
    }
  }, [])

  const hasQuery = normalizedValue.length > 0
  const showDropdown = open && !disabled && isFocused
  const showSuggestions = showDropdown && options.length > 0
  const showEmptyState = showDropdown && hasQuery && !isLoading && options.length === 0
  const SelectedIcon = principalType === 'USER' ? UserIcon : Shield

  function selectValue(selectedValue: string) {
    onChange(selectedValue)
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
            if (!showDropdown || options.length === 0) {
              if (event.key === 'Escape') setIsFocused(false)
              return
            }

            if (event.key === 'ArrowDown') {
              event.preventDefault()
              setHighlightedIndex((current) => (current + 1) % options.length)
            }

            if (event.key === 'ArrowUp') {
              event.preventDefault()
              setHighlightedIndex((current) => (current - 1 + options.length) % options.length)
            }

            if (event.key === 'Enter') {
              event.preventDefault()
              selectValue(options[highlightedIndex]?.value ?? options[0].value)
            }

            if (event.key === 'Escape') {
              event.preventDefault()
              setIsFocused(false)
            }
          }}
          placeholder={principalType === 'USER' ? 'Type a name or email' : 'Type a role name or code'}
          className="pl-9 pr-9"
          autoComplete="off"
          disabled={disabled}
          aria-controls={showDropdown ? listId : undefined}
          aria-expanded={showDropdown}
          aria-autocomplete="list"
          aria-activedescendant={showSuggestions ? `${listId}-option-${highlightedIndex}` : undefined}
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
              {options.map((option, index) => {
                const selected = option.value.toLowerCase() === normalizedValue
                const highlighted = index === highlightedIndex

                return (
                  <button
                    key={option.id}
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
                    onClick={() => selectValue(option.value)}
                  >
                    <div className="min-w-0">
                      <div className="flex items-center gap-2">
                        <SelectedIcon className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
                        <span className="truncate text-sm font-medium">{option.label}</span>
                      </div>
                      <p className="truncate pl-5 text-xs text-muted-foreground">{option.hint}</p>
                    </div>
                    {selected ? <Check className="h-4 w-4 shrink-0 text-primary" /> : null}
                  </button>
                )
              })}
            </div>
          ) : null}

          {showEmptyState ? (
            <div className="px-3 py-3 text-sm text-muted-foreground">
              {principalType === 'USER' ? 'No matching users found.' : 'No matching roles found.'}
            </div>
          ) : null}
        </div>
      ) : null}
    </div>
  )
}
