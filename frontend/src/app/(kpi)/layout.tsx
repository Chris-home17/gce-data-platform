import { redirect } from 'next/navigation'
import { auth } from '@/lib/auth'

export default async function KpiLayout({ children }: { children: React.ReactNode }) {
  if (process.env.NEXT_PUBLIC_DEV_BYPASS !== 'true') {
    const session = await auth()
    if (!session) redirect('/login')
  }

  return (
    <div className="min-h-screen bg-background">
      {children}
    </div>
  )
}
