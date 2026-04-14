-- ============================================================
-- Migration: AccountBranding — Up
-- Adds per-account branding (colors + logo) to the platform.
-- Safe to re-run: all statements are idempotent.
-- ============================================================

-- 1. Add branding columns to Dim.Account (idempotent guard)
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Dim.Account') AND name = 'PrimaryColor')
BEGIN
    ALTER TABLE Dim.Account ADD
        PrimaryColor              NVARCHAR(7)    NULL,
        PrimaryColor2             NVARCHAR(7)    NULL,
        SecondaryColor            NVARCHAR(7)    NULL,
        SecondaryColor2           NVARCHAR(7)    NULL,
        AccentColor               NVARCHAR(7)    NULL,
        TextOnPrimaryOverride     NVARCHAR(7)    NULL,
        TextOnSecondaryOverride   NVARCHAR(7)    NULL,
        LogoDataUrl               NVARCHAR(MAX)  NULL;
END;
GO

-- 2. Recreate App.vAccounts to expose the new branding columns
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
        -- Site count
        ISNULL(sites.SiteCount, 0)           AS SiteCount,
        -- User count (distinct users with any access grant to this account)
        ISNULL(users.UserCount, 0)           AS UserCount,
        -- Access policy count
        ISNULL(accPol.AccessPolicyCount, 0)  AS AccessPolicyCount,
        -- Package policy count
        ISNULL(pkgPol.PackagePolicyCount, 0) AS PackagePolicyCount,
        -- Total policy count
        ISNULL(accPol.AccessPolicyCount, 0) +
        ISNULL(pkgPol.PackagePolicyCount, 0) AS TotalPolicyCount,
        -- Branding
        a.PrimaryColor,
        a.PrimaryColor2,
        a.SecondaryColor,
        a.SecondaryColor2,
        a.AccentColor,
        a.TextOnPrimaryOverride,
        a.TextOnSecondaryOverride,
        a.LogoDataUrl
    FROM Dim.Account AS a
    -- Site count
    OUTER APPLY
    (
        SELECT COUNT(*) AS SiteCount
        FROM Dim.OrgUnit AS ou
        WHERE ou.AccountId = a.AccountId
          AND ou.OrgUnitType = 'Site'
          AND ou.IsActive = 1
    ) AS sites
    -- User count via access grants
    OUTER APPLY
    (
        SELECT COUNT(DISTINCT u.UserId) AS UserCount
        FROM Sec.vAuthorizedSitesDynamic AS auth
        JOIN Sec.[User] AS u ON u.UPN = auth.UserUPN
        WHERE auth.AccountId = a.AccountId
    ) AS users
    -- Access policy count
    OUTER APPLY
    (
        SELECT COUNT(*) AS AccessPolicyCount
        FROM Sec.AccountAccessPolicy AS pol
        WHERE pol.IsActive = 1
    ) AS accPol
    -- Package policy count
    OUTER APPLY
    (
        SELECT COUNT(*) AS PackagePolicyCount
        FROM Sec.AccountPackagePolicy AS pol
        WHERE pol.IsActive = 1
    ) AS pkgPol;
GO

-- 3. Add the branding-only update procedure
CREATE OR ALTER PROCEDURE App.UpdateAccountBranding
    @AccountId               INT,
    @PrimaryColor            NVARCHAR(7)    = NULL,
    @PrimaryColor2           NVARCHAR(7)    = NULL,
    @SecondaryColor          NVARCHAR(7)    = NULL,
    @SecondaryColor2         NVARCHAR(7)    = NULL,
    @AccentColor             NVARCHAR(7)    = NULL,
    @TextOnPrimaryOverride   NVARCHAR(7)    = NULL,
    @TextOnSecondaryOverride NVARCHAR(7)    = NULL,
    @LogoDataUrl             NVARCHAR(MAX)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE Dim.Account
    SET PrimaryColor             = @PrimaryColor,
        PrimaryColor2            = @PrimaryColor2,
        SecondaryColor           = @SecondaryColor,
        SecondaryColor2          = @SecondaryColor2,
        AccentColor              = @AccentColor,
        TextOnPrimaryOverride    = @TextOnPrimaryOverride,
        TextOnSecondaryOverride  = @TextOnSecondaryOverride,
        LogoDataUrl              = @LogoDataUrl,
        ModifiedOnUtc            = SYSUTCDATETIME(),
        ModifiedBy               = SESSION_USER
    WHERE AccountId = @AccountId;
END;
GO
