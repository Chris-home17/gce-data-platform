// ---------------------------------------------------------------------------
// Platform permission codes — kept in sync with backend Permissions class
// ---------------------------------------------------------------------------

export const PERMISSIONS = {
  SUPER_ADMIN:           'platform.super_admin',
  ACCOUNTS_MANAGE:       'accounts.manage',
  USERS_MANAGE:          'users.manage',
  GRANTS_MANAGE:         'grants.manage',
  KPI_MANAGE:            'kpi.manage',
  POLICIES_MANAGE:       'policies.manage',
  PLATFORM_ROLES_MANAGE: 'platform_roles.manage',
} as const

export type Permission = typeof PERMISSIONS[keyof typeof PERMISSIONS]

// ---------------------------------------------------------------------------
// API response wrappers
// ---------------------------------------------------------------------------

export interface ApiList<T> {
  items: T[]
  totalCount: number
}

export interface ApiError {
  message: string
  code: string
}

// ---------------------------------------------------------------------------
// RBAC domain types
// ---------------------------------------------------------------------------

/** From App.vAccounts (screen A-01) */
export interface Account {
  accountId: number
  accountCode: string
  accountName: string
  isActive: boolean
  siteCount: number
  userCount: number
}

/**
 * Resolved branding for an account.
 * textOnPrimary and textOnSecondary are always final computed values —
 * the frontend never needs to recompute them.
 */
export interface AccountBranding {
  accountId: number
  primaryColor: string | null
  primaryColor2: string | null
  secondaryColor: string | null
  secondaryColor2: string | null
  accentColor: string | null
  textOnPrimary: string
  textOnSecondary: string
  logoDataUrl: string | null
}

export interface UpdateAccountBrandingInput {
  primaryColor?: string | null
  primaryColor2?: string | null
  secondaryColor?: string | null
  secondaryColor2?: string | null
  accentColor?: string | null
  textOnPrimaryOverride?: string | null
  textOnSecondaryOverride?: string | null
  logoDataUrl?: string | null
}

/** From App.vUsers (screen A-11) */
export interface User {
  userId: number
  upn: string
  displayName: string
  isActive: boolean
  roleCount: number
  roleList: string | null
  siteCount: number
  accountCount: number
  packageCount: number
  reportCount: number
  gapStatus: string | null
}

/** From App.vGrants (used by A-08, A-12) */
export interface Grant {
  principalAccessGrantId: number
  principalId: number
  principalType: string
  principalName: string
  accessType: 'ALL' | 'ACCOUNT'
  scopeType: 'NONE' | 'ORGUNIT'
  accountCode: string
  accountName: string
  orgUnitType: string
  orgUnitCode: string
  orgUnitName: string
  grantedOnUtc: string
}

/** From App.vPackageGrants (used by A-08, A-12) */
export interface PackageGrant {
  principalPackageGrantId: number
  principalId: number
  principalType: string
  principalName: string
  grantSource: 'DIRECT' | 'ROLE'
  sourceCode: string | null
  sourceName: string | null
  grantScope: 'ALL_PACKAGES' | 'PACKAGE'
  packageCode: string
  packageName: string
  grantedOnUtc: string
}

/** From GET /users/{id}/effective-access */
export interface EffectiveAccessEntry {
  grantSource: 'DIRECT' | 'ROLE' | 'DELEGATION'
  sourceCode: string | null   // RoleCode or delegator UPN
  sourceName: string | null   // RoleName or delegator DisplayName
  accessType: 'ALL' | 'ACCOUNT'
  scopeType: 'NONE' | 'ORGUNIT'
  accountCode: string | null
  accountName: string | null
  scopeOrgUnitCode: string | null
  scopeOrgUnitName: string | null
  scopeOrgUnitType: string | null
}

/** From App.GetUserEffectiveAccess SP — resolved site access */
export interface EffectiveSite {
  accountCode: string
  accountName: string
  siteCode: string
  siteName: string
  countryCode: string | null
  path: string | null
  sourceSystem: string | null
  sourceOrgUnitId: string | null
  sourceOrgUnitName: string | null
}

