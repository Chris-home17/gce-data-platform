import type { Metadata } from 'next'
import { PageHeader } from '@/components/shared/page-header'
import { PoliciesTable } from './policies-table'
import { NewPolicyDialog } from './new-policy-dialog'

export const metadata: Metadata = { title: 'Policies' }

export default function PoliciesPage() {
  return (
    <div className="space-y-6">
      <PageHeader
        title="Role Policies"
        description="Templates that auto-generate per-account roles when policies are applied. Tokens: {AccountCode}, {AccountName}."
        actions={<NewPolicyDialog />}
      />
      <PoliciesTable />
    </div>
  )
}
