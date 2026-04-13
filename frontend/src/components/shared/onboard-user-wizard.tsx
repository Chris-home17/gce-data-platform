'use client'

import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { Check, ChevronRight, Loader2, UserPlus, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Badge } from '@/components/ui/badge'
import { cn } from '@/lib/utils'
import { api } from '@/lib/api'
import type { Role, Package } from '@/types/api'

// ---------------------------------------------------------------------------
// Step indicator
// ---------------------------------------------------------------------------

const STEPS = ['User', 'Roles', 'Access', 'Packages', 'Review']

function StepIndicator({ current }: { current: number }) {
  return (
    <div className="flex items-center gap-1.5">
      {STEPS.map((label, i) => {
        const done = i < current
        const active = i === current
        return (
          <div key={label} className="flex items-center gap-1.5">
            {i > 0 && (
              <ChevronRight className="h-3 w-3 shrink-0 text-muted-foreground/40" />
            )}
            <div className="flex items-center gap-1.5">
              <div
                className={cn(
                  'flex h-5 w-5 shrink-0 items-center justify-center rounded-full text-[10px] font-semibold',
                  done
                    ? 'bg-primary text-primary-foreground'
                    : active
                    ? 'border-2 border-primary text-primary'
                    : 'border border-muted-foreground/30 text-muted-foreground/50'
                )}
              >
                {done ? <Check className="h-2.5 w-2.5" /> : i + 1}
              </div>
              <span
                className={cn(
                  'hidden text-xs sm:block',
                  active ? 'font-medium text-foreground' : done ? 'text-muted-foreground' : 'text-muted-foreground/50'
                )}
              >
                {label}
              </span>
            </div>
          </div>
        )
      })}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Wizard state
// ---------------------------------------------------------------------------

interface WizardState {
  upn: string
  displayName: string
  userId: number | null
  selectedRoles: Role[]
  grantType: 'NONE' | 'FULL_ACCOUNT' | 'GLOBAL_ALL'
  accountCode: string
  selectedPackages: Package[]
  grantAllPackages: boolean
}

const INITIAL_STATE: WizardState = {
  upn: '',
  displayName: '',
  userId: null,
  selectedRoles: [],
  grantType: 'NONE',
  accountCode: '',
  selectedPackages: [],
  grantAllPackages: false,
}

// ---------------------------------------------------------------------------
// Step 1 — User
// ---------------------------------------------------------------------------

function StepUser({
  state,
  onChange,
}: {
  state: WizardState
  onChange: (patch: Partial<WizardState>) => void
}) {
  return (
    <div className="space-y-4">
      <p className="text-sm text-muted-foreground">
        Enter the user&apos;s UPN (email address). If they don&apos;t exist yet, they&apos;ll be created.
      </p>
      <div className="space-y-2">
        <Label htmlFor="upn">UPN / Email *</Label>
        <Input
          id="upn"
          placeholder="user@organisation.com"
          autoComplete="off"
          value={state.upn}
          onChange={(e) => onChange({ upn: e.target.value })}
        />
      </div>
      <div className="space-y-2">
        <Label htmlFor="displayName">
          Display Name <span className="text-muted-foreground font-normal">(optional)</span>
        </Label>
        <Input
          id="displayName"
          placeholder="Jane Smith"
          value={state.displayName}
          onChange={(e) => onChange({ displayName: e.target.value })}
        />
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Step 2 — Roles
// ---------------------------------------------------------------------------

function StepRoles({
  state,
  onChange,
  accountId,
}: {
  state: WizardState
  onChange: (patch: Partial<WizardState>) => void
  accountId?: number
}) {
  const [search, setSearch] = useState('')
  const { data, isLoading } = useQuery({
    queryKey: ['roles', accountId ? { accountId } : 'all'],
    queryFn: () => api.roles.list(accountId ? { accountId } : undefined),
  })

  const allRoles = data?.items.filter((r) => r.isActive) ?? []
  // When launched from an account, show account-specific roles first, then global roles
  const roles = accountId
    ? [
        ...allRoles.filter((r) => r.accountId === accountId),
        ...allRoles.filter((r) => r.accountId === null),
      ]
    : allRoles

  const filtered = search.trim()
    ? roles.filter(
        (r) =>
          r.roleName.toLowerCase().includes(search.toLowerCase()) ||
          r.roleCode.toLowerCase().includes(search.toLowerCase())
      )
    : roles

  function toggle(role: Role) {
    const exists = state.selectedRoles.some((r) => r.roleId === role.roleId)
    onChange({
      selectedRoles: exists
        ? state.selectedRoles.filter((r) => r.roleId !== role.roleId)
        : [...state.selectedRoles, role],
    })
  }

  return (
    <div className="space-y-3">
      <p className="text-sm text-muted-foreground">
        Select roles to assign. You can skip this step and assign roles later.
      </p>
      {!isLoading && roles.length > 0 && (
        <Input
          placeholder="Search by name or code…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          autoFocus
        />
      )}
      {isLoading ? (
        <div className="space-y-2">
          {[1, 2, 3].map((i) => (
            <div key={i} className="h-12 animate-pulse rounded-lg bg-muted" />
          ))}
        </div>
      ) : roles.length === 0 ? (
        <p className="text-center text-sm text-muted-foreground py-6">No active roles found</p>
      ) : filtered.length === 0 ? (
        <p className="text-center text-sm text-muted-foreground py-6">No roles match &quot;{search}&quot;</p>
      ) : (
        <div className="max-h-52 space-y-1.5 overflow-y-auto rounded-lg border p-1.5">
          {filtered.map((role) => {
            const selected = state.selectedRoles.some((r) => r.roleId === role.roleId)
            const isGlobal = role.accountId === null
            return (
              <button
                key={role.roleId}
                onClick={() => toggle(role)}
                className={cn(
                  'flex min-w-0 w-full items-center justify-between rounded-md px-3 py-2.5 text-left text-sm transition-colors',
                  selected
                    ? 'bg-primary/10 text-primary border border-primary/40'
                    : 'border border-transparent hover:bg-muted'
                )}
              >
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-1.5">
                    <span className="font-medium truncate">{role.roleName}</span>
                    <Badge
                      variant="outline"
                      className={cn(
                        'text-[10px] px-1 py-0 shrink-0',
                        isGlobal
                          ? 'border-violet-300 text-violet-600 dark:border-violet-700 dark:text-violet-400'
                          : 'border-blue-300 text-blue-600 dark:border-blue-700 dark:text-blue-400'
                      )}
                    >
                      {isGlobal ? 'Global' : 'Account'}
                    </Badge>
                  </div>
                  <span className="block font-mono text-xs text-muted-foreground truncate">{role.roleCode}</span>
                </div>
                {selected && <Check className="ml-2 h-4 w-4 shrink-0 text-primary" />}
              </button>
            )
          })}
        </div>
      )}
      {state.selectedRoles.length > 0 && (
        <p className="text-xs text-muted-foreground">
          {state.selectedRoles.length} role{state.selectedRoles.length !== 1 ? 's' : ''} selected
        </p>
      )}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Step 3 — Access
// ---------------------------------------------------------------------------

function StepAccess({
  state,
  onChange,
}: {
  state: WizardState
  onChange: (patch: Partial<WizardState>) => void
}) {
  const { data, isLoading } = useQuery({
    queryKey: ['accounts'],
    queryFn: () => api.accounts.list(),
  })

  const accounts = data?.items.filter((a) => a.isActive) ?? []

  return (
    <div className="space-y-4">
      <p className="text-sm text-muted-foreground">
        Choose the access scope for this user. You can skip and configure access later.
      </p>

      <div className="space-y-2">
        <Label>Access level</Label>
        <div className="grid gap-2">
          {([
            ['NONE', 'No access grant', 'Skip — configure later'],
            ['FULL_ACCOUNT', 'Full account', 'Access to all sites in a specific account'],
            ['GLOBAL_ALL', 'Global all', 'Access to all accounts and all packages'],
          ] as const).map(([value, label, desc]) => (
            <button
              key={value}
              onClick={() => onChange({ grantType: value })}
              className={cn(
                'flex w-full items-start gap-3 rounded-lg border p-3 text-left text-sm transition-colors',
                state.grantType === value
                  ? 'border-primary/50 bg-primary/5 ring-1 ring-primary/30'
                  : 'hover:bg-muted/50'
              )}
            >
              <div
                className={cn(
                  'mt-0.5 h-4 w-4 shrink-0 rounded-full border-2',
                  state.grantType === value ? 'border-primary bg-primary' : 'border-muted-foreground/40'
                )}
              />
              <div>
                <span className="font-medium">{label}</span>
                <p className="text-xs text-muted-foreground">{desc}</p>
              </div>
            </button>
          ))}
        </div>
      </div>

      {state.grantType === 'FULL_ACCOUNT' && (
        <div className="space-y-2">
          <Label>Account *</Label>
          {isLoading ? (
            <div className="h-9 animate-pulse rounded-md bg-muted" />
          ) : (
            <div className="max-h-48 overflow-y-auto rounded-lg border p-2 space-y-1">
              {accounts.map((account) => (
                <button
                  key={account.accountId}
                  onClick={() => onChange({ accountCode: account.accountCode })}
                  className={cn(
                    'flex w-full items-center justify-between rounded-md px-3 py-2 text-left text-sm',
                    state.accountCode === account.accountCode
                      ? 'bg-primary/10 text-primary ring-1 ring-primary/30'
                      : 'hover:bg-muted'
                  )}
                >
                  <div>
                    <span className="font-medium">{account.accountName}</span>
                    <span className="ml-2 font-mono text-xs text-muted-foreground">{account.accountCode}</span>
                  </div>
                  {state.accountCode === account.accountCode && (
                    <Check className="h-4 w-4 shrink-0 text-primary" />
                  )}
                </button>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Step 4 — Packages
// ---------------------------------------------------------------------------

function StepPackages({
  state,
  onChange,
}: {
  state: WizardState
  onChange: (patch: Partial<WizardState>) => void
}) {
  const { data, isLoading } = useQuery({
    queryKey: ['packages'],
    queryFn: () => api.packages.list(),
  })

  const packages = data?.items.filter((p) => p.isActive) ?? []

  function toggle(pkg: Package) {
    const exists = state.selectedPackages.some((p) => p.packageId === pkg.packageId)
    onChange({
      selectedPackages: exists
        ? state.selectedPackages.filter((p) => p.packageId !== pkg.packageId)
        : [...state.selectedPackages, pkg],
      grantAllPackages: false,
    })
  }

  return (
    <div className="space-y-3">
      <p className="text-sm text-muted-foreground">
        Grant access to BI packages. Optional — you can configure this later.
      </p>

      <button
        onClick={() => onChange({ grantAllPackages: !state.grantAllPackages, selectedPackages: [] })}
        className={cn(
          'flex w-full items-center gap-3 rounded-lg border p-3 text-left text-sm transition-colors',
          state.grantAllPackages
            ? 'border-primary/50 bg-primary/5 ring-1 ring-primary/30'
            : 'hover:bg-muted/50'
        )}
      >
        <div
          className={cn(
            'h-4 w-4 shrink-0 rounded border-2',
            state.grantAllPackages ? 'border-primary bg-primary' : 'border-muted-foreground/40'
          )}
        >
          {state.grantAllPackages && <Check className="h-3 w-3 text-white" />}
        </div>
        <div>
          <span className="font-medium">All packages</span>
          <p className="text-xs text-muted-foreground">Grant access to every active package</p>
        </div>
      </button>

      {!state.grantAllPackages && (
        <>
          {isLoading ? (
            <div className="space-y-2">
              {[1, 2, 3].map((i) => (
                <div key={i} className="h-11 animate-pulse rounded-lg bg-muted" />
              ))}
            </div>
          ) : packages.length === 0 ? (
            <p className="text-center text-sm text-muted-foreground py-4">No active packages found</p>
          ) : (
            <div className="max-h-56 space-y-1.5 overflow-y-auto rounded-lg border p-1.5">
              {packages.map((pkg) => {
                const selected = state.selectedPackages.some((p) => p.packageId === pkg.packageId)
                return (
                  <button
                    key={pkg.packageId}
                    onClick={() => toggle(pkg)}
                    className={cn(
                      'flex min-w-0 w-full items-center justify-between rounded-md px-3 py-2.5 text-left text-sm transition-colors',
                      selected
                        ? 'bg-primary/10 text-primary ring-1 ring-primary/30'
                        : 'hover:bg-muted'
                    )}
                  >
                    <div className="min-w-0 flex-1">
                      <span className="block font-medium truncate">{pkg.packageName}</span>
                      <span className="block font-mono text-xs text-muted-foreground truncate">{pkg.packageCode}</span>
                    </div>
                    {selected && <Check className="ml-2 h-4 w-4 shrink-0 text-primary" />}
                  </button>
                )
              })}
            </div>
          )}
          {state.selectedPackages.length > 0 && (
            <p className="text-xs text-muted-foreground">
              {state.selectedPackages.length} package{state.selectedPackages.length !== 1 ? 's' : ''} selected
            </p>
          )}
        </>
      )}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Step 5 — Review
// ---------------------------------------------------------------------------

function StepReview({ state }: { state: WizardState }) {
  return (
    <div className="space-y-4">
      <p className="text-sm text-muted-foreground">
        Review and confirm. All steps below will be executed in order.
      </p>

      <div className="space-y-2">
        {/* User */}
        <div className="rounded-lg border p-3">
          <div className="flex items-center gap-2 text-sm font-medium mb-1">
            <div className="h-5 w-5 rounded-full bg-primary/10 text-primary flex items-center justify-center text-xs font-bold">1</div>
            Create / find user
          </div>
          <div className="ml-7 text-sm text-muted-foreground">
            <span className="font-mono">{state.upn}</span>
            {state.displayName && <span> · {state.displayName}</span>}
          </div>
        </div>

        {/* Roles */}
        <div className="rounded-lg border p-3">
          <div className="flex items-center gap-2 text-sm font-medium mb-1">
            <div className="h-5 w-5 rounded-full bg-primary/10 text-primary flex items-center justify-center text-xs font-bold">2</div>
            Assign roles
          </div>
          <div className="ml-7 flex flex-wrap gap-1.5">
            {state.selectedRoles.length === 0 ? (
              <span className="text-xs text-muted-foreground">None — skip</span>
            ) : (
              state.selectedRoles.map((r) => {
                const isGlobal = r.accountId === null
                return (
                  <div key={r.roleId} className="flex items-center gap-1">
                    <Badge variant="secondary" className="text-xs font-mono">{r.roleCode}</Badge>
                    <Badge
                      variant="outline"
                      className={cn(
                        'text-[10px] px-1 py-0',
                        isGlobal
                          ? 'border-violet-300 text-violet-600 dark:border-violet-700 dark:text-violet-400'
                          : 'border-blue-300 text-blue-600 dark:border-blue-700 dark:text-blue-400'
                      )}
                    >
                      {isGlobal ? 'Global' : 'Account'}
                    </Badge>
                  </div>
                )
              })
            )}
          </div>
        </div>

        {/* Access */}
        <div className="rounded-lg border p-3">
          <div className="flex items-center gap-2 text-sm font-medium mb-1">
            <div className="h-5 w-5 rounded-full bg-primary/10 text-primary flex items-center justify-center text-xs font-bold">3</div>
            Grant access
          </div>
          <div className="ml-7 text-sm text-muted-foreground">
            {state.grantType === 'NONE' && <span>None — skip</span>}
            {state.grantType === 'GLOBAL_ALL' && <span>Global all accounts</span>}
            {state.grantType === 'FULL_ACCOUNT' && (
              <span>
                Full account:{' '}
                <span className="font-mono font-medium text-foreground">{state.accountCode}</span>
              </span>
            )}
          </div>
        </div>

        {/* Packages */}
        <div className="rounded-lg border p-3">
          <div className="flex items-center gap-2 text-sm font-medium mb-1">
            <div className="h-5 w-5 rounded-full bg-primary/10 text-primary flex items-center justify-center text-xs font-bold">4</div>
            Package access
          </div>
          <div className="ml-7 flex flex-wrap gap-1.5">
            {!state.grantAllPackages && state.selectedPackages.length === 0 ? (
              <span className="text-xs text-muted-foreground">None — skip</span>
            ) : state.grantAllPackages ? (
              <Badge variant="secondary" className="text-xs">All packages</Badge>
            ) : (
              state.selectedPackages.map((p) => (
                <Badge key={p.packageId} variant="secondary" className="text-xs font-mono">
                  {p.packageCode}
                </Badge>
              ))
            )}
          </div>
        </div>
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Main wizard
// ---------------------------------------------------------------------------

interface OnboardUserWizardProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  accountId?: number
}

export function OnboardUserWizard({ open, onOpenChange, accountId }: OnboardUserWizardProps) {
  const queryClient = useQueryClient()
  const [step, setStep] = useState(0)
  const [state, setState] = useState<WizardState>(INITIAL_STATE)
  const [error, setError] = useState<string | null>(null)
  const [done, setDone] = useState(false)

  function patch(update: Partial<WizardState>) {
    setState((prev) => ({ ...prev, ...update }))
  }

  function reset() {
    setStep(0)
    setState(INITIAL_STATE)
    setError(null)
    setDone(false)
  }

  function handleClose() {
    onOpenChange(false)
    setTimeout(reset, 300)
  }

  const commitMutation = useMutation({
    mutationFn: async () => {
      // Step 1: create user (idempotent — will 409 if exists, which is fine)
      let userId = state.userId
      try {
        const user = await api.users.create({
          upn: state.upn,
          displayName: state.displayName || undefined,
        })
        userId = user.userId
      } catch {
        // User may already exist — fetch them
        const users = await api.users.list()
        const existing = users.items.find(
          (u) => u.upn.toLowerCase() === state.upn.toLowerCase()
        )
        if (!existing) throw new Error(`User ${state.upn} could not be created or found.`)
        userId = existing.userId
      }

      // Step 2: assign roles
      for (const role of state.selectedRoles) {
        await api.roles.addMember(role.roleId, state.upn)
      }

      // Step 3: access grant
      if (state.grantType === 'GLOBAL_ALL') {
        await api.grants.grant({
          principalType: 'USER',
          principalIdentifier: state.upn,
          grantType: 'GLOBAL_ALL',
        })
      } else if (state.grantType === 'FULL_ACCOUNT' && state.accountCode) {
        await api.grants.grant({
          principalType: 'USER',
          principalIdentifier: state.upn,
          grantType: 'FULL_ACCOUNT',
          accountCode: state.accountCode,
        })
      }

      // Step 4: package grants
      if (state.grantAllPackages) {
        await api.grants.grant({
          principalType: 'USER',
          principalIdentifier: state.upn,
          grantType: 'GLOBAL_PACKAGE',
        })
      } else {
        for (const pkg of state.selectedPackages) {
          await api.grants.grant({
            principalType: 'USER',
            principalIdentifier: state.upn,
            grantType: 'GLOBAL_PACKAGE',
            packageCode: pkg.packageCode,
          })
        }
      }

      return userId
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['users'] })
      queryClient.invalidateQueries({ queryKey: ['accounts'] })
      queryClient.invalidateQueries({ queryKey: ['roles'] })
      queryClient.invalidateQueries({ queryKey: ['org-units'] })
      queryClient.invalidateQueries({ queryKey: ['delegations'] })
      queryClient.invalidateQueries({ queryKey: ['coverage'] })
      setDone(true)
      setError(null)
    },
    onError: (err) => {
      setError(err instanceof Error ? err.message : 'Something went wrong.')
    },
  })

  function canProceed(): boolean {
    if (step === 0) return state.upn.trim().length > 0 && state.upn.includes('@')
    if (step === 3) {
      if (state.grantType === 'FULL_ACCOUNT' && !state.accountCode) return false
    }
    return true
  }

  const isLast = step === STEPS.length - 1

  return (
    <Dialog open={open} onOpenChange={handleClose}>
      <DialogContent className="w-[calc(100vw-2rem)] sm:max-w-2xl">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <UserPlus className="h-5 w-5" />
            Onboard User
          </DialogTitle>
        </DialogHeader>

        {done ? (
          <div className="space-y-4 py-2">
            <div className="flex flex-col items-center gap-3 py-6 text-center">
              <div className="flex h-12 w-12 items-center justify-center rounded-full bg-emerald-100 text-emerald-600">
                <Check className="h-6 w-6" />
              </div>
              <div>
                <p className="font-semibold">User onboarded successfully</p>
                <p className="mt-1 text-sm text-muted-foreground font-mono">{state.upn}</p>
              </div>
            </div>
            <div className="flex justify-end gap-2">
              <Button variant="outline" onClick={() => { reset(); }}>
                Onboard another
              </Button>
              <Button onClick={handleClose}>Done</Button>
            </div>
          </div>
        ) : (
          <div className="space-y-5">
            <StepIndicator current={step} />

            <div className="min-h-[260px] w-full">
              {step === 0 && <StepUser state={state} onChange={patch} />}
              {step === 1 && <StepRoles state={state} onChange={patch} accountId={accountId} />}
              {step === 2 && <StepAccess state={state} onChange={patch} />}
              {step === 3 && <StepPackages state={state} onChange={patch} />}
              {step === 4 && <StepReview state={state} />}
            </div>

            {error && (
              <p className="rounded-md bg-destructive/10 px-3 py-2 text-sm text-destructive">
                {error}
              </p>
            )}

            <div className="flex items-center justify-between border-t pt-4">
              <Button
                variant="ghost"
                size="sm"
                onClick={() => step === 0 ? handleClose() : setStep(s => s - 1)}
                disabled={commitMutation.isPending}
              >
                {step === 0 ? (
                  <>
                    <X className="mr-1.5 h-4 w-4" />
                    Cancel
                  </>
                ) : (
                  'Back'
                )}
              </Button>

              <div className="flex items-center gap-2">
                {!isLast && step > 0 && (
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => setStep(s => s + 1)}
                    disabled={commitMutation.isPending}
                  >
                    Skip
                  </Button>
                )}
                <Button
                  size="sm"
                  onClick={() => isLast ? commitMutation.mutate() : setStep(s => s + 1)}
                  disabled={!canProceed() || commitMutation.isPending}
                >
                  {commitMutation.isPending ? (
                    <>
                      <Loader2 className="mr-1.5 h-4 w-4 animate-spin" />
                      Processing…
                    </>
                  ) : isLast ? (
                    'Confirm & Onboard'
                  ) : (
                    'Next'
                  )}
                </Button>
              </div>
            </div>
          </div>
        )}
      </DialogContent>
    </Dialog>
  )
}