/** From App.GetUserEffectiveAccess SP — resolved report access */
export interface EffectiveReport {
  packageCode: string
  packageName: string
  reportCode: string
  reportName: string
}

/** From GET /users/{id}/resolved-access */
export interface ResolvedAccess {
  sites: EffectiveSite[]
  reports: EffectiveReport[]
}

/** From App.vRoles (screen A-07) */
export interface Role {
  roleId: number
  roleCode: string
  roleName: string
  description: string | null
  isActive: boolean
  accountId: number | null
  accountCode: string | null
  accountName: string | null
  memberCount: number
  accessGrantCount: number
  packageGrantCount: number
}

/** From App.vRoleMembers (screen A-08) */
export interface RoleMember {
  roleId: number
  memberPrincipalId: number
  upn: string
  displayName: string
  addedOnUtc: string
}

/** From Sec.AccountRolePolicy (screen A-09) */
export interface Policy {
  accountRolePolicyId: number
  policyName: string
  roleCodeTemplate: string
  roleNameTemplate: string
  scopeType: 'NONE' | 'ORGUNIT'
  orgUnitType: string | null
  orgUnitCode: string | null
  expandPerOrgUnit: boolean
  isActive: boolean
}

export interface PolicyRole {
  accountRolePolicyId: number
  policyName: string
  roleId: number
  roleCode: string
  roleName: string
  description: string | null
  isActive: boolean
  accountId: number
  accountCode: string
  accountName: string
  scopeType: 'NONE' | 'ORGUNIT'
  orgUnitId: number | null
  orgUnitType: string | null
  orgUnitCode: string | null
  orgUnitName: string | null
}

export interface CreatePolicyInput {
  policyName: string
  roleCodeTemplate: string
  roleNameTemplate: string
  scopeType: 'NONE' | 'ORGUNIT'
  orgUnitType?: string
  orgUnitCode?: string
  expandPerOrgUnit: boolean
  applyNow: boolean
}

export interface UpdatePolicyInput {
  policyName: string
  roleCodeTemplate: string
  roleNameTemplate: string
  scopeType: 'NONE' | 'ORGUNIT'
  orgUnitType?: string
  orgUnitCode?: string
  expandPerOrgUnit: boolean
  refreshAfterSave: boolean
}

/** From App.vDelegations (screen A-17) */
export interface Delegation {
  principalDelegationId: number
  delegatorPrincipalId: number
  delegatePrincipalId: number
  delegatorName: string
  delegatorType: string
  delegateName: string
  delegateType: string
  accessType: 'ALL' | 'ACCOUNT'
  scopeType: 'NONE' | 'ORGUNIT'
  accountCode: string
  accountName: string
  orgUnitType: string
  orgUnitCode: string
  orgUnitName: string
  validFromDate: string | null
  validToDate: string | null
  isActive: boolean
  createdOnUtc: string
}

export interface DelegationScopeAccountOption {
  accountCode: string
  accountName: string
}

export interface DelegationScopeOrgUnitOption {
  orgUnitId: number
  accountCode: string
  orgUnitType: string
  orgUnitCode: string
  orgUnitName: string
  path: string
}

export interface DelegationScopeOptions {
  accounts: DelegationScopeAccountOption[]
  orgUnits: DelegationScopeOrgUnitOption[]
}

// ---------------------------------------------------------------------------
// Tag domain types
// ---------------------------------------------------------------------------

/** From App.vTags (Platform Config > Tags) */
export interface Tag {
  tagId: number
  tagCode: string
  tagName: string
  tagDescription: string | null
  isActive: boolean
  kpiCount: number
}

export interface CreateTagInput {
  tagCode: string
  tagName: string
  tagDescription?: string
}

export interface UpdateTagInput {
  tagName: string
  tagDescription?: string
}

// ---------------------------------------------------------------------------
// KPI Package domain types
// ---------------------------------------------------------------------------

