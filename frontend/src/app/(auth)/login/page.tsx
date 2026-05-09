import type { Metadata } from 'next'
import { LoginForm } from './login-form'
import { Logo } from '@/components/brand/logo'

export const metadata: Metadata = {
  title: 'Sign In',
}

export default function LoginPage() {
  return (
    <div className="flex min-h-screen items-center justify-center bg-muted/40">
      <div className="w-full max-w-sm space-y-8 px-4">
        {/* Logo / wordmark */}
        <div className="flex flex-col items-center gap-4">
          <Logo size="lg" />
          <div className="text-center">
            <h1 className="text-2xl font-semibold tracking-tight">GCE Data Platform</h1>
            <p className="text-sm text-muted-foreground">Administration Portal</p>
          </div>
        </div>

        {/* Sign-in card */}
        <div className="rounded-xl border bg-card p-8 shadow-sm">
          <div className="mb-6 space-y-1">
            <h2 className="text-lg font-medium">Sign in to continue</h2>
            <p className="text-sm text-muted-foreground">
              Use your GCE Microsoft account to access the admin portal.
            </p>
          </div>
          <LoginForm />
        </div>

        <p className="text-center text-xs text-muted-foreground">
          Access is restricted to authorised GCE administrators.
        </p>
      </div>
    </div>
  )
}
