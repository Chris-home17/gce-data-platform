import { redirect } from 'next/navigation'
import { auth } from '@/lib/auth'
import { Sidebar } from '@/components/layout/sidebar'
import { AdminShell } from './admin-shell'
import { AccountProvider } from '@/contexts/account-context'

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  // Dev bypass: skip session check so the app is reachable without Azure AD.
  // The login page still requires the Credentials sign-in step in this mode.
  if (process.env.NEXT_PUBLIC_DEV_BYPASS !== 'true') {
    const session = await auth()
    if (!session) redirect('/login')
  }

  return (
    <AccountProvider>
      <div className="flex min-h-screen bg-background">
        <Sidebar />
        <AdminShell>{children}</AdminShell>
      </div>
    </AccountProvider>
  )
}