/** Parsed tag entry from a pipe-delimited "TagId:TagName" raw string */
export interface KpiPackageTag {
  tagId: number
  tagName: string
}

/** Parse the pipe-delimited TagsRaw field into structured tag objects */
export function parsePackageTags(tagsRaw: string | null | undefined): KpiPackageTag[] {
  if (!tagsRaw) return []
  return tagsRaw.split('|').map((pair) => {
    const idx = pair.indexOf(':')
    return { tagId: parseInt(pair.slice(0, idx), 10), tagName: pair.slice(idx + 1) }
  })
}

/** From App.vKpiPackages (KPI Management > KPI Packages) */
export interface KpiPackage {
  kpiPackageId: number
  packageCode: string
  packageName: string
  isActive: boolean
  kpiCount: number
  /** Pipe-delimited "TagId:TagName" pairs; null if no tags */
  tagsRaw: string | null
}

export interface KpiPackageItem {
  kpiPackageItemId: number
  kpiPackageId: number
  kpiId: number
  kpiCode: string
  kpiName: string
  category: string | null
  dataType: string | null
  kpiIsActive: boolean
}

export interface KpiPackageDetail {
  package: KpiPackage
  items: KpiPackageItem[]
}

export interface CreateKpiPackageInput {
  packageCode: string
  packageName: string
  tagIds?: number[]
}

export interface UpdateKpiPackageInput {
  packageName: string
  tagIds?: number[]
}

export interface SetKpiPackageItemsInput {
  kpiIds: number[]
}

export interface CreateTemplatesFromPackageInput {
  kpiPackageId: number
  periodScheduleId: number
  accountCode: string
  orgUnitCode?: string | null
  orgUnitType: string
  isRequired: boolean
  materializeNow: boolean
}

export interface BatchKpiAssignmentTemplateItem {
  kpiCode: string
  kpiPackageId?: number | null
  isRequired: boolean
  targetValue?: number | null
  thresholdGreen?: number | null
  thresholdAmber?: number | null
  thresholdRed?: number | null
  thresholdDirection?: 'Higher' | 'Lower' | null
  submitterGuidance?: string | null
  customKpiName?: string | null
  customKpiDescription?: string | null
}

export interface BatchCreateKpiAssignmentTemplatesInput {
  periodScheduleId: number
  accountCode: string
  orgUnitCode?: string | null
  orgUnitCodes?: string[]
  orgUnitType: string
  materializeNow: boolean
  items: BatchKpiAssignmentTemplateItem[]
}

export interface BatchCreateKpiAssignmentTemplatesResponse {
  createdCount: number
  skippedCount: number
  skippedKpiCodes: string[]
  errors: string[]
}

// ---------------------------------------------------------------------------
// Catalogue domain types
// ---------------------------------------------------------------------------

/** From App.vPackages (screen A-03) */
export interface Package {
  packageId: number
  packageCode: string
  packageName: string
  packageGroup: string | null
  reportCount: number
  isActive: boolean
}

/** From App.vBiReports (screen A-05) */
export interface BiReport {
  biReportId: number
  reportCode: string
  reportName: string
  reportUri: string | null
  packageCount: number
  packageList: string
  isActive: boolean
}

// ---------------------------------------------------------------------------
// Infrastructure domain types
// ---------------------------------------------------------------------------

export type OrgUnitType = 'Region' | 'SubRegion' | 'Cluster' | 'Country' | 'Area' | 'Branch' | 'Site'

export interface SharedGeoUnit {
  sharedGeoUnitId: number
  geoUnitType: 'Region' | 'SubRegion' | 'Cluster' | 'Country'
  geoUnitCode: string
  geoUnitName: string
  countryCode: string | null
  isActive: boolean
}

export interface CreateSharedGeoUnitInput {
  geoUnitType: 'Region' | 'SubRegion' | 'Cluster' | 'Country'
  geoUnitCode: string
  geoUnitName: string
  countryCode?: string
}

