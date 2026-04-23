-- ============================================================
-- Migration: FixVAccountsPolicyCounts — Down
-- Restores the prior App.vAccounts shape (with the buggy
-- platform-wide policy counts) for rollback parity.
-- ============================================================

IF OBJECT_ID('App.vAccounts', 'V') IS NOT NULL
    DROP VIEW App.vAccounts;
GO

CREATE OR ALTER VIEW App.vAccounts
AS
    SELECT
        a.AccountId,
        a.AccountCode,
        a.AccountName,
        a.IsActive,
        a.CreatedOnUtc,
        a.ModifiedOnUtc,
        ISNULL(sites.SiteCount, 0)           AS SiteCount,
        ISNULL(users.UserCount, 0)           AS UserCount,
        ISNULL(accPol.AccessPolicyCount, 0)  AS AccessPolicyCount,
        ISNULL(pkgPol.PackagePolicyCount, 0) AS PackagePolicyCount,
        ISNULL(accPol.AccessPolicyCount, 0) +
        ISNULL(pkgPol.PackagePolicyCount, 0) AS TotalPolicyCount,
        a.PrimaryColor,
        a.PrimaryColor2,
        a.SecondaryColor,
        a.SecondaryColor2,
        a.AccentColor,
        a.TextOnPrimaryOverride,
        a.TextOnSecondaryOverride,
        a.LogoDataUrl
    FROM Dim.Account AS a
    OUTER APPLY
    (
        SELECT COUNT(*) AS SiteCount
        FROM Dim.OrgUnit AS ou
        WHERE ou.AccountId = a.AccountId
          AND ou.OrgUnitType = 'Site'
          AND ou.IsActive = 1
    ) AS sites
    OUTER APPLY
    (
        SELECT COUNT(DISTINCT u.UserId) AS UserCount
        FROM Sec.vAuthorizedSitesDynamic AS auth
        JOIN Sec.[User] AS u ON u.UPN = auth.UserUPN
        WHERE auth.AccountId = a.AccountId
    ) AS users
    OUTER APPLY
    (
        SELECT COUNT(*) AS AccessPolicyCount
        FROM Sec.AccountAccessPolicy AS pol
        WHERE pol.IsActive = 1
    ) AS accPol
    OUTER APPLY
    (
        SELECT COUNT(*) AS PackagePolicyCount
        FROM Sec.AccountPackagePolicy AS pol
        WHERE pol.IsActive = 1
    ) AS pkgPol;
GO
