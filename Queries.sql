/*
    Queries.sql
    Reference queries for auditing and analysing security coverage and data mappings.
    Use these as templates when validating effective access or building operations dashboards.
*/
SET NOCOUNT ON;
GO

/* --------------------------------------------------------------------------
   List every principal (user or role) with the packages and reports they can access
   -------------------------------------------------------------------------- */
SELECT
    p.PrincipalType,
    p.PrincipalName,
    pkg.PackageCode,
    pkg.PackageName,
    ar.ReportCode,
    ar.ReportName
FROM Sec.Principal AS p
JOIN Sec.vPrincipalPackageAccess AS pkg
    ON pkg.PrincipalId = p.PrincipalId
LEFT JOIN Dim.BiReportPackage AS rp
    ON rp.PackageId = pkg.PackageId
LEFT JOIN Dim.BiReport AS ar
    ON ar.BiReportId = rp.BiReportId
ORDER BY p.PrincipalType, p.PrincipalName, pkg.PackageCode, ar.ReportCode;
GO

/* --------------------------------------------------------------------------
   Summarise report coverage for each user (effective via roles or direct grants)
   -------------------------------------------------------------------------- */
WITH DistinctReports AS
(
    SELECT DISTINCT
        auth.UserUPN,
        auth.BiReportId,
        auth.PackageCode
    FROM Sec.vAuthorizedReportsDynamic AS auth
),
ReportCounts AS
(
    SELECT
        dr.UserUPN,
        COUNT(DISTINCT dr.BiReportId) AS ReportCount
    FROM DistinctReports AS dr
    GROUP BY dr.UserUPN
),
DistinctPackages AS
(
    SELECT DISTINCT
        dr.UserUPN,
        dr.PackageCode
    FROM DistinctReports AS dr
)
SELECT
    rc.UserUPN,
    rc.ReportCount,
    STRING_AGG(dp.PackageCode, ', ') AS Packages
FROM ReportCounts AS rc
LEFT JOIN DistinctPackages AS dp
    ON dp.UserUPN = rc.UserUPN
GROUP BY rc.UserUPN, rc.ReportCount
ORDER BY rc.UserUPN;
GO

/* --------------------------------------------------------------------------
   Inspect what a specific user can access (set @TargetUPN)
   -------------------------------------------------------------------------- */
DECLARE @TargetUPN NVARCHAR(320) = 'allison.tate@fabrikam.com';

SELECT
    auth.UserUPN,
    auth.PackageCode,
    auth.ReportCode,
    auth.ReportName
FROM Sec.vAuthorizedReportsDynamic AS auth
WHERE auth.UserUPN = @TargetUPN
ORDER BY auth.PackageCode, auth.ReportCode;
GO

/* --------------------------------------------------------------------------
   List direct and role-derived principals for a given user
   -------------------------------------------------------------------------- */
DECLARE @UserUPN NVARCHAR(320) = 'allison.tate@fabrikam.com';

SELECT
    u.UserId,
    u.UPN,
    grantMap.GrantPrincipalId,
    CASE pr.PrincipalType
        WHEN 'Role' THEN 'Role membership'
        ELSE 'User'
    END AS GrantOrigin,
    pr.PrincipalName
FROM Sec.[User] AS u
JOIN Sec.vUserGrantPrincipals AS grantMap
    ON grantMap.UserPrincipalId = u.UserId
JOIN Sec.Principal AS pr
    ON pr.PrincipalId = grantMap.GrantPrincipalId
WHERE u.UPN = @UserUPN;
GO

/* --------------------------------------------------------------------------
   Site coverage per principal, including account and hierarchy information
   -------------------------------------------------------------------------- */
SELECT
    auth.UserUPN,
    auth.AccountCode,
    auth.SiteCode,
    auth.SiteName,
    auth.CountryCode,
    auth.Path,
    auth.SourceSystem,
    auth.SourceOrgUnitId,
    auth.SourceOrgUnitName
FROM Sec.vAuthorizedSitesDynamic AS auth
ORDER BY auth.UserUPN, auth.AccountCode, auth.SiteCode;
GO

/* --------------------------------------------------------------------------
   Who can see a particular site? Set @AccountCode & @SiteCode accordingly
   -------------------------------------------------------------------------- */
DECLARE
    @AccountCode NVARCHAR(50) = 'DHL',
    @SiteCode    NVARCHAR(50) = 'US-01';

SELECT DISTINCT
    auth.UserUPN,
    auth.AccountCode,
    auth.SiteCode,
    auth.SiteName,
    auth.SourceSystem,
    auth.SourceOrgUnitId
FROM Sec.vAuthorizedSitesDynamic AS auth
WHERE auth.AccountCode = @AccountCode
  AND auth.SiteCode = @SiteCode
ORDER BY auth.UserUPN;
GO

/* --------------------------------------------------------------------------
   Grants inventory (rows from Sec.PrincipalAccessGrant) with resolved names
   -------------------------------------------------------------------------- */
SELECT
    p.PrincipalType,
    p.PrincipalName,
    pag.AccessType,
    CASE WHEN pag.AccountId IS NULL THEN 'N/A' ELSE acct.AccountCode END AS AccountCode,
    pag.ScopeType,
    org.OrgUnitType,
    org.OrgUnitCode,
    org.OrgUnitName,
    pag.GrantedOnUtc
