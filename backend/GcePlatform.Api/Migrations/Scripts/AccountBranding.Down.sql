-- ============================================================
-- Migration: AccountBranding — Down
-- Reverses the branding additions.
-- ============================================================

-- 1. Drop the branding update procedure
IF OBJECT_ID('App.UpdateAccountBranding', 'P') IS NOT NULL
    DROP PROCEDURE App.UpdateAccountBranding;
GO

-- 2. Revert App.vAccounts to the pre-branding shape
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
        ISNULL(pkgPol.PackagePolicyCount, 0) AS TotalPolicyCount
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

-- 3. Drop branding columns from Dim.Account
--    (vAccounts has been dropped first so no view dependency remains)
ALTER TABLE Dim.Account
    DROP COLUMN PrimaryColor,
                PrimaryColor2,
                SecondaryColor,
                SecondaryColor2,
                AccentColor,
                TextOnPrimaryOverride,
                TextOnSecondaryOverride,
                LogoDataUrl;
GO
