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
// Account Branding
// ---------------------------------------------------------------------------

/// <summary>Raw DB projection — includes override fields for server-side resolution.</summary>
public record AccountBrandingRaw(
    int     AccountId,
    string? PrimaryColor,
    string? PrimaryColor2,
    string? SecondaryColor,
    string? SecondaryColor2,
    string? AccentColor,
    string? TextOnPrimaryOverride,
    string? TextOnSecondaryOverride,
    string? LogoDataUrl
);

/// <summary>
/// Resolved branding DTO sent to the frontend.
/// TextOnPrimary and TextOnSecondary are always final computed values —
/// the frontend never needs to recompute them.
/// </summary>
public record AccountBrandingDto(
    int     AccountId,
    string? PrimaryColor,
    string? PrimaryColor2,
    string? SecondaryColor,
    string? SecondaryColor2,
    string? AccentColor,
    string  TextOnPrimary,
    string  TextOnSecondary,
    string? LogoDataUrl
);

/// <summary>Admin request to save branding fields for an account.</summary>
public record UpdateAccountBrandingRequest(
    string? PrimaryColor,
    string? PrimaryColor2,
    string? SecondaryColor,
    string? SecondaryColor2,
    string? AccentColor,
    string? TextOnPrimaryOverride,
    string? TextOnSecondaryOverride,
    string? LogoDataUrl
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

public record UpdateBiReportRequest(
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
    int      PeriodScheduleId,
    string   ScheduleName,
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
// Tag  (App.vTags — Platform Config > Tags)
// ---------------------------------------------------------------------------

public record TagDto(
    int     TagId,
    string  TagCode,
    string  TagName,
    string? TagDescription,
    bool    IsActive,
    int     KpiCount
);

public record CreateTagRequest(
    string  TagCode,
    string  TagName,
    string? TagDescription
);

public record UpdateTagRequest(
    string  TagName,
    string? TagDescription
);

// ---------------------------------------------------------------------------
// KPI Package  (App.vKpiPackages — KPI Management > KPI Packages)
// ---------------------------------------------------------------------------

public record KpiPackageDto(
    int     KpiPackageId,
    string  PackageCode,
    string  PackageName,
    bool    IsActive,
    int     KpiCount,
    // Pipe-delimited "TagId:TagName" pairs (same pattern as KpiDefinition.TagsRaw)
    string? TagsRaw
);

public record KpiPackageItemDto(
    int     KpiPackageItemId,
    int     KpiPackageId,
    int     KpiId,
    string  KpiCode,
    string  KpiName,
    string? Category,
    string? DataType,
    bool    KpiIsActive
);

public record CreateKpiPackageRequest(
    string             PackageCode,
    string             PackageName,
    IEnumerable<int>?  TagIds
);

public record UpdateKpiPackageRequest(
    string             PackageName,
    IEnumerable<int>?  TagIds
);

public record SetKpiPackageItemsRequest(
    IEnumerable<int> KpiIds
);

public record CreateTemplatesFromPackageRequest(
    int      KpiPackageId,
    int      PeriodScheduleId,
    string   AccountCode,
    string?  OrgUnitCode,
    string   OrgUnitType,
    bool     IsRequired,
    bool     MaterializeNow
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
    bool    AllowMultiValue,
    string  CollectionType,
    string? ThresholdDirection,
    bool    IsActive,
    int     AssignmentCount,
    // Pipe-delimited option list for DropDown KPIs; null for other types
    string? DropDownOptionsRaw,
    // Tags as pipe-delimited "TagId:TagName" pairs; null if untagged
    string? TagsRaw
);

public record CreateKpiDefinitionRequest(
    string   KpiCode,
    string   KpiName,
    string?  KpiDescription,
    string?  Category,
    string?  Unit,
    string   DataType,
    bool     AllowMultiValue,
    string   CollectionType,
    string?  ThresholdDirection,
    // DropDown options — null to skip, empty list to clear
    IEnumerable<string>? DropDownOptions,
    // Tag IDs to assign — null to skip, empty list to clear
    IEnumerable<int>? TagIds
);

// KpiCode is immutable after creation (stable identifier used by assignments).
public record UpdateKpiDefinitionRequest(
    string   KpiName,
    string?  KpiDescription,
    string?  Category,
    string?  Unit,
    string   DataType,
    bool     AllowMultiValue,
    string   CollectionType,
    string?  ThresholdDirection,
    // DropDown options — null to leave unchanged, empty list to clear
    IEnumerable<string>? DropDownOptions,
    // Tag IDs — null to leave unchanged, empty list to clear
    IEnumerable<int>? TagIds
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
    string   DataType,
    int      PeriodId,
    int      PeriodScheduleId,
    string   ScheduleName,
    string   PeriodLabel,
    bool     IsRequired,
    decimal? TargetValue,
    decimal? ThresholdGreen,
    decimal? ThresholdAmber,
    decimal? ThresholdRed,
    string   EffectiveThresholdDirection,
    bool     IsActive,
    string?  AssignmentGroupName
);

// KPI Effective Assignment  (App.vEffectiveKpiAssignments — submission-facing)
// Site-specific assignments shadow account-wide ones for the same KPI + period.
// Account-wide assignments are expanded to one row per active site in the account.
// ---------------------------------------------------------------------------

public record EffectiveKpiAssignmentDto(
    int      AssignmentId,
    Guid     ExternalId,
    string   KpiCode,
    string   KpiName,
    string   EffectiveKpiName,
    string?  EffectiveKpiDescription,
    string?  Category,
    string   AccountCode,
    string   AccountName,
    string   SiteCode,
    string   SiteName,
    bool     IsAccountWide,
    string   PeriodLabel,
    int      PeriodYear,
    int      PeriodMonth,
    string   PeriodStatus,
    bool     IsRequired,
    decimal? TargetValue,
    decimal? ThresholdGreen,
    decimal? ThresholdAmber,
    decimal? ThresholdRed,
    string   EffectiveThresholdDirection,
    string?  SubmitterGuidance,
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
    string    DataType,
    bool      IsRequired,
    decimal?  TargetValue,
    decimal?  ThresholdGreen,
    decimal?  ThresholdAmber,
    decimal?  ThresholdRed,
    string?   EffectiveThresholdDirection,
    bool      IsActive,
    int       GeneratedAssignmentCount,
    // Package tracking — null for individually assigned templates
    int?      KpiPackageId,
    string?   KpiPackageName,
    string?   AssignmentGroupName
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
    bool     MaterializeNow,
    string?  AssignmentGroupName
);

public record BatchKpiAssignmentTemplateItem(
    string   KpiCode,
    int?     KpiPackageId,
    bool     IsRequired,
    decimal? TargetValue,
    decimal? ThresholdGreen,
    decimal? ThresholdAmber,
    decimal? ThresholdRed,
    string?  ThresholdDirection,
    string?  SubmitterGuidance,
    string?  CustomKpiName,
    string?  CustomKpiDescription
);

public record BatchCreateKpiAssignmentTemplatesRequest(
    int                    PeriodScheduleId,
    string                 AccountCode,
    // For single-site: provide OrgUnitCode. For multi-site: provide OrgUnitCodes list.
    // OrgUnitCodes takes precedence when both are provided.
    string?                OrgUnitCode,
    IEnumerable<string>?   OrgUnitCodes,
    string                 OrgUnitType,
    bool                   MaterializeNow,
    IEnumerable<BatchKpiAssignmentTemplateItem> Items,
    string?                AssignmentGroupName
);

public record BatchCreateKpiAssignmentTemplatesResponse(
    int                    CreatedCount,
    int                    SkippedCount,
    IEnumerable<string>    SkippedKpiCodes,
    IEnumerable<string>    Errors
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
    string?  SubmitterGuidance,
    string?  AssignmentGroupName
);

// ---------------------------------------------------------------------------
// Site Completion  (App.vSiteCompletionSummary — screen K-04)
// ---------------------------------------------------------------------------

public record SiteCompletionDto(
    string   AccountCode,
    string   AccountName,
    string   SiteCode,
    string   SiteName,
    int      SiteOrgUnitId,
    string   PeriodLabel,
    int      PeriodId,
    int      TotalRequired,
    int      TotalSubmitted,
    int      TotalLocked,
    int      TotalMissing,
    decimal  CompletionPct,
    byte?    ReminderLevel,
    bool     ReminderResolved,
    string?  GroupName
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

public record MoveOrgUnitRequest(
    int? ParentOrgUnitId
);

// ---------------------------------------------------------------------------
// Org Unit bulk import  (POST /org-units/bulk)
// ---------------------------------------------------------------------------

public record BulkOrgUnitRow(
    string  OrgUnitType,
    string  OrgUnitCode,
    string  OrgUnitName,
    string? ParentOrgUnitType,
    string? ParentOrgUnitCode
);

public record BulkCreateOrgUnitsRequest(
    string              AccountCode,
    List<BulkOrgUnitRow> Rows
);

public record BulkOrgUnitResult(
    int     RowIndex,
    bool    Success,
    int?    OrgUnitId,
    string? Error
);

public record BulkCreateOrgUnitsResponse(List<BulkOrgUnitResult> Results);

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

public record UpdateSharedGeoUnitRequest(
    string   GeoUnitType,
    string   GeoUnitCode,
    string   GeoUnitName,
    string?  CountryCode
);

public record BulkSharedGeoUnitRow(
    string   GeoUnitType,
    string   GeoUnitCode,
    string   GeoUnitName,
    string?  CountryCode
);

public record BulkCreateSharedGeoUnitsRequest(List<BulkSharedGeoUnitRow> Rows);

public record BulkSharedGeoUnitResult(
    int     RowIndex,
    bool    Success,
    int?    SharedGeoUnitId,
    string? Error
);

public record BulkCreateSharedGeoUnitsResponse(List<BulkSharedGeoUnitResult> Results);

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
// Platform roles / permissions
// ---------------------------------------------------------------------------

public record CurrentUserDto(
    int UserId,
    string Upn,
    string DisplayName,
    IEnumerable<string> Permissions
);

public record PlatformPermissionDto(
    int PermissionId,
    string PermissionCode,
    string DisplayName,
    string? Description,
    string? Category,
    int SortOrder
);

public record PlatformRoleDto(
    int PlatformRoleId,
    string RoleCode,
    string RoleName,
    string? Description,
    bool IsActive,
    int MemberCount,
    int PermissionCount
);

public record PlatformRoleMemberDto(
    int UserId,
    // Mixed-case Upn so System.Text.Json's camelCase policy emits "upn".
    // All-caps "UPN" would serialize as "uPN" and break the frontend contract.
    string Upn,
    string DisplayName,
    DateTime AssignedOnUtc
);

public record PlatformRoleDetailDto(
    PlatformRoleDto Role,
    IEnumerable<PlatformPermissionDto> Permissions,
    IEnumerable<PlatformRoleMemberDto> Members
);

public record CreatePlatformRoleRequest(
    string RoleCode,
    string RoleName,
    string? Description
);

public record SetPlatformRolePermissionsRequest(
    IEnumerable<string> PermissionCodes
);

public record AddPlatformRoleMemberRequest(
    string UserUpn
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

public record UpdateAccountRolePolicyRequest(
    string   PolicyName,
    string   RoleCodeTemplate,
    string   RoleNameTemplate,
    string   ScopeType,
    string?  OrgUnitType,
    string?  OrgUnitCode,
    bool     ExpandPerOrgUnit,
    bool     RefreshAfterSave
);

public record AccountRolePolicyRoleDto(
    int      AccountRolePolicyId,
    string   PolicyName,
    int      RoleId,
    string   RoleCode,
    string   RoleName,
    string?  Description,
    bool     IsActive,
    int      AccountId,
    string   AccountCode,
    string   AccountName,
    string   ScopeType,
    int?     OrgUnitId,
    string?  OrgUnitType,
    string?  OrgUnitCode,
    string?  OrgUnitName
);

// ---------------------------------------------------------------------------
// KPI Submission
// ---------------------------------------------------------------------------

public record SubmitKpiRequest(
    Guid     AssignmentExternalId,
    decimal? SubmissionValue,
    string?  SubmissionText,    // also used for DropDown selection(s)
    bool?    SubmissionBoolean, // used when DataType = 'Boolean'
    string?  SubmissionNotes,
    bool     LockOnSubmit,
    string?  ChangeReason,
    bool     BypassLock
);

public record KpiSubmissionDto(
    int      SubmissionId,
    Guid     AssignmentExternalId,
    decimal? SubmissionValue,
    string?  SubmissionText,
    bool?    SubmissionBoolean,
    string?  SubmissionNotes,
    string   LockState,
    string   SubmittedByUpn,
    DateTime SubmittedAt
);

// Admin drill-down: all assignments for a site+period with submission state
public record SiteSubmissionDetailDto(
    int       AssignmentId,
    Guid      ExternalId,        // used to call the unlock endpoint
    string    KpiCode,
    string    KpiName,
    string    EffectiveKpiName,
    string?   Category,
    string    DataType,
    bool      IsRequired,
    decimal?  TargetValue,
    decimal?  ThresholdGreen,
    decimal?  ThresholdAmber,
    decimal?  ThresholdRed,
    string?   EffectiveThresholdDirection,
    int?      SubmissionId,
    decimal?  SubmissionValue,
    string?   SubmissionText,
    bool?     SubmissionBoolean,
    string?   SubmissionNotes,
    string?   LockState,
    string?   SubmittedByUpn,
    DateTime? SubmittedAt,
    bool      IsSubmitted,
    string?   RagStatus,
    string?   AssignmentGroupName
);

// ---------------------------------------------------------------------------
// KPI Submission Token
// ---------------------------------------------------------------------------

public record CreateSubmissionTokenRequest(
    int     SiteOrgUnitId,
    int     PeriodId,
    string? AssignmentGroupName
);

public record KpiAssignmentGroupDto(
    int    AccountId,
    string AccountCode,
    string AccountName,
    string GroupName
);

public record SubmissionTokenDto(
    Guid     TokenId,
    string   SiteCode,
    string   SiteName,
    string   AccountCode,
    string   AccountName,
    string   PeriodLabel,
    string   PeriodStatus,
    DateTime PeriodCloseDate,
    DateTime ExpiresAtUtc,
    string   CreatedBy,
    DateTime CreatedAtUtc,
    DateTime? RevokedAtUtc
);

public record AssignmentWithSubmissionDto(
    int      AssignmentId,
    Guid     ExternalId,
    string   KpiCode,
    string   KpiName,
    string   EffectiveKpiName,
    string?  EffectiveKpiDescription,
    string?  Category,
    string   DataType,
    bool     AllowMultiValue,
    // Effective drop-down options: template override if present, else definition defaults.
    // Pipe-delimited; null for non-DropDown types.
    string?  DropDownOptionsRaw,
    bool     IsRequired,
    decimal? TargetValue,
    decimal? ThresholdGreen,
    decimal? ThresholdAmber,
    decimal? ThresholdRed,
    string?  EffectiveThresholdDirection,
    string?  SubmitterGuidance,
    int?     SubmissionId,
    decimal? SubmissionValue,
    string?  SubmissionText,
    bool?    SubmissionBoolean,
    string?  SubmissionNotes,
    string?  LockState,
    bool     IsSubmitted
);

public record SubmissionTokenContextDto(
    Guid                     TokenId,
    string                   SiteCode,
    string                   SiteName,
    string                   AccountCode,
    string                   AccountName,
    string                   PeriodLabel,
    string                   PeriodStatus,
    DateTime                 PeriodCloseDate,
    DateTime                 ExpiresAtUtc,
    string?                  AssignmentGroupName,
    IEnumerable<AssignmentWithSubmissionDto> Assignments,
    AccountBrandingDto?      Branding
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
    string   GrantSource,
    string?  SourceCode,
    string?  SourceName,
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
    int?    AccountId,
    string? AccountCode,
    string? AccountName,
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
    int     PackageCount,
    int     ReportCount,
    string? GapStatus
);

// ---------------------------------------------------------------------------
// Delegation  (App.vDelegations — screen A-17)
// ---------------------------------------------------------------------------

public record DelegationDto(
    int      PrincipalDelegationId,
    int      DelegatorPrincipalId,
    int      DelegatePrincipalId,
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
    string?  ValidFromDate,
    string?  ValidToDate,
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
    string? OrgUnitCode,
    string? ValidFromDate,
    string? ValidToDate
);

public record DelegationScopeAccountOptionDto(
    string AccountCode,
    string AccountName
);

public record DelegationScopeOrgUnitOptionDto(
    int    OrgUnitId,
    string AccountCode,
    string OrgUnitType,
    string OrgUnitCode,
    string OrgUnitName,
    string Path
);

public record DelegationScopeOptionsDto(
    List<DelegationScopeAccountOptionDto> Accounts,
    List<DelegationScopeOrgUnitOptionDto> OrgUnits
);

// ---------------------------------------------------------------------------
// Effective access — user detail, A-12
// ---------------------------------------------------------------------------

public record EffectiveAccessEntryDto(
    string  GrantSource,       // DIRECT | ROLE | DELEGATION
    string? SourceCode,        // RoleCode for ROLE; null otherwise
    string? SourceName,        // RoleName or delegator DisplayName
    string  AccessType,        // ALL | ACCOUNT
    string  ScopeType,         // NONE | ORGUNIT
    string? AccountCode,
    string? AccountName,
    string? ScopeOrgUnitCode,
    string? ScopeOrgUnitName,
    string? ScopeOrgUnitType
);

// ---------------------------------------------------------------------------
// Resolved effective access — App.GetUserEffectiveAccess SP result
// ---------------------------------------------------------------------------

public record EffectiveSiteDto(
    string  AccountCode,
    string  AccountName,
    string  SiteCode,
    string  SiteName,
    string? CountryCode,
    string? Path,
    string? SourceSystem,
    string? SourceOrgUnitId,
    string? SourceOrgUnitName
);

public record EffectiveReportDto(
    string  PackageCode,
    string  PackageName,
    string  ReportCode,
    string  ReportName
);

public record ResolvedAccessDto(
    IEnumerable<EffectiveSiteDto>   Sites,
    IEnumerable<EffectiveReportDto> Reports
);

// ---------------------------------------------------------------------------
// Error response
// ---------------------------------------------------------------------------

public record ApiError(string Code, string Message);

// Shared toggle request used by all PATCH /{entity}/{id}/status endpoints
public record SetActiveRequest(bool IsActive);