FROM Sec.PrincipalAccessGrant AS pag
JOIN Sec.Principal AS p
    ON p.PrincipalId = pag.PrincipalId
LEFT JOIN Dim.Account AS acct
    ON acct.AccountId = pag.AccountId
LEFT JOIN Dim.OrgUnit AS org
    ON org.OrgUnitId = pag.OrgUnitId
ORDER BY p.PrincipalType, p.PrincipalName, pag.AccessType, pag.ScopeType;
GO

/* --------------------------------------------------------------------------
   Identify principals with ALL-account access but no package grants (potential gap)
   -------------------------------------------------------------------------- */
SELECT DISTINCT
    p.PrincipalType,
    p.PrincipalName
FROM Sec.PrincipalAccessGrant AS pag
JOIN Sec.Principal AS p
    ON p.PrincipalId = pag.PrincipalId
LEFT JOIN Sec.PrincipalPackageGrant AS pkg
    ON pkg.PrincipalId = p.PrincipalId
WHERE pag.AccessType = 'ALL'
  AND pag.ScopeType = 'NONE'
  AND pkg.PrincipalPackageGrantId IS NULL
ORDER BY p.PrincipalType, p.PrincipalName;
GO

/* --------------------------------------------------------------------------
   Source-system mapping audit: show external IDs per canonical org unit
   -------------------------------------------------------------------------- */
SELECT
    org.AccountId,
    acct.AccountCode,
    org.OrgUnitType,
    org.OrgUnitCode,
    org.OrgUnitName,
    map.SourceSystem,
    map.SourceOrgUnitId,
    map.SourceOrgUnitName,
    map.IsActive
FROM Dim.OrgUnit AS org
LEFT JOIN Dim.Account AS acct
    ON acct.AccountId = org.AccountId
LEFT JOIN Dim.OrgUnitSourceMap AS map
    ON map.OrgUnitId = org.OrgUnitId
ORDER BY acct.AccountCode, org.Path, map.SourceSystem;
GO

/* --------------------------------------------------------------------------
   Find source-system records that are not mapped yet
   (Assuming staging table Stg.SourceOrgUnit with columns SourceSystem, OrgUnitId)
   -------------------------------------------------------------------------- */
-- SELECT s.SourceSystem,
--        s.SourceOrgUnitId
-- FROM Stg.SourceOrgUnit AS s
-- LEFT JOIN Dim.OrgUnitSourceMap AS map
--     ON map.SourceSystem = s.SourceSystem
--    AND map.SourceOrgUnitId = s.SourceOrgUnitId
-- WHERE map.OrgUnitSourceMapId IS NULL;
-- GO

/* --------------------------------------------------------------------------
   User coverage summary (reports, packages, and sites per user)
   -------------------------------------------------------------------------- */
SELECT
    summary.UPN,
    summary.PackageCount,
    summary.ReportCount,
    summary.SiteCount,
    summary.AccountCount
FROM Sec.vUserCoverageSummary AS summary
ORDER BY summary.UPN;
GO

/* --------------------------------------------------------------------------
   Identify coverage gaps quickly via view
   -------------------------------------------------------------------------- */
SELECT *
FROM Sec.vUserAccessGaps;
GO

/* --------------------------------------------------------------------------
   Inspect configured automation policies
   -------------------------------------------------------------------------- */
SELECT
    accessPol.PolicyName,
    p.PrincipalName,
    accessPol.ScopeType,
    accessPol.OrgUnitType,
    accessPol.OrgUnitCode,
    accessPol.IsActive
FROM Sec.AccountAccessPolicy AS accessPol
JOIN Sec.Principal AS p ON p.PrincipalId = accessPol.PrincipalId
ORDER BY accessPol.PolicyName;
GO

SELECT
    packagePol.PolicyName,
    p.PrincipalName,
    packagePol.GrantScope,
    packagePol.PackageCode,
    packagePol.IsActive
FROM Sec.AccountPackagePolicy AS packagePol
JOIN Sec.Principal AS p ON p.PrincipalId = packagePol.PrincipalId
ORDER BY packagePol.PolicyName;
GO

/* --------------------------------------------------------------------------
   Delegation overview
   -------------------------------------------------------------------------- */
SELECT
    del.PrincipalDelegationId,
    delegator.PrincipalName AS Delegator,
    delegate.PrincipalName  AS Delegate,
    del.AccessType,
    acct.AccountCode,
    del.ScopeType,
    org.OrgUnitType,
    org.OrgUnitCode,
    del.IsActive,
    del.CreatedOnUtc
FROM Sec.PrincipalDelegation AS del
JOIN Sec.Principal AS delegator ON delegator.PrincipalId = del.DelegatorPrincipalId
JOIN Sec.Principal AS delegate  ON delegate.PrincipalId = del.DelegatePrincipalId
LEFT JOIN Dim.Account AS acct   ON acct.AccountId = del.AccountId
LEFT JOIN Dim.OrgUnit AS org    ON org.OrgUnitId = del.OrgUnitId
ORDER BY delegator.PrincipalName, delegate.PrincipalName;
GO

/* --------------------------------------------------------------------------
   Run health check (returns multiple result sets for issues & gaps)
   -------------------------------------------------------------------------- */
EXEC App.SecurityHealthCheck;
GO
