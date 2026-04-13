/**
 * NextAuth v5 configuration.
 *
 * Exported as `auth` so it can be used in both the route handler and
 * middleware without duplicating configuration.
 *
 * Dev bypass
 * ----------
 * Set NEXT_PUBLIC_DEV_BYPASS=true in .env.local to skip Azure AD entirely.
 * A Credentials provider is used instead — one click signs you in as a
 * local dev user. No Azure application registration needed.
 */

import NextAuth from 'next-auth'
import AzureAD from 'next-auth/providers/microsoft-entra-id'
import Credentials from 'next-auth/providers/credentials'

const DEV_BYPASS = process.env.NEXT_PUBLIC_DEV_BYPASS === 'true'
const BASE_SCOPES = ['openid', 'profile', 'email', 'offline_access']
const API_SCOPE = process.env.AZURE_AD_API_SCOPE?.trim()
const AUTHORIZATION_SCOPE = [...BASE_SCOPES, ...(API_SCOPE ? [API_SCOPE] : [])].join(' ')

export const { handlers, auth, signIn, signOut } = NextAuth({
  providers: DEV_BYPASS
    ? [
        Credentials({
          name: 'Dev Bypass',
          credentials: {
            name: { label: 'Name', type: 'text' },
          },
          // Accept any input — local dev only, never deployed
          authorize(credentials) {
            return {
              id: 'dev-user-001',
              name: (credentials?.name as string | undefined) || 'Dev User',
              email: 'dev@gce-platform.local',
            }
          },
        }),
      ]
    : [
        AzureAD({
          clientId: process.env.AZURE_AD_CLIENT_ID!,
          clientSecret: process.env.AZURE_AD_CLIENT_SECRET!,
          issuer: `https://login.microsoftonline.com/${process.env.AZURE_AD_TENANT_ID!}/v2.0`,
          authorization: {
            params: { scope: AUTHORIZATION_SCOPE },
          },
        }),
      ],

  callbacks: {
    async jwt({ token, account }) {
      if (account?.access_token) {
        token.accessToken = account.access_token
      }
      // Give the API client a placeholder so it doesn't send an empty header
      if (DEV_BYPASS && !token.accessToken) {
        token.accessToken = 'dev-bypass-token'
      }
      // Fetch permissions + userId once from the backend after initial sign-in.
      // In dev bypass mode, skip the API call and grant all permissions locally.
      if (token.accessToken && token.permissions === undefined) {
        if (DEV_BYPASS) {
          token.permissions = [
            'platform.super_admin',
            'accounts.manage',
            'users.manage',
            'grants.manage',
            'kpi.manage',
            'policies.manage',
            'platform_roles.manage',
          ]
          token.userId = 1
        } else {
          try {
            const res = await fetch(
              `${process.env.NEXT_PUBLIC_API_BASE_URL}/auth/me`,
              { headers: { Authorization: `Bearer ${token.accessToken}` } }
            )
            if (res.ok) {
              const data = await res.json()
              token.permissions = data.permissions ?? []
              token.userId = data.userId ?? null
            } else {
              token.permissions = []
            }
          } catch {
            token.permissions = []
          }
        }
      }
      return token
    },
    async session({ session, token }) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const s = session as any
      s.accessToken = token.accessToken
      s.permissions = token.permissions
      s.userId = token.userId
      return session
    },
  },

  pages: {
    signIn: '/login',
    error: '/login',
  },
})
