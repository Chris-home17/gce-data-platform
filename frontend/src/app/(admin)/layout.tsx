import { redirect } from 'next/navigation'
import { auth } from '@/lib/auth'
import { Sidebar } from '@/components/layout/sidebar'
import { AdminShell } from './admin-shell'
import { AccountProvider } from '@/contexts/account-context'
import { DEV_BYPASS } from '@/lib/dev-bypass'

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  if (!DEV_BYPASS) {
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