export interface UpdateSharedGeoUnitInput {
  geoUnitType: 'Region' | 'SubRegion' | 'Cluster' | 'Country'
  geoUnitCode: string
  geoUnitName: string
  countryCode?: string
}

export interface BulkSharedGeoUnitRow {
  geoUnitType: string
  geoUnitCode: string
  geoUnitName: string
  countryCode?: string
}

export interface BulkCreateSharedGeoUnitsInput {
  rows: BulkSharedGeoUnitRow[]
}

export interface BulkSharedGeoUnitResult {
  rowIndex: number
  success: boolean
  sharedGeoUnitId: number | null
  error: string | null
}

export interface BulkCreateSharedGeoUnitsResponse {
  results: BulkSharedGeoUnitResult[]
}

/** From App.vOrgUnits */
export interface OrgUnit {
  orgUnitId: number
  accountId: number
  accountCode: string
  accountName: string
  sharedGeoUnitId: number | null
  sharedGeoUnitCode: string | null
  sharedGeoUnitName: string | null
  countryOrgUnitId: number | null
  countryOrgUnitCode: string | null
  countryOrgUnitName: string | null
  orgUnitType: OrgUnitType
  orgUnitCode: string
  orgUnitName: string
  parentOrgUnitId: number | null
  parentOrgUnitName: string | null
  parentOrgUnitType: string | null
  path: string
  countryCode: string | null
  isActive: boolean
  childCount: number
  sourceMappingCount: number
}

/** From App.vSourceMappings (screen M-13) */
export interface SourceMapping {
  orgUnitSourceMapId: number
  orgUnitId: number
  sharedGeoUnitId: number | null
  orgUnitCode: string
  orgUnitName: string
  orgUnitType: string
  accountId: number | null
  accountCode: string | null
  accountName: string | null
  sourceSystem: string
  sourceOrgUnitId: string
  sourceOrgUnitName: string | null
  isActive: boolean
}

/** From App.vCoverageSummary (screen M-11/M-12) */
export interface CoverageSummary {
  userId: number
  upn: string
  packageCount: number
  reportCount: number
  siteCount: number
  accountCount: number
  gapStatus: string
}

/** From App.vSites (screen M-03) */
export interface Site {
  siteId: number
  externalId: string
  siteCode: string
  siteName: string
  accountCode: string
  accountName: string
  region: string | null
  isActive: boolean
  userCount: number
}

// ---------------------------------------------------------------------------
// KPI domain types
// ---------------------------------------------------------------------------

export interface KpiPeriodSchedule {
  periodScheduleId: number
  externalId: string
  scheduleName: string
  frequencyType: 'Monthly' | 'EveryNMonths' | 'Quarterly' | 'SemiAnnual' | 'Annual'
  frequencyInterval: number | null
  startDate: string
  endDate: string | null
  submissionOpenDay: number
  submissionCloseDay: number
  generateMonthsAhead: number
  notes: string | null
  isActive: boolean
  generatedPeriodCount: number
  firstGeneratedPeriodLabel: string | null
  lastGeneratedPeriodLabel: string | null
}

/** From KPI.Definition via App.vKpiDefinitions (screen K-01) */
export interface KpiDefinition {
  kpiId: number
  externalId: string
  kpiCode: string
  kpiName: string
  kpiDescription: string | null
  category: string
  unit: string
  dataType: 'Numeric' | 'Percentage' | 'Boolean' | 'Text' | 'Currency' | 'DropDown' | string
  allowMultiValue: boolean
  collectionType: string
  thresholdDirection: 'Higher' | 'Lower' | null
  isActive: boolean
  assignmentCount: number
  /** Pipe-delimited option list for DropDown KPIs; null for other types */
  dropDownOptionsRaw: string | null
  /** Pipe-delimited "TagId:TagName" pairs; null if untagged */
  tagsRaw: string | null
}

