namespace GcePlatform.Api.Models;

// ---------------------------------------------------------------------------
// Generic list wrapper — matches the frontend ApiList<T> type
// ---------------------------------------------------------------------------

public record ApiList<T>(IEnumerable<T> Items, int TotalCount);

// ---------------------------------------------------------------------------
// Account  (App.vAccounts — screen A-01)
// ---------------------------------------------------------------------------

public record AccountDto(
    int     AccountId,
    string  AccountCode,
    string  AccountName,
    bool    IsActive,
    int     SiteCount,
    int     UserCount
);

public record CreateAccountRequest(
    string AccountCode,
    string AccountName
);

// ---------------------------------------------------------------------------
// Package  (App.vPackages — screen A-03)
// ---------------------------------------------------------------------------

public record PackageDto(
    int     PackageId,
    string  PackageCode,
    string  PackageName,
    string? PackageGroup,
    bool    IsActive,
    int     ReportCount
);

public record CreatePackageRequest(
    string  PackageCode,
    string  PackageName,
    string? PackageGroup
);

// ---------------------------------------------------------------------------
// BI Report  (App.vBiReports — screen A-05)
// ---------------------------------------------------------------------------

public record BiReportDto(
    int     BiReportId,
    string  ReportCode,
    string  ReportName,
    string? ReportUri,
    bool    IsActive,
    int     PackageCount,
    string  PackageList
);

public record CreateBiReportRequest(
    string  ReportCode,
    string  ReportName,
    string? ReportUri
);

public record AssignReportToPackageRequest(
    string ReportCode,
    string PackageCode,
    bool   Remove
);

// ---------------------------------------------------------------------------
// KPI Period  (App.vKpiPeriods — screen K-02)
// ---------------------------------------------------------------------------

public record KpiPeriodScheduleDto(
    int       PeriodScheduleId,
    Guid      ExternalId,
    string    ScheduleName,
    string    FrequencyType,
    byte?     FrequencyInterval,
    DateTime  StartDate,
    DateTime? EndDate,
    byte      SubmissionOpenDay,
    byte      SubmissionCloseDay,
    byte      GenerateMonthsAhead,
    string?   Notes,
    bool      IsActive,
    int       GeneratedPeriodCount,
    string?   FirstGeneratedPeriodLabel,
    string?   LastGeneratedPeriodLabel
);

public record CreateKpiPeriodScheduleRequest(
    string    ScheduleName,
    string    FrequencyType,
    byte?     FrequencyInterval,
    DateTime  StartDate,
    DateTime? EndDate,
    byte      SubmissionOpenDay,
    byte      SubmissionCloseDay,
    byte      GenerateMonthsAhead,
    string?   Notes,
    bool      GenerateNow
);

public record KpiPeriodDto(
    int      PeriodId,
    Guid     ExternalId,
    string   PeriodLabel,
    short    PeriodYear,
    byte     PeriodMonth,
    DateTime SubmissionOpenDate,
    DateTime SubmissionCloseDate,
    string   Status,
    bool     IsCurrentlyOpen,
    int?     DaysRemaining
);

public record CreateKpiPeriodRequest(
    short    PeriodYear,
    byte     PeriodMonth,
    DateTime SubmissionOpenDate,
    DateTime SubmissionCloseDate,
    string?  Notes
);

// ---------------------------------------------------------------------------
// KPI Definition  (App.vKpiDefinitions — screen K-01)
// ---------------------------------------------------------------------------

public record KpiDefinitionDto(
    int     KpiId,
    Guid    ExternalId,
    string  KpiCode,
    string  KpiName,
    string? KpiDescription,
    string? Category,
    string? Unit,
    string  DataType,
    string  CollectionType,
    string? ThresholdDirection,
    bool    IsActive,
    int     AssignmentCount
);

public record CreateKpiDefinitionRequest(
    string  KpiCode,
    string  KpiName,
    string? KpiDescription,
    string? Category,
    string? Unit,
    string  DataType,
    string  CollectionType,
    string? ThresholdDirection
);

// ---------------------------------------------------------------------------
// KPI Assignment  (App.vKpiAssignments — screen K-03)
// ---------------------------------------------------------------------------

public record KpiAssignmentDto(
    int      AssignmentId,
    Guid     ExternalId,
    string   KpiCode,
    string   KpiName,
    string?  Category,
    string   AccountCode,
    string   AccountName,
    string?  SiteCode,
    string?  SiteName,
    bool     IsAccountWide,
    string   PeriodLabel,
    bool     IsRequired,
    decimal? TargetValue,
    decimal? ThresholdGreen,
    decimal? ThresholdAmber,
    decimal? ThresholdRed,
    string   EffectiveThresholdDirection,
    bool     IsActive
);

