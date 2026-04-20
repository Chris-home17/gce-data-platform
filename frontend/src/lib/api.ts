/**
 * Thin typed fetch wrapper for the GCE Data Platform API.
 *
 * Base URL is read from NEXT_PUBLIC_API_BASE_URL.
 * Bearer token is obtained from the NextAuth session and attached to every
 * request automatically.
 *
 * All functions return plain typed Promises so TanStack Query can own caching
 * and lifecycle management.
 */

import { getSession } from 'next-auth/react'
import type {
  Account,
  AccountBranding,
  ApiList,
  AssignReportToPackageInput,
  BatchCreateKpiAssignmentTemplatesInput,
  BatchCreateKpiAssignmentTemplatesResponse,
  BiReport,
  CoverageSummary,
  CreateAccountInput,
  CreateBiReportInput,
  UpdateBiReportInput,
  CreatePlatformRoleInput,
  PlatformRole,
  PlatformPermission,
  PlatformRoleDetail,
  SetPlatformRolePermissionsInput,
  CreateKpiAssignmentInput,
  CreateKpiAssignmentTemplateInput,
  CreateKpiDefinitionInput,
  UpdateKpiDefinitionInput,
  CreateKpiPeriodInput,
  CreateKpiPeriodScheduleInput,
  BulkCreateOrgUnitsInput,
  BulkCreateOrgUnitsResponse,
  BulkCreateSharedGeoUnitsInput,
  BulkCreateSharedGeoUnitsResponse,
  CreateOrgUnitInput,
  CreatePackageInput,
  CreatePolicyInput,
  UpdatePolicyInput,
  MoveOrgUnitInput,
  CreateRoleInput,
  CreateSharedGeoUnitInput,
  UpdateSharedGeoUnitInput,
  CreateSourceMappingInput,
  CreateSubmissionTokenInput,
  CreateUserInput,
  UpdateAccountBrandingInput,
  CreateDelegationInput,
  Delegation,
  DelegationScopeOptions,
  EffectiveAccessEntry,
  ResolvedAccess,
  Grant,
  GrantAccessInput,
  KpiAssignment,
  KpiAssignmentGroup,
  KpiAssignmentTemplate,
  KpiDefinition,
  KpiPeriod,
  KpiPeriodSchedule,
  KpiPackage,
  KpiPackageDetail,
  CreateKpiPackageInput,
  UpdateKpiPackageInput,
  SetKpiPackageItemsInput,
  CreateTemplatesFromPackageInput,
  OrgUnit,
  Package,
  PackageGrant,
  Policy,
  PolicyRole,
  Role,
  RoleMember,
  SharedGeoUnit,
  Site,
  SiteCompletion,
  SiteSubmissionDetail,
  SourceMapping,
  SubmissionToken,
  SubmissionTokenContext,
  SubmitKpiInput,
  Tag,
  CreateTagInput,
  UpdateTagInput,
  User,
} from '@/types/api'

// ---------------------------------------------------------------------------
// Core fetch helper
// ---------------------------------------------------------------------------

const BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? ''

class ApiResponseError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message: string
  ) {
    super(message)
    this.name = 'ApiResponseError'
  }
}

async function getAuthHeaders(): Promise<HeadersInit> {
  // getSession is safe to call in both server and client contexts via next-auth v5
  const session = await getSession()
  const headers: HeadersInit = {
    'Content-Type': 'application/json',
    Accept: 'application/json',
  }
  // next-auth v5 exposes the access token on session.accessToken when configured
  const token = (session as { accessToken?: string } | null)?.accessToken
  if (token) {
    headers['Authorization'] = `Bearer ${token}`
  }
  return headers
}

async function apiFetch<T>(path: string, init?: RequestInit): Promise<T> {
  const headers = await getAuthHeaders()
  const response = await fetch(`${BASE_URL}${path}`, {
    ...init,
    headers: { ...headers, ...(init?.headers ?? {}) },
  })

  if (!response.ok) {
    let code = 'UNKNOWN_ERROR'
    let message = `HTTP ${response.status}`
    try {
      const body = await response.json()
      code = body?.code ?? code
      message = body?.message ?? message
    } catch {
      // ignore JSON parse errors on error responses
    }
    throw new ApiResponseError(response.status, code, message)
  }

  // Handle 204 No Content
  if (response.status === 204) {
    return undefined as unknown as T
  }

  return response.json() as Promise<T>
}

