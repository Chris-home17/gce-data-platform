'use client'

/**
 * AccountContext
 *
 * Holds the user's currently selected account. The selection is persisted to
 * localStorage so it survives page refreshes.
 *
 * On first load (or if the stored account no longer exists in the list) the
 * context auto-selects the first active account.
 */

import {
  createContext,
  useContext,
  useState,
  useEffect,
  useCallback,
  type ReactNode,
} from 'react'
import { useQuery } from '@tanstack/react-query'
import { api } from '@/lib/api'
import type { Account } from '@/types/api'

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface AccountContextValue {
  /** All accounts the current user can see */
  accounts: Account[]
  /** The currently selected account (undefined while loading) */
  selectedAccount: Account | undefined
  /** True while the initial accounts list is fetching */
  isLoading: boolean
  /** Switch to a different account */
  selectAccount: (accountId: number) => void
}

// ---------------------------------------------------------------------------
// Context
// ---------------------------------------------------------------------------

const STORAGE_KEY = 'gce:selectedAccountId'

const AccountContext = createContext<AccountContextValue>({
  accounts: [],
  selectedAccount: undefined,
  isLoading: true,
  selectAccount: () => undefined,
})

export function AccountProvider({ children }: { children: ReactNode }) {
  const { data, isLoading } = useQuery({
    queryKey: ['accounts'],
    queryFn: () => api.accounts.list(),
  })

  const accounts = data?.items ?? []

  const [selectedId, setSelectedId] = useState<number | null>(() => {
    if (typeof window === 'undefined') return null
    const stored = localStorage.getItem(STORAGE_KEY)
    return stored ? parseInt(stored, 10) : null
  })

  // When accounts load, validate / auto-select
  useEffect(() => {
    if (accounts.length === 0) return

    const activeAccounts = accounts.filter((a) => a.isActive)
    if (activeAccounts.length === 0) return

    // If stored ID is valid, keep it
    if (selectedId && activeAccounts.some((a) => a.accountId === selectedId)) return

    // Otherwise fall back to the first active account
    const fallback = activeAccounts[0].accountId
    setSelectedId(fallback)
    localStorage.setItem(STORAGE_KEY, String(fallback))
  }, [accounts, selectedId])

  const selectAccount = useCallback((accountId: number) => {
    setSelectedId(accountId)
    localStorage.setItem(STORAGE_KEY, String(accountId))
  }, [])

  const selectedAccount = accounts.find((a) => a.accountId === selectedId)

  return (
    <AccountContext.Provider
      value={{ accounts, selectedAccount, isLoading, selectAccount }}
    >
      {children}
    </AccountContext.Provider>
  )
}

export function useAccount() {
  return useContext(AccountContext)
}