public record KpiAssignmentTemplateDto(
    int       AssignmentTemplateId,
    Guid      ExternalId,
    string    KpiCode,
    string    KpiName,
    string?   CustomKpiName,
    string?   CustomKpiDescription,
    string?   EffectiveKpiName,
    string?   EffectiveKpiDescription,
    string?   Category,
    int?      PeriodScheduleId,
    string?   ScheduleName,
    string?   FrequencyType,
    byte?     FrequencyInterval,
    string    AccountCode,
    string    AccountName,
    string?   SiteCode,
    string?   SiteName,
    bool      IsAccountWide,
    bool      IsRequired,
    decimal?  TargetValue,
    decimal?  ThresholdGreen,
    decimal?  ThresholdAmber,
    decimal?  ThresholdRed,
    string?   EffectiveThresholdDirection,
    bool      IsActive,
    int       GeneratedAssignmentCount
);

public record CreateKpiAssignmentTemplateRequest(
    string   KpiCode,
    int      PeriodScheduleId,
    string   AccountCode,
    string?  OrgUnitCode,
    string   OrgUnitType,
    bool     IsRequired,
    decimal? TargetValue,
    decimal? ThresholdGreen,
    decimal? ThresholdAmber,
    decimal? ThresholdRed,
    string?  ThresholdDirection,
    string?  SubmitterGuidance,
    string?  CustomKpiName,
    string?  CustomKpiDescription,
    bool     MaterializeNow
);

public record CreateKpiAssignmentRequest(
    string   KpiCode,
    string   AccountCode,
    string?  OrgUnitCode,
    string   OrgUnitType,
    short    PeriodYear,
    byte     PeriodMonth,
    bool     IsRequired,
    decimal? TargetValue,
    decimal? ThresholdGreen,
    decimal? ThresholdAmber,
    decimal? ThresholdRed,
    string?  ThresholdDirection,
    string?  SubmitterGuidance
);

// ---------------------------------------------------------------------------
// Site Completion  (App.vSiteCompletionSummary — screen K-04)
// ---------------------------------------------------------------------------

public record SiteCompletionDto(
    string   AccountCode,
    string   AccountName,
    string   SiteCode,
    string   SiteName,
    string   PeriodLabel,
    int      TotalRequired,
    int      TotalSubmitted,
    int      TotalLocked,
    int      TotalMissing,
    decimal  CompletionPct,
    byte?    ReminderLevel,
    bool     ReminderResolved
);

// ---------------------------------------------------------------------------
// Org Unit create request  (App.InsertOrgUnit — screen M-03)
// ---------------------------------------------------------------------------

public record CreateOrgUnitRequest(
    string  AccountCode,
    string  OrgUnitType,
    string? OrgUnitCode,
    string? OrgUnitName,
    string? ParentOrgUnitType,
    string? ParentOrgUnitCode,
    int?    SharedGeoUnitId,
    int?    CountrySharedGeoUnitId
);

public record SharedGeoUnitDto(
    int      SharedGeoUnitId,
    string   GeoUnitType,
    string   GeoUnitCode,
    string   GeoUnitName,
    string?  CountryCode,
    bool     IsActive
);

public record CreateSharedGeoUnitRequest(
    string   GeoUnitType,
    string   GeoUnitCode,
    string   GeoUnitName,
    string?  CountryCode
);

// ---------------------------------------------------------------------------
// Source Mapping  (App.vSourceMappings — screen M-13)
// ---------------------------------------------------------------------------

public record SourceMappingDto(
    int      OrgUnitSourceMapId,
    int      OrgUnitId,
    int?     SharedGeoUnitId,
    string   OrgUnitCode,
    string   OrgUnitName,
    string   OrgUnitType,
    int?     AccountId,
    string?  AccountCode,
    string?  AccountName,
    string   SourceSystem,
    string   SourceOrgUnitId,
    string?  SourceOrgUnitName,
    bool     IsActive
);

public record CreateSourceMappingRequest(
    string  AccountCode,
    string  OrgUnitCode,
    string  OrgUnitType,
    string  SourceSystem,
    string  SourceOrgUnitId,
    string? SourceOrgUnitName
);

// ---------------------------------------------------------------------------
// Coverage Summary  (App.vCoverageSummary — screen M-11/M-12)
// ---------------------------------------------------------------------------

public record CoverageSummaryDto(
    int     UserId,
    string  Upn,
    int     PackageCount,
    int     ReportCount,
    int     SiteCount,
    int     AccountCount,
    string  GapStatus
);

// ---------------------------------------------------------------------------
// Account Role Policy  (Sec.AccountRolePolicy — screen A-09)
// ---------------------------------------------------------------------------