/** From KPI.Period via App.vKpiPeriods (screen K-02) */
export interface KpiPeriod {
  periodId: number
  externalId: string
  periodScheduleId: number
  scheduleName: string
  periodLabel: string
  periodYear: number
  periodMonth: number
  submissionOpenDate: string
  submissionCloseDate: string
  status: 'Draft' | 'Open' | 'Closed' | 'Distributed'
  isCurrentlyOpen: boolean
  daysRemaining: number | null
}

/** From KPI.Assignment via App.vKpiAssignments (screen K-03) */
export interface KpiAssignment {
  assignmentId: number
  externalId: string
  kpiCode: string
  kpiName: string
  category: string | null
  accountCode: string
  accountName: string
  siteCode: string | null
  siteName: string | null
  isAccountWide: boolean
  dataType: string
  periodId: number
  periodScheduleId: number
  scheduleName: string
  periodLabel: string
  isRequired: boolean
  targetValue: number | null
  thresholdGreen: number | null
  thresholdAmber: number | null
  thresholdRed: number | null
  effectiveThresholdDirection: string
  isActive: boolean
}

export interface KpiAssignmentTemplate {
  assignmentTemplateId: number
  externalId: string
  kpiCode: string
  kpiName: string
  customKpiName: string | null
  customKpiDescription: string | null
  effectiveKpiName: string | null
  effectiveKpiDescription: string | null
  category: string | null
  periodScheduleId: number | null
  scheduleName: string | null
  frequencyType: 'Monthly' | 'EveryNMonths' | 'Quarterly' | 'SemiAnnual' | 'Annual' | null
  frequencyInterval: number | null
  accountCode: string
  accountName: string
  siteCode: string | null
  siteName: string | null
  isAccountWide: boolean
  dataType: string
  isRequired: boolean
  targetValue: number | null
  thresholdGreen: number | null
  thresholdAmber: number | null
  thresholdRed: number | null
  effectiveThresholdDirection: string | null
  isActive: boolean
  generatedAssignmentCount: number
  /** null for individually assigned templates */
  kpiPackageId: number | null
  kpiPackageName: string | null
}

/** From App.vSiteCompletionSummary (screen K-04) */
export interface SiteCompletion {
  accountCode: string
  accountName: string
  siteCode: string
  siteName: string
  siteOrgUnitId: number
  periodLabel: string
  periodId: number
  totalRequired: number
  totalSubmitted: number
  totalLocked: number
  totalMissing: number
  completionPct: number
  reminderLevel: number | null
  reminderResolved: boolean
}

/** Admin drill-down: assignment + submission state for a site+period */
export interface SiteSubmissionDetail {
  assignmentId: number
  externalId: string
  kpiCode: string
  kpiName: string
  effectiveKpiName: string
  category: string | null
  dataType: string
  isRequired: boolean
  targetValue: number | null
  thresholdGreen: number | null
  thresholdAmber: number | null
  thresholdRed: number | null
  effectiveThresholdDirection: string | null
  submissionId: number | null
  submissionValue: number | null
  submissionText: string | null
  submissionBoolean: boolean | null
  submissionNotes: string | null
  lockState: 'Unlocked' | 'Locked' | 'LockedByAuto' | 'LockedByPeriodClose' | null
  submittedByUpn: string | null
  submittedAt: string | null
  isSubmitted: boolean
  ragStatus: 'Green' | 'Amber' | 'Red' | null
}

// ---------------------------------------------------------------------------
// Form input types
// ---------------------------------------------------------------------------

export interface CreateAccountInput {
  accountCode: string
  accountName: string
}

export interface CreateUserInput {
  upn: string
  displayName?: string
}

export interface CreateRoleInput {
  roleCode: string
  roleName: string
  description?: string
}

export interface CreateKpiPeriodInput {
  periodYear: number
  periodMonth: number
  submissionOpenDate: string   // YYYY-MM-DD
  submissionCloseDate: string  // YYYY-MM-DD
  notes?: string
}

