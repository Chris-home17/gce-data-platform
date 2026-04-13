/**
 * Next.js middleware — enforces authentication on all admin routes.
 *
 * When NEXT_PUBLIC_DEV_BYPASS=true the middleware is a pass-through so the
 * app can be explored locally without Azure AD credentials. Auth.ts uses a
 * Credentials provider in that mode, so the login page still creates a real
 * NextAuth session — the bypass just skips the forced redirect so you land
 * directly on the login page rather than being bounced.
 *
 * In production (DEV_BYPASS unset / false) the next-auth `auth` guard is
 * used — unauthenticated requests to protected routes redirect to /login.
 */

import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'
import { auth } from '@/lib/auth'

export function middleware(request: NextRequest) {
  if (process.env.NEXT_PUBLIC_DEV_BYPASS === 'true') {
    return NextResponse.next()
  }
  // next-auth v5 `auth` accepts a NextRequest in middleware context
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return (auth as any)(request)
}

export const config = {
  matcher: [
    '/((?!_next/static|_next/image|favicon.ico|login|api/auth).*)',
  ],
}
