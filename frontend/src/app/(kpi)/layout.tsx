import { redirect } from 'next/navigation'
import { auth } from '@/lib/auth'
import { DEV_BYPASS } from '@/lib/dev-bypass'

export default async function KpiLayout({ children }: { children: React.ReactNode }) {
  if (!DEV_BYPASS) {
    const session = await auth()
    if (!session) redirect('/login')
  }

  return (
    <div className="min-h-screen bg-background">
      {children}
    </div>
  )
}