export interface CreateKpiPeriodScheduleInput {
  scheduleName: string
  frequencyType: 'Monthly' | 'EveryNMonths' | 'Quarterly' | 'SemiAnnual' | 'Annual'
  frequencyInterval?: number | null
  startDate: string
  endDate?: string | null
  submissionOpenDay: number
  submissionCloseDay: number
  generateMonthsAhead: number
  notes?: string
  generateNow: boolean
}

export interface CreateKpiDefinitionInput {
  kpiCode: string
  kpiName: string
  kpiDescription?: string
  category?: string
  unit?: string
  dataType: 'Numeric' | 'Percentage' | 'Boolean' | 'Text' | 'Currency' | 'DropDown'
  allowMultiValue?: boolean
  collectionType: 'Manual' | 'Automated' | 'BulkUpload'
  thresholdDirection?: 'Higher' | 'Lower' | null
  dropDownOptions?: string[]
  tagIds?: number[]
}

export interface UpdateKpiDefinitionInput {
  kpiName: string
  kpiDescription?: string
  category?: string
  unit?: string
  dataType: 'Numeric' | 'Percentage' | 'Boolean' | 'Text' | 'Currency' | 'DropDown'
  allowMultiValue?: boolean
  collectionType: 'Manual' | 'Automated' | 'BulkUpload'
  thresholdDirection?: 'Higher' | 'Lower' | null
  dropDownOptions?: string[] | null
  tagIds?: number[] | null
}

export type GrantType = 'GLOBAL_ALL' | 'GLOBAL_PACKAGE' | 'FULL_ACCOUNT' | 'PATH_PREFIX' | 'COUNTRY_ALL'

export interface GrantAccessInput {
  principalType: 'USER' | 'ROLE'
  principalIdentifier: string   // UPN for users, RoleCode for roles
  grantType: GrantType
  packageCode?: string
  accountCode?: string
  orgUnitType?: string
  orgUnitCode?: string
  countryCode?: string
}

export interface CreatePackageInput {
  packageCode: string
  packageName: string
  packageGroup?: string
}

export interface CreateBiReportInput {
  reportCode: string
  reportName: string
  reportUri?: string
}

export interface UpdateBiReportInput {
  reportName: string
  reportUri?: string
}

export interface AssignReportToPackageInput {
  reportCode: string
  packageCode: string
  remove?: boolean
}

export interface CreateOrgUnitInput {
  accountCode: string
  orgUnitType: string
  orgUnitCode?: string
  orgUnitName?: string
  parentOrgUnitType?: string
  parentOrgUnitCode?: string
  sharedGeoUnitId?: number
  countrySharedGeoUnitId?: number
}

export interface MoveOrgUnitInput {
  parentOrgUnitId?: number | null
}

export interface BulkOrgUnitRow {
  orgUnitType: string
  orgUnitCode: string
  orgUnitName: string
  parentOrgUnitType?: string
  parentOrgUnitCode?: string
}

export interface BulkCreateOrgUnitsInput {
  accountCode: string
  rows: BulkOrgUnitRow[]
}

export interface BulkOrgUnitResult {
  rowIndex: number
  success: boolean
  orgUnitId: number | null
  error: string | null
}

export interface BulkCreateOrgUnitsResponse {
  results: BulkOrgUnitResult[]
}

export interface CreateSourceMappingInput {
  accountCode: string
  orgUnitCode: string
  orgUnitType: string
  sourceSystem: string
  sourceOrgUnitId: string
  sourceOrgUnitName?: string
}

export interface CreateDelegationInput {
  delegatorType: 'USER' | 'ROLE'
  delegatorIdentifier: string
  delegateType: 'USER' | 'ROLE'
  delegateIdentifier: string
  accessType: 'ALL' | 'ACCOUNT'
  accountCode?: string
  scopeType: 'NONE' | 'ORGUNIT'
  orgUnitType?: string
  orgUnitCode?: string
  validFromDate?: string
  validToDate?: string
}

