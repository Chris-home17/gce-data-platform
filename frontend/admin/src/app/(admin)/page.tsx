import { redirect } from 'next/navigation'

/**
 * Root admin route — immediately redirects to the Accounts list,
 * which is the primary landing screen for platform administrators.
 */
export default function AdminRootPage() {
  redirect('/accounts')
}