public record AccountRolePolicyDto(
    int      AccountRolePolicyId,
    string   PolicyName,
    string   RoleCodeTemplate,
    string   RoleNameTemplate,
    string   ScopeType,
    string?  OrgUnitType,
    string?  OrgUnitCode,
    bool     ExpandPerOrgUnit,
    bool     IsActive
);

public record CreateAccountRolePolicyRequest(
    string   PolicyName,
    string   RoleCodeTemplate,
    string   RoleNameTemplate,
    string   ScopeType,
    string?  OrgUnitType,
    string?  OrgUnitCode,
    bool     ExpandPerOrgUnit,
    bool     ApplyNow
);

// ---------------------------------------------------------------------------
// User create request
// ---------------------------------------------------------------------------

public record CreateUserRequest(
    string  Upn,
    string? DisplayName
);

// ---------------------------------------------------------------------------
// Grant  (App.vGrants / App.vPackageGrants — used by A-08, A-12)
// ---------------------------------------------------------------------------

public record GrantDto(
    int      PrincipalAccessGrantId,
    int      PrincipalId,
    string   PrincipalType,
    string   PrincipalName,
    string   AccessType,
    string   ScopeType,
    string   AccountCode,
    string   AccountName,
    string   OrgUnitType,
    string   OrgUnitCode,
    string   OrgUnitName,
    DateTime GrantedOnUtc
);

public record PackageGrantDto(
    int      PrincipalPackageGrantId,
    int      PrincipalId,
    string   PrincipalType,
    string   PrincipalName,
    string   GrantScope,
    string   PackageCode,
    string   PackageName,
    DateTime GrantedOnUtc
);

public record AddRoleMemberRequest(string UserUpn);

public record GrantAccessRequest(
    string  PrincipalType,
    string  PrincipalIdentifier,
    string  GrantType,
    string? PackageCode,
    string? AccountCode,
    string? OrgUnitType,
    string? OrgUnitCode,
    string? CountryCode
);

// ---------------------------------------------------------------------------
// Role  (App.vRoles — screen A-07 / A-08)
// ---------------------------------------------------------------------------

public record RoleDto(
    int     RoleId,
    string  RoleCode,
    string  RoleName,
    string? Description,
    bool    IsActive,
    int     MemberCount,
    int     AccessGrantCount,
    int     PackageGrantCount
);

public record CreateRoleRequest(
    string  RoleCode,
    string  RoleName,
    string? Description
);

public record RoleMemberDto(
    int      RoleId,
    int      MemberPrincipalId,
    string   Upn,
    string   DisplayName,
    DateTime AddedOnUtc
);

// ---------------------------------------------------------------------------
// Org Unit  (App.vOrgUnits — account structure / sites)
// ---------------------------------------------------------------------------

public record OrgUnitDto(
    int      OrgUnitId,
    int      AccountId,
    string   AccountCode,
    string   AccountName,
    int?     SharedGeoUnitId,
    string?  SharedGeoUnitCode,
    string?  SharedGeoUnitName,
    int?     CountryOrgUnitId,
    string?  CountryOrgUnitCode,
    string?  CountryOrgUnitName,
    string   OrgUnitType,
    string   OrgUnitCode,
    string   OrgUnitName,
    int?     ParentOrgUnitId,
    string?  ParentOrgUnitName,
    string?  ParentOrgUnitType,
    string   Path,
    string?  CountryCode,
    bool     IsActive,
    int      ChildCount,
    int      SourceMappingCount
);

// ---------------------------------------------------------------------------
// User  (App.vUsers)
// ---------------------------------------------------------------------------

public record UserDto(
    int     UserId,
    string  Upn,
    string  DisplayName,
    bool    IsActive,
    int     RoleCount,
    string? RoleList,
    int     SiteCount,
    int     AccountCount,
    string? GapStatus
);

// ---------------------------------------------------------------------------
// Delegation  (App.vDelegations — screen A-17)
// ---------------------------------------------------------------------------

public record DelegationDto(
    int      PrincipalDelegationId,
    string   DelegatorName,
    string   DelegatorType,
    string   DelegateName,
    string   DelegateType,
    string   AccessType,
    string   ScopeType,
    string   AccountCode,
    string   AccountName,
    string   OrgUnitType,
    string   OrgUnitCode,
    string   OrgUnitName,
    bool     IsActive,
    DateTime CreatedOnUtc
);

public record GrantDelegationRequest(
    string  DelegatorType,
    string  DelegatorIdentifier,
    string  DelegateType,
    string  DelegateIdentifier,
    string  AccessType,
    string? AccountCode,
    string  ScopeType,
    string? OrgUnitType,
    string? OrgUnitCode
);

// ---------------------------------------------------------------------------
// Error response
// ---------------------------------------------------------------------------

public record ApiError(string Code, string Message);

// Shared toggle request used by all PATCH /{entity}/{id}/status endpoints
public record SetActiveRequest(bool IsActive);
