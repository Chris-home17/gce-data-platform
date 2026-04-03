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
  grantScope: 'ALL_PACKAGES' | 'PACKAGE'
  packageCode: string
  packageName: string
  grantedOnUtc: string
}

/** From App.vRoles (screen A-07) */
export interface Role {
  roleId: number
  roleCode: string
  roleName: string
  description: string | null
  isActive: boolean
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
  isActive: boolean
}

export interface CreatePolicyInput {
  policyName: string
  roleCodeTemplate: string
  roleNameTemplate: string
  scopeType: 'NONE' | 'ORGUNIT'
  orgUnitType?: string
  orgUnitCode?: string
  applyNow: boolean
}

/** From App.vDelegations (screen A-17) */
export interface Delegation {
  principalDelegationId: number
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
  isActive: boolean
  createdOnUtc: string
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

export type OrgUnitType = 'Division' | 'Country' | 'Site' | 'Region' | 'Branch' | 'Area' | 'Territory'

/** From App.vOrgUnits */
export interface OrgUnit {
  orgUnitId: number
  accountId: number
  accountCode: string
  accountName: string
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
  orgUnitCode: string
  orgUnitName: string
  orgUnitType: string
  accountId: number
  accountCode: string
  accountName: string
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
  category: string
  unit: string
  dataType: string
  collectionType: string
  thresholdDirection: 'Higher' | 'Lower' | null
  isActive: boolean
  assignmentCount: number
}

/** From KPI.Period via App.vKpiPeriods (screen K-02) */
export interface KpiPeriod {
  periodId: number
  externalId: string
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
  isRequired: boolean
  targetValue: number | null
  thresholdGreen: number | null
  thresholdAmber: number | null
  thresholdRed: number | null
  effectiveThresholdDirection: string | null
  isActive: boolean
  generatedAssignmentCount: number
}

/** From App.vSiteCompletionSummary (screen K-04) */
export interface SiteCompletion {
  accountCode: string
  siteCode: string
  siteName: string
  periodLabel: string
  totalRequired: number
  totalSubmitted: number
  totalLocked: number
  totalMissing: number
  completionPct: number
  reminderLevel: number | null
  reminderResolved: boolean
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
  dataType: 'Numeric' | 'Percentage' | 'Boolean' | 'Text' | 'Currency'
  collectionType: 'Manual' | 'Automated' | 'BulkUpload'
  thresholdDirection?: 'Higher' | 'Lower' | null
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

export interface AssignReportToPackageInput {
  reportCode: string
  packageCode: string
  remove?: boolean
}

export interface CreateOrgUnitInput {
  accountCode: string
  orgUnitType: string
  orgUnitCode: string
  orgUnitName: string
  parentOrgUnitType?: string
  parentOrgUnitCode?: string
  countryCode?: string
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
  materializeNow: boolean
}
