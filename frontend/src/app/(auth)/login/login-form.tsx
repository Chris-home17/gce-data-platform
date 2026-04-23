'use client'

import { useState } from 'react'
import { signIn } from 'next-auth/react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Loader2 } from 'lucide-react'

const DEV_BYPASS = process.env.NEXT_PUBLIC_DEV_BYPASS === 'true'

export function LoginForm() {
  const [isLoading, setIsLoading] = useState(false)
  const [devName, setDevName] = useState('Dev User')

  async function handleSignIn() {
    setIsLoading(true)
    try {
      if (DEV_BYPASS) {
        await signIn('credentials', { name: devName, callbackUrl: '/accounts' })
      } else {
        await signIn('microsoft-entra-id', { callbackUrl: '/accounts' })
      }
    } finally {
      setIsLoading(false)
    }
  }

  if (DEV_BYPASS) {
    return (
      <div className="space-y-3">
        <div className="rounded-md border border-warning-border bg-warning-muted px-3 py-2 text-xs text-warning-muted-foreground">
          Dev bypass active — no Azure AD credentials required.
        </div>
        <Input
          value={devName}
          onChange={(e) => setDevName(e.target.value)}
          placeholder="Display name"
          disabled={isLoading}
        />
        <Button className="w-full" size="lg" onClick={handleSignIn} disabled={isLoading || !devName.trim()}>
          {isLoading && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
          {isLoading ? 'Signing in…' : 'Continue as Dev User'}
        </Button>
      </div>
    )
  }

  return (
    <Button className="w-full gap-2" size="lg" onClick={handleSignIn} disabled={isLoading}>
      {isLoading ? (
        <Loader2 className="h-4 w-4 animate-spin" />
      ) : (
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 23 23" className="h-4 w-4 shrink-0" aria-hidden="true">
          <path fill="#f3f3f3" d="M0 0h23v23H0z" />
          <path fill="#f35325" d="M1 1h10v10H1z" />
          <path fill="#81bc06" d="M12 1h10v10H12z" />
          <path fill="#05a6f0" d="M1 12h10v10H1z" />
          <path fill="#ffba08" d="M12 12h10v10H12z" />
        </svg>
      )}
      {isLoading ? 'Redirecting…' : 'Sign in with Microsoft'}
    </Button>
  )
}