export interface CreateKpiAssignmentInput {
  kpiCode: string
  accountCode: string
  orgUnitCode?: string | null
  orgUnitType?: string
  periodYear: number
  periodMonth: number
  isRequired: boolean
  targetValue?: number | null
  thresholdGreen?: number | null
  thresholdAmber?: number | null
  thresholdRed?: number | null
  thresholdDirection?: 'Higher' | 'Lower' | null
  submitterGuidance?: string
}

export interface CreateKpiAssignmentTemplateInput {
  kpiCode: string
  periodScheduleId: number
  accountCode: string
  orgUnitCode?: string | null
  orgUnitType?: string
  isRequired: boolean
  targetValue?: number | null
  thresholdGreen?: number | null
  thresholdAmber?: number | null
  thresholdRed?: number | null
  thresholdDirection?: 'Higher' | 'Lower' | null
  submitterGuidance?: string
  customKpiName?: string | null
  customKpiDescription?: string | null
  materializeNow: boolean
}

// ---------------------------------------------------------------------------
// KPI Submission types
// ---------------------------------------------------------------------------

export interface SubmitKpiInput {
  assignmentExternalId: string
  submissionValue?: number | null
  submissionText?: string | null       // also used for DropDown selection(s)
  submissionBoolean?: boolean | null   // used when dataType === 'Boolean'
  submissionNotes?: string | null
  lockOnSubmit: boolean
  changeReason?: string | null
  bypassLock: boolean
}

export interface AssignmentWithSubmission {
  assignmentId: number
  externalId: string
  kpiCode: string
  kpiName: string
  effectiveKpiName: string
  effectiveKpiDescription: string | null
  category: string | null
  dataType: 'Numeric' | 'Percentage' | 'Currency' | 'Boolean' | 'Text' | 'DropDown' | string
  allowMultiValue: boolean
  /** Pipe-delimited effective option list for DropDown KPIs */
  dropDownOptionsRaw: string | null
  isRequired: boolean
  targetValue: number | null
  thresholdGreen: number | null
  thresholdAmber: number | null
  thresholdRed: number | null
  effectiveThresholdDirection: string | null
  submitterGuidance: string | null
  submissionId: number | null
  submissionValue: number | null
  submissionText: string | null
  submissionBoolean: boolean | null
  submissionNotes: string | null
  lockState: 'Unlocked' | 'Locked' | 'LockedByAuto' | 'LockedByPeriodClose' | null
  isSubmitted: boolean
}

export interface SubmissionTokenContext {
  tokenId: string
  siteCode: string
  siteName: string
  accountCode: string
  accountName: string
  periodLabel: string
  periodStatus: string
  periodCloseDate: string
  expiresAtUtc: string
  assignments: AssignmentWithSubmission[]
  branding?: AccountBranding | null
}

export interface SubmissionToken {
  tokenId: string
  siteCode: string
  siteName: string
  accountCode: string
  accountName: string
  periodLabel: string
  periodStatus: string
  periodCloseDate: string
  expiresAtUtc: string
  createdBy: string
  createdAtUtc: string
  revokedAtUtc: string | null
}

export interface CreateSubmissionTokenInput {
  siteOrgUnitId: number
  periodId: number
}

// ---------------------------------------------------------------------------
// Platform Roles & Permissions
// ---------------------------------------------------------------------------

export interface PlatformRole {
  platformRoleId: number
  roleCode: string
  roleName: string
  description: string | null
  isActive: boolean
  memberCount: number
  permissionCount: number
}

export interface PlatformPermission {
  permissionCode: string
  displayName: string
  description: string | null
  category: string
}

export interface PlatformRoleMember {
  userId: number
  upn: string
  displayName: string
  assignedOnUtc: string
}

export interface PlatformRoleDetail {
  role: PlatformRole
  permissions: PlatformPermission[]
  members: PlatformRoleMember[]
}

export interface CreatePlatformRoleInput {
  roleCode: string
  roleName: string
  description?: string
}

export interface SetPlatformRolePermissionsInput {
  permissionCodes: string[]
}