// ---------------------------------------------------------------------------
// API surface
// ---------------------------------------------------------------------------

export const api = {
  accounts: {
    list(): Promise<ApiList<Account>> {
      return apiFetch('/accounts')
    },
    get(id: number): Promise<Account> {
      return apiFetch(`/accounts/${id}`)
    },
    users(id: number): Promise<ApiList<User>> {
      return apiFetch(`/accounts/${id}/users`)
    },
    create(data: CreateAccountInput): Promise<Account> {
      return apiFetch('/accounts', { method: 'POST', body: JSON.stringify(data) })
    },
    setActive(id: number, isActive: boolean): Promise<void> {
      return apiFetch(`/accounts/${id}/status`, { method: 'PATCH', body: JSON.stringify({ isActive }) })
    },
    getBranding(id: number): Promise<AccountBranding | null> {
      return apiFetch(`/accounts/${id}/branding`)
    },
    updateBranding(id: number, data: UpdateAccountBrandingInput): Promise<void> {
      return apiFetch(`/accounts/${id}/branding`, { method: 'PUT', body: JSON.stringify(data) })
    },
  },

  users: {
    list(): Promise<ApiList<User>> {
      return apiFetch('/users')
    },
    get(id: number): Promise<User> {
      return apiFetch(`/users/${id}`)
    },
    create(data: CreateUserInput): Promise<User> {
      return apiFetch('/users', { method: 'POST', body: JSON.stringify(data) })
    },
    setActive(id: number, isActive: boolean): Promise<void> {
      return apiFetch(`/users/${id}/status`, { method: 'PATCH', body: JSON.stringify({ isActive }) })
    },
    roles(id: number): Promise<ApiList<Role>> {
      return apiFetch(`/users/${id}/roles`)
    },
    grants(id: number): Promise<ApiList<Grant>> {
      return apiFetch(`/users/${id}/grants`)
    },
    packageGrants(id: number): Promise<ApiList<PackageGrant>> {
      return apiFetch(`/users/${id}/package-grants`)
    },
    delegations(id: number): Promise<ApiList<Delegation>> {
      return apiFetch(`/users/${id}/delegations`)
    },
    effectiveAccess(id: number): Promise<ApiList<EffectiveAccessEntry>> {
      return apiFetch(`/users/${id}/effective-access`)
    },
    resolvedAccess(id: number): Promise<ResolvedAccess> {
      return apiFetch(`/users/${id}/resolved-access`)
    },
  },

  roles: {
    list(params?: { accountId?: number }): Promise<ApiList<Role>> {
      const qs = params?.accountId ? `?accountId=${params.accountId}` : ''
      return apiFetch(`/roles${qs}`)
    },
    get(id: number): Promise<Role> {
      return apiFetch(`/roles/${id}`)
    },
    create(data: CreateRoleInput): Promise<Role> {
      return apiFetch('/roles', { method: 'POST', body: JSON.stringify(data) })
    },
    setActive(id: number, isActive: boolean): Promise<void> {
      return apiFetch(`/roles/${id}/status`, { method: 'PATCH', body: JSON.stringify({ isActive }) })
    },
    members(id: number): Promise<ApiList<RoleMember>> {
      return apiFetch(`/roles/${id}/members`)
    },
    addMember(id: number, userUpn: string): Promise<void> {
      return apiFetch(`/roles/${id}/members`, { method: 'POST', body: JSON.stringify({ userUpn }) })
    },
    removeMember(id: number, userId: number): Promise<void> {
      return apiFetch(`/roles/${id}/members/${userId}`, { method: 'DELETE' })
    },
    grants(id: number): Promise<ApiList<Grant>> {
      return apiFetch(`/roles/${id}/grants`)
    },
    packageGrants(id: number): Promise<ApiList<PackageGrant>> {
      return apiFetch(`/roles/${id}/package-grants`)
    },
  },

  policies: {
    list(): Promise<ApiList<Policy>> {
      return apiFetch('/policies')
    },
    get(id: number): Promise<Policy> {
      return apiFetch(`/policies/${id}`)
    },
    roles(id: number): Promise<ApiList<PolicyRole>> {
      return apiFetch(`/policies/${id}/roles`)
    },
    create(data: CreatePolicyInput): Promise<Policy> {
      return apiFetch('/policies', { method: 'POST', body: JSON.stringify(data) })
    },
    update(id: number, data: UpdatePolicyInput): Promise<Policy> {
      return apiFetch(`/policies/${id}`, { method: 'PUT', body: JSON.stringify(data) })
    },
    refresh(id: number): Promise<void> {
      return apiFetch(`/policies/${id}/refresh`, { method: 'POST' })
    },
    setActive(id: number, isActive: boolean): Promise<void> {
      return apiFetch(`/policies/${id}/status`, { method: 'PATCH', body: JSON.stringify({ isActive }) })
    },
  },

  delegations: {
    list(): Promise<ApiList<Delegation>> {
      return apiFetch('/delegations')
    },
    scopeOptions(params: {
      delegatorType: 'USER' | 'ROLE'
      delegatorIdentifier: string
      accessType: 'ALL' | 'ACCOUNT'
      accountCode?: string
    }): Promise<DelegationScopeOptions> {
      const qs = new URLSearchParams({
        delegatorType: params.delegatorType,
        delegatorIdentifier: params.delegatorIdentifier,
        accessType: params.accessType,
      })
      if (params.accountCode) qs.set('accountCode', params.accountCode)
      return apiFetch(`/delegations/scope-options?${qs.toString()}`)
    },
    create(data: CreateDelegationInput): Promise<void> {
      return apiFetch('/delegations', { method: 'POST', body: JSON.stringify(data) })
    },
    setActive(id: number, isActive: boolean): Promise<void> {
      return apiFetch(`/delegations/${id}/status`, { method: 'PATCH', body: JSON.stringify({ isActive }) })
    },
    revoke(id: number): Promise<void> {
      return apiFetch(`/delegations/${id}`, { method: 'DELETE' })
    },
  },

  packages: {
    list(): Promise<ApiList<Package>> {
      return apiFetch('/packages')
    },
    get(id: number): Promise<Package> {
      return apiFetch(`/packages/${id}`)
    },
    create(data: CreatePackageInput): Promise<Package> {
      return apiFetch('/packages', { method: 'POST', body: JSON.stringify(data) })
    },
    setActive(id: number, isActive: boolean): Promise<void> {
      return apiFetch(`/packages/${id}/status`, { method: 'PATCH', body: JSON.stringify({ isActive }) })
    },
    reports(id: number): Promise<ApiList<BiReport>> {
      return apiFetch(`/packages/${id}/reports`)
    },
  },

  reports: {
    list(): Promise<ApiList<BiReport>> {
      return apiFetch('/reports')
    },
    get(id: number): Promise<BiReport> {
      return apiFetch(`/reports/${id}`)
    },
    create(data: CreateBiReportInput): Promise<BiReport> {
      return apiFetch('/reports', { method: 'POST', body: JSON.stringify(data) })
    },
    update(id: number, data: UpdateBiReportInput): Promise<BiReport> {
      return apiFetch(`/reports/${id}`, { method: 'PUT', body: JSON.stringify(data) })
    },
    assign(data: AssignReportToPackageInput): Promise<void> {
      return apiFetch('/reports/assign', { method: 'POST', body: JSON.stringify(data) })
    },
    setActive(id: number, isActive: boolean): Promise<void> {
      return apiFetch(`/reports/${id}/status`, { method: 'PATCH', body: JSON.stringify({ isActive }) })
    },
  },

  orgUnits: {
    list(params?: { accountId?: number }): Promise<ApiList<OrgUnit>> {
      const qs = params?.accountId ? `?accountId=${params.accountId}` : ''
      return apiFetch(`/org-units${qs}`)
    },
    get(id: number): Promise<OrgUnit> {
      return apiFetch(`/org-units/${id}`)
    },
    create(data: CreateOrgUnitInput): Promise<OrgUnit> {
      return apiFetch('/org-units', { method: 'POST', body: JSON.stringify(data) })
    },
    move(id: number, data: MoveOrgUnitInput): Promise<OrgUnit> {
      return apiFetch(`/org-units/${id}/move`, { method: 'POST', body: JSON.stringify(data) })
    },
    setActive(id: number, isActive: boolean): Promise<void> {
      return apiFetch(`/org-units/${id}/status`, { method: 'PATCH', body: JSON.stringify({ isActive }) })
    },
    bulkCreate(data: BulkCreateOrgUnitsInput): Promise<BulkCreateOrgUnitsResponse> {
      return apiFetch('/org-units/bulk', { method: 'POST', body: JSON.stringify(data) })
    },
  },

  sharedGeoUnits: {
    list(params?: { geoUnitType?: string }): Promise<ApiList<SharedGeoUnit>> {
      const qs = params?.geoUnitType ? `?geoUnitType=${encodeURIComponent(params.geoUnitType)}` : ''
      return apiFetch(`/shared-geo-units${qs}`)
    },
    create(data: CreateSharedGeoUnitInput): Promise<SharedGeoUnit> {
      return apiFetch('/shared-geo-units', { method: 'POST', body: JSON.stringify(data) })
    },
    update(id: number, data: UpdateSharedGeoUnitInput): Promise<SharedGeoUnit> {
      return apiFetch(`/shared-geo-units/${id}`, { method: 'PUT', body: JSON.stringify(data) })
    },
    bulkCreate(data: BulkCreateSharedGeoUnitsInput): Promise<BulkCreateSharedGeoUnitsResponse> {
      return apiFetch('/shared-geo-units/bulk', { method: 'POST', body: JSON.stringify(data) })
    },
  },

  sourceMappings: {
    list(params?: { accountId?: number }): Promise<ApiList<SourceMapping>> {
      const qs = params?.accountId ? `?accountId=${params.accountId}` : ''
      return apiFetch(`/source-mappings${qs}`)
    },
    create(data: CreateSourceMappingInput): Promise<SourceMapping> {
      return apiFetch('/source-mappings', { method: 'POST', body: JSON.stringify(data) })
    },
  },

  coverage: {
    list(): Promise<ApiList<CoverageSummary>> {
      return apiFetch('/coverage')
    },
  },

  grants: {
    grant(data: GrantAccessInput): Promise<void> {
      return apiFetch('/grants', { method: 'POST', body: JSON.stringify(data) })
    },
    async revoke(id: number): Promise<void> {
      try {
        await apiFetch(`/grants/${id}`, { method: 'DELETE' })
      } catch (err) {
        if (err instanceof ApiResponseError && err.status === 409 && err.code === 'GRANT_ALREADY_REVOKED') return
        throw err
      }
    },
    async revokePackage(id: number): Promise<void> {
      try {
        await apiFetch(`/package-grants/${id}`, { method: 'DELETE' })
      } catch (err) {
        if (err instanceof ApiResponseError && err.status === 409 && err.code === 'GRANT_ALREADY_REVOKED') return
        throw err
      }
    },
  },

  sites: {
    list(): Promise<ApiList<Site>> {
      return apiFetch('/sites')
    },
    get(id: number): Promise<Site> {
      return apiFetch(`/sites/${id}`)
    },
  },

  kpi: {
    periods: {
      schedules: {
        list(): Promise<ApiList<KpiPeriodSchedule>> {
          return apiFetch('/kpi/period-schedules')
        },
        create(data: CreateKpiPeriodScheduleInput): Promise<KpiPeriodSchedule> {
          return apiFetch('/kpi/period-schedules', { method: 'POST', body: JSON.stringify(data) })
        },
        generate(id: number): Promise<void> {
          return apiFetch(`/kpi/period-schedules/${id}/generate`, { method: 'POST' })
        },
        setActive(id: number, isActive: boolean): Promise<void> {
          return apiFetch(`/kpi/period-schedules/${id}/status`, { method: 'PATCH', body: JSON.stringify({ isActive }) })
        },
      },
      list(): Promise<ApiList<KpiPeriod>> {
        return apiFetch('/kpi/periods')
      },
      get(id: number): Promise<KpiPeriod> {
        return apiFetch(`/kpi/periods/${id}`)
      },
      create(data: CreateKpiPeriodInput): Promise<KpiPeriod> {
        return apiFetch('/kpi/periods', { method: 'POST', body: JSON.stringify(data) })
      },
      open(id: number): Promise<void> {
        return apiFetch(`/kpi/periods/${id}/open`, { method: 'POST' })
      },
      close(id: number): Promise<void> {
        return apiFetch(`/kpi/periods/${id}/close`, { method: 'POST' })
      },
    },
    definitions: {
      list(): Promise<ApiList<KpiDefinition>> {
        return apiFetch('/kpi/definitions')
      },
      get(id: number): Promise<KpiDefinition> {
        return apiFetch(`/kpi/definitions/${id}`)
      },
      create(data: CreateKpiDefinitionInput): Promise<KpiDefinition> {
        return apiFetch('/kpi/definitions', { method: 'POST', body: JSON.stringify(data) })
      },
      update(id: number, data: UpdateKpiDefinitionInput): Promise<KpiDefinition> {
        return apiFetch(`/kpi/definitions/${id}`, { method: 'PATCH', body: JSON.stringify(data) })
      },
      setActive(id: number, isActive: boolean): Promise<void> {
        return apiFetch(`/kpi/definitions/${id}/status`, { method: 'PATCH', body: JSON.stringify({ isActive }) })
      },
    },
    assignments: {
      groups(params?: { accountId?: number }): Promise<ApiList<KpiAssignmentGroup>> {
        const qs = new URLSearchParams()
        if (params?.accountId) qs.set('accountId', String(params.accountId))
        const query = qs.toString()
        return apiFetch(`/kpi/assignment-groups${query ? `?${query}` : ''}`)
      },
      templates: {
        list(params?: { accountId?: number }): Promise<ApiList<KpiAssignmentTemplate>> {
          const qs = new URLSearchParams()
          if (params?.accountId) qs.set('accountId', String(params.accountId))
          const query = qs.toString()
          return apiFetch(`/kpi/assignment-templates${query ? `?${query}` : ''}`)
        },
        create(data: CreateKpiAssignmentTemplateInput): Promise<KpiAssignmentTemplate> {
          return apiFetch('/kpi/assignment-templates', { method: 'POST', body: JSON.stringify(data) })
        },
        batchCreate(data: BatchCreateKpiAssignmentTemplatesInput): Promise<BatchCreateKpiAssignmentTemplatesResponse> {
          return apiFetch('/kpi/assignment-templates/batch', { method: 'POST', body: JSON.stringify(data) })
        },
        materialize(id: number): Promise<void> {
          return apiFetch(`/kpi/assignment-templates/${id}/materialize`, { method: 'POST' })
        },
        setActive(id: number, isActive: boolean): Promise<void> {
          return apiFetch(`/kpi/assignment-templates/${id}/status`, { method: 'PATCH', body: JSON.stringify({ isActive }) })
        },
      },
      list(params?: { periodId?: number; accountId?: number; siteCode?: string }): Promise<ApiList<KpiAssignment>> {
        const qs = new URLSearchParams()
        if (params?.periodId) qs.set('periodId', String(params.periodId))
        if (params?.accountId) qs.set('accountId', String(params.accountId))
        if (params?.siteCode) qs.set('siteCode', params.siteCode)
        const query = qs.toString()
        return apiFetch(`/kpi/assignments${query ? `?${query}` : ''}`)
      },
      create(data: CreateKpiAssignmentInput): Promise<KpiAssignment> {
        return apiFetch('/kpi/assignments', { method: 'POST', body: JSON.stringify(data) })
      },
      setActive(id: number, isActive: boolean): Promise<void> {
        return apiFetch(`/kpi/assignments/${id}/status`, { method: 'PATCH', body: JSON.stringify({ isActive }) })
      },
    },
    monitoring: {
      list(params?: { periodId?: number; accountId?: number; siteOrgUnitId?: number; groupName?: string | null }): Promise<ApiList<SiteCompletion>> {
        const qs = new URLSearchParams()
        if (params?.periodId) qs.set('periodId', String(params.periodId))
        if (params?.accountId) qs.set('accountId', String(params.accountId))
        if (params?.siteOrgUnitId) qs.set('siteOrgUnitId', String(params.siteOrgUnitId))
        if (params?.groupName != null) qs.set('groupName', params.groupName)
        const query = qs.toString()
        return apiFetch(`/kpi/monitoring${query ? `?${query}` : ''}`)
      },
    },
    submissions: {
      submit(data: SubmitKpiInput): Promise<{ submissionId: number }> {
        return apiFetch('/kpi/submissions', { method: 'POST', body: JSON.stringify(data) })
      },
      bulkSubmit(data: SubmitKpiInput[]): Promise<Array<{ assignmentExternalId: string; submissionId: number | null; success: boolean; error: string | null }>> {
        return apiFetch('/kpi/submissions/bulk', { method: 'POST', body: JSON.stringify(data) })
      },
      listForSite(params: { siteOrgUnitId: number; periodId: number }): Promise<ApiList<SiteSubmissionDetail>> {
        const qs = new URLSearchParams({ siteOrgUnitId: String(params.siteOrgUnitId), periodId: String(params.periodId) })
        return apiFetch(`/kpi/site-submissions?${qs}`)
      },
      unlock(assignmentExternalId: string): Promise<void> {
        return apiFetch(`/kpi/submissions/${assignmentExternalId}/unlock`, { method: 'PATCH' })
      },
    },
    packages: {
      list(): Promise<ApiList<KpiPackage>> {
        return apiFetch('/kpi/packages')
      },
      get(id: number): Promise<KpiPackageDetail> {
        return apiFetch(`/kpi/packages/${id}`)
      },
      create(data: CreateKpiPackageInput): Promise<KpiPackage> {
        return apiFetch('/kpi/packages', { method: 'POST', body: JSON.stringify(data) })
      },
      update(id: number, data: UpdateKpiPackageInput): Promise<KpiPackage> {
        return apiFetch(`/kpi/packages/${id}`, { method: 'PATCH', body: JSON.stringify(data) })
      },
      setActive(id: number, isActive: boolean): Promise<void> {
        return apiFetch(`/kpi/packages/${id}/status`, { method: 'PATCH', body: JSON.stringify({ isActive }) })
      },
      setItems(id: number, data: SetKpiPackageItemsInput): Promise<void> {
        return apiFetch(`/kpi/packages/${id}/items`, { method: 'PUT', body: JSON.stringify(data) })
      },
      assignTemplates(id: number, data: CreateTemplatesFromPackageInput): Promise<void> {
        return apiFetch(`/kpi/packages/${id}/assign-templates`, { method: 'POST', body: JSON.stringify(data) })
      },
    },
    submissionTokens: {
      list(params?: { siteOrgUnitId?: number; periodId?: number }): Promise<ApiList<SubmissionToken>> {
        const qs = new URLSearchParams()
        if (params?.siteOrgUnitId) qs.set('siteOrgUnitId', String(params.siteOrgUnitId))
        if (params?.periodId) qs.set('periodId', String(params.periodId))
        const query = qs.toString()
        return apiFetch(`/kpi/submission-tokens${query ? `?${query}` : ''}`)
      },
      create(data: CreateSubmissionTokenInput): Promise<SubmissionToken> {
        return apiFetch('/kpi/submission-tokens', { method: 'POST', body: JSON.stringify(data) })
      },
      getContext(tokenId: string): Promise<SubmissionTokenContext> {
        return apiFetch(`/kpi/submission-tokens/${tokenId}`)
      },
      revoke(tokenId: string): Promise<void> {
        return apiFetch(`/kpi/submission-tokens/${tokenId}`, { method: 'DELETE' })
      },
    },
  },
  tags: {
    list(): Promise<ApiList<Tag>> {
      return apiFetch('/tags')
    },
    get(id: number): Promise<Tag> {
      return apiFetch(`/tags/${id}`)
    },
    create(data: CreateTagInput): Promise<Tag> {
      return apiFetch('/tags', { method: 'POST', body: JSON.stringify(data) })
    },
    update(id: number, data: UpdateTagInput): Promise<Tag> {
      return apiFetch(`/tags/${id}`, { method: 'PATCH', body: JSON.stringify(data) })
    },
    setActive(id: number, isActive: boolean): Promise<void> {
      return apiFetch(`/tags/${id}/status`, { method: 'PATCH', body: JSON.stringify({ isActive }) })
    },
  },

  platformRoles: {
    list(): Promise<ApiList<PlatformRole>> {
      return apiFetch('/platform-roles')
    },
    get(id: number): Promise<PlatformRoleDetail> {
      return apiFetch(`/platform-roles/${id}`)
    },
    create(data: CreatePlatformRoleInput): Promise<PlatformRole> {
      return apiFetch('/platform-roles', { method: 'POST', body: JSON.stringify(data) })
    },
    setActive(id: number, isActive: boolean): Promise<void> {
      return apiFetch(`/platform-roles/${id}/status`, { method: 'PATCH', body: JSON.stringify({ isActive }) })
    },
    addMember(id: number, data: { userUpn: string }): Promise<void> {
      return apiFetch(`/platform-roles/${id}/members`, { method: 'POST', body: JSON.stringify(data) })
    },
    removeMember(id: number, userId: number): Promise<void> {
      return apiFetch(`/platform-roles/${id}/members/${userId}`, { method: 'DELETE' })
    },
    setPermissions(id: number, data: SetPlatformRolePermissionsInput): Promise<void> {
      return apiFetch(`/platform-roles/${id}/permissions`, { method: 'PUT', body: JSON.stringify(data) })
    },
  },

  platformPermissions: {
    list(): Promise<ApiList<PlatformPermission>> {
      return apiFetch('/platform-permissions')
    },
  },
} as const

export { ApiResponseError }
