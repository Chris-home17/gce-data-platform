import { redirect } from 'next/navigation'

/**
 * Root admin route — immediately redirects to the Dashboard,
 * which is the primary landing screen for platform administrators.
 */
export default function AdminRootPage() {
  redirect('/dashboard')
}
