-- ============================================================
-- Migration: FixVAccountsPolicyCounts — Up
-- Removes three bogus columns from App.vAccounts:
--   AccessPolicyCount, PackagePolicyCount, TotalPolicyCount.
--
-- Why: Sec.AccountAccessPolicy and Sec.AccountPackagePolicy have no
-- AccountId — they are platform-wide policy templates. The OUTER APPLY
-- subqueries therefore returned the same global count on every account
-- row. No frontend DTO reads these columns. Safer to drop than to
-- try to invent a per-account count that does not exist.
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
        ISNULL(sites.SiteCount, 0) AS SiteCount,
        ISNULL(users.UserCount, 0) AS UserCount,
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
    ) AS users;
GO
