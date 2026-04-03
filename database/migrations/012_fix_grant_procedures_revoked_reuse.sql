/*
    Migration 012 — Fix Sec.Grant* procedures to handle previously-revoked grants

    Problem:
        All Grant procedures used an IF NOT EXISTS / NOT EXISTS pattern to guard
        against duplicate inserts.  That check scanned ALL rows including soft-deleted
        (RevokedAt IS NOT NULL) ones.  After migration 011 filtered revoked rows from
        App.vGrants / App.vPackageGrants, re-granting a previously-revoked access
        silently did nothing — the revoked row was found by the EXISTS check, the INSERT
        was skipped, and the view never showed the grant again.

    Fix:
        Replace the single-step IF NOT EXISTS … INSERT pattern with a two-step UPSERT:
          1. UPDATE any existing revoked row to clear RevokedAt (re-activates it).
          2. INSERT a fresh row only when no row (active OR revoked) exists for that
             combination, so we never violate unique constraints.

        This makes every Grant procedure idempotent across three states:
          • Active grant already exists  → no-op (UPDATE touches 0 rows, EXISTS guards INSERT).
          • Revoked grant exists         → re-activated via UPDATE, INSERT skipped.
          • No row exists at all         → INSERT as before.

    Procedures updated:
        Sec.GrantGlobalAllPackages
        Sec.GrantAllAccounts
        Sec.GrantGlobal
        Sec.GrantFullAccount
        Sec.GrantPathPrefix
        Sec.GrantCountryAllAccounts
*/

SET NOCOUNT ON;
GO

-- -----------------------------------------------------------------------
-- 1. Sec.GrantGlobalAllPackages
-- -----------------------------------------------------------------------
CREATE OR ALTER PROCEDURE Sec.GrantGlobalAllPackages
    @PrincipalType NVARCHAR(10),
    @PrincipalIdentifier NVARCHAR(320)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PrincipalId INT = Sec.fnResolvePrincipalId(@PrincipalType, @PrincipalIdentifier);
    IF @PrincipalId IS NULL
        THROW 50010, 'Principal not found for global all-packages grant.', 1;

    -- Re-activate a previously revoked row if one exists
    UPDATE Sec.PrincipalPackageGrant
    SET RevokedAt            = NULL,
        RevokedByPrincipalId = NULL,
        ModifiedOnUtc        = SYSUTCDATETIME(),
        ModifiedBy           = 'regrant'
    WHERE PrincipalId = @PrincipalId
      AND GrantScope   = 'ALL_PACKAGES'
      AND RevokedAt IS NOT NULL;

    -- Insert only when no row exists at all (active or revoked)
    IF @@ROWCOUNT = 0 AND NOT EXISTS (
        SELECT 1
        FROM Sec.PrincipalPackageGrant
        WHERE PrincipalId = @PrincipalId
          AND GrantScope   = 'ALL_PACKAGES'
    )
    BEGIN
        INSERT INTO Sec.PrincipalPackageGrant (PrincipalId, PackageId, GrantScope)
        VALUES (@PrincipalId, NULL, 'ALL_PACKAGES');
    END;
END;
GO

-- -----------------------------------------------------------------------
-- 2. Sec.GrantAllAccounts
-- -----------------------------------------------------------------------
CREATE OR ALTER PROCEDURE Sec.GrantAllAccounts
    @PrincipalType NVARCHAR(10),
    @PrincipalIdentifier NVARCHAR(320),
    @ActingPrincipalType NVARCHAR(10) = NULL,
    @ActingPrincipalIdentifier NVARCHAR(320) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PrincipalId INT = Sec.fnResolvePrincipalId(@PrincipalType, @PrincipalIdentifier);
    IF @PrincipalId IS NULL
        THROW 50019, 'Principal not found for all-accounts grant.', 1;

    DECLARE @ActingPrincipalId INT = NULL;
    IF @ActingPrincipalIdentifier IS NOT NULL
    BEGIN
        SET @ActingPrincipalType = COALESCE(@ActingPrincipalType, 'User');
        SET @ActingPrincipalId   = Sec.fnResolvePrincipalId(@ActingPrincipalType, @ActingPrincipalIdentifier);
        IF @ActingPrincipalId IS NULL
            THROW 50024, 'Acting principal not found for delegation.', 1;

        IF Sec.fnCanAdministerScope(@ActingPrincipalId, NULL, 'NONE', NULL) = 0
            THROW 50025, 'Acting principal lacks coverage to grant all accounts.', 1;
    END

    UPDATE Sec.PrincipalAccessGrant
    SET RevokedAt            = NULL,
        RevokedByPrincipalId = NULL,
        ModifiedOnUtc        = SYSUTCDATETIME(),
        ModifiedBy           = 'regrant'
    WHERE PrincipalId = @PrincipalId
      AND AccessType   = 'ALL'
      AND ScopeType    = 'NONE'
      AND RevokedAt IS NOT NULL;

    IF @@ROWCOUNT = 0 AND NOT EXISTS (
        SELECT 1
        FROM Sec.PrincipalAccessGrant
        WHERE PrincipalId = @PrincipalId
          AND AccessType   = 'ALL'
          AND ScopeType    = 'NONE'
    )
    BEGIN
        INSERT INTO Sec.PrincipalAccessGrant (PrincipalId, AccessType, ScopeType)
        VALUES (@PrincipalId, 'ALL', 'NONE');
    END;
END;
GO

-- -----------------------------------------------------------------------
-- 3. Sec.GrantGlobal
-- -----------------------------------------------------------------------
CREATE OR ALTER PROCEDURE Sec.GrantGlobal
    @PrincipalType NVARCHAR(10),
    @PrincipalIdentifier NVARCHAR(320),
    @PackageCode NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PrincipalId INT = Sec.fnResolvePrincipalId(@PrincipalType, @PrincipalIdentifier);
    IF @PrincipalId IS NULL
        THROW 50011, 'Principal not found for package grant.', 1;

    DECLARE @PackageId INT = (SELECT PackageId FROM Dim.Package WHERE PackageCode = @PackageCode);
    IF @PackageId IS NULL
        THROW 50012, 'Package not found for provided code.', 1;

    UPDATE Sec.PrincipalPackageGrant
    SET RevokedAt            = NULL,
        RevokedByPrincipalId = NULL,
        ModifiedOnUtc        = SYSUTCDATETIME(),
        ModifiedBy           = 'regrant'
    WHERE PrincipalId = @PrincipalId
      AND PackageId    = @PackageId
      AND GrantScope   = 'PACKAGE'
      AND RevokedAt IS NOT NULL;

    IF @@ROWCOUNT = 0 AND NOT EXISTS (
        SELECT 1
        FROM Sec.PrincipalPackageGrant
        WHERE PrincipalId = @PrincipalId
          AND PackageId    = @PackageId
          AND GrantScope   = 'PACKAGE'
    )
    BEGIN
        INSERT INTO Sec.PrincipalPackageGrant (PrincipalId, PackageId, GrantScope)
        VALUES (@PrincipalId, @PackageId, 'PACKAGE');
    END;
END;
GO

-- -----------------------------------------------------------------------
-- 4. Sec.GrantFullAccount
-- -----------------------------------------------------------------------
CREATE OR ALTER PROCEDURE Sec.GrantFullAccount
    @PrincipalType NVARCHAR(10),
    @PrincipalIdentifier NVARCHAR(320),
    @AccountCode NVARCHAR(50),
    @ActingPrincipalType NVARCHAR(10) = NULL,
    @ActingPrincipalIdentifier NVARCHAR(320) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PrincipalId INT = Sec.fnResolvePrincipalId(@PrincipalType, @PrincipalIdentifier);
    IF @PrincipalId IS NULL
        THROW 50013, 'Principal not found for account grant.', 1;

    DECLARE @AccountId INT = (SELECT AccountId FROM Dim.Account WHERE AccountCode = @AccountCode);
    IF @AccountId IS NULL
        THROW 50014, 'Account not found for provided code.', 1;

    DECLARE @ActingPrincipalId INT = NULL;
    IF @ActingPrincipalIdentifier IS NOT NULL
    BEGIN
        SET @ActingPrincipalType = COALESCE(@ActingPrincipalType, 'User');
        SET @ActingPrincipalId   = Sec.fnResolvePrincipalId(@ActingPrincipalType, @ActingPrincipalIdentifier);
        IF @ActingPrincipalId IS NULL
            THROW 50024, 'Acting principal not found for delegation.', 1;

        IF Sec.fnCanAdministerScope(@ActingPrincipalId, @AccountId, 'NONE', NULL) = 0
            THROW 50026, 'Acting principal lacks coverage to grant full account access.', 1;
    END

    UPDATE Sec.PrincipalAccessGrant
    SET RevokedAt            = NULL,
        RevokedByPrincipalId = NULL,
        ModifiedOnUtc        = SYSUTCDATETIME(),
        ModifiedBy           = 'regrant'
    WHERE PrincipalId = @PrincipalId
      AND AccessType   = 'ACCOUNT'
      AND AccountId    = @AccountId
      AND ScopeType    = 'NONE'
      AND RevokedAt IS NOT NULL;

    IF @@ROWCOUNT = 0 AND NOT EXISTS (
        SELECT 1
        FROM Sec.PrincipalAccessGrant
        WHERE PrincipalId = @PrincipalId
          AND AccessType   = 'ACCOUNT'
          AND AccountId    = @AccountId
          AND ScopeType    = 'NONE'
    )
    BEGIN
        INSERT INTO Sec.PrincipalAccessGrant (PrincipalId, AccessType, AccountId, ScopeType)
        VALUES (@PrincipalId, 'ACCOUNT', @AccountId, 'NONE');
    END;
END;
GO

-- -----------------------------------------------------------------------
-- 5. Sec.GrantPathPrefix
-- -----------------------------------------------------------------------
CREATE OR ALTER PROCEDURE Sec.GrantPathPrefix
    @PrincipalType NVARCHAR(10),
    @PrincipalIdentifier NVARCHAR(320),
    @AccountCode NVARCHAR(50),
    @OrgUnitType NVARCHAR(20),
    @OrgUnitCode NVARCHAR(50),
    @ActingPrincipalType NVARCHAR(10) = NULL,
    @ActingPrincipalIdentifier NVARCHAR(320) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PrincipalId INT = Sec.fnResolvePrincipalId(@PrincipalType, @PrincipalIdentifier);
    IF @PrincipalId IS NULL
        THROW 50015, 'Principal not found for org unit grant.', 1;

    DECLARE @AccountId INT = (SELECT AccountId FROM Dim.Account WHERE AccountCode = @AccountCode);
    IF @AccountId IS NULL
        THROW 50016, 'Account not found for provided code.', 1;

    DECLARE @OrgUnitId INT;
    SELECT @OrgUnitId = OrgUnitId
    FROM Dim.OrgUnit
    WHERE AccountId   = @AccountId
      AND OrgUnitType = @OrgUnitType
      AND OrgUnitCode = @OrgUnitCode;

    IF @OrgUnitId IS NULL
        THROW 50017, 'Org unit not found for provided parameters.', 1;

    DECLARE @ActingPrincipalId INT = NULL;
    IF @ActingPrincipalIdentifier IS NOT NULL
    BEGIN
        SET @ActingPrincipalType = COALESCE(@ActingPrincipalType, 'User');
        SET @ActingPrincipalId   = Sec.fnResolvePrincipalId(@ActingPrincipalType, @ActingPrincipalIdentifier);
        IF @ActingPrincipalId IS NULL
            THROW 50024, 'Acting principal not found for delegation.', 1;

        IF Sec.fnCanAdministerScope(@ActingPrincipalId, @AccountId, 'ORGUNIT', @OrgUnitId) = 0
            THROW 50027, 'Acting principal lacks coverage to grant this org unit.', 1;
    END

    UPDATE Sec.PrincipalAccessGrant
    SET RevokedAt            = NULL,
        RevokedByPrincipalId = NULL,
        ModifiedOnUtc        = SYSUTCDATETIME(),
        ModifiedBy           = 'regrant'
    WHERE PrincipalId             = @PrincipalId
      AND AccessType              = 'ACCOUNT'
      AND AccountId               = @AccountId
      AND ScopeType               = 'ORGUNIT'
      AND COALESCE(OrgUnitId, -1) = COALESCE(@OrgUnitId, -1)
      AND RevokedAt IS NOT NULL;

    IF @@ROWCOUNT = 0 AND NOT EXISTS (
        SELECT 1
        FROM Sec.PrincipalAccessGrant
        WHERE PrincipalId             = @PrincipalId
          AND AccessType              = 'ACCOUNT'
          AND AccountId               = @AccountId
          AND ScopeType               = 'ORGUNIT'
          AND COALESCE(OrgUnitId, -1) = COALESCE(@OrgUnitId, -1)
    )
    BEGIN
        INSERT INTO Sec.PrincipalAccessGrant (PrincipalId, AccessType, AccountId, ScopeType, OrgUnitId)
        VALUES (@PrincipalId, 'ACCOUNT', @AccountId, 'ORGUNIT', @OrgUnitId);
    END;
END;
GO

-- -----------------------------------------------------------------------
-- 6. Sec.GrantCountryAllAccounts
-- -----------------------------------------------------------------------
CREATE OR ALTER PROCEDURE Sec.GrantCountryAllAccounts
    @PrincipalType NVARCHAR(10),
    @PrincipalIdentifier NVARCHAR(320),
    @CountryCode NVARCHAR(10),
    @ActingPrincipalType NVARCHAR(10) = NULL,
    @ActingPrincipalIdentifier NVARCHAR(320) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PrincipalId INT = Sec.fnResolvePrincipalId(@PrincipalType, @PrincipalIdentifier);
    IF @PrincipalId IS NULL
        THROW 50018, 'Principal not found for country grant.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM Dim.OrgUnit
        WHERE OrgUnitType = 'Country'
          AND OrgUnitCode = @CountryCode
    )
        THROW 50021, 'Country org unit not found to support grant.', 1;

    DECLARE @ActingPrincipalId INT = NULL;
    IF @ActingPrincipalIdentifier IS NOT NULL
    BEGIN
        SET @ActingPrincipalType = COALESCE(@ActingPrincipalType, 'User');
        SET @ActingPrincipalId   = Sec.fnResolvePrincipalId(@ActingPrincipalType, @ActingPrincipalIdentifier);
        IF @ActingPrincipalId IS NULL
            THROW 50024, 'Acting principal not found for delegation.', 1;

        DECLARE @SampleCountryOrgUnitId INT;
        SELECT TOP (1) @SampleCountryOrgUnitId = OrgUnitId
        FROM Dim.OrgUnit
        WHERE OrgUnitType = 'Country'
          AND OrgUnitCode = @CountryCode
        ORDER BY OrgUnitId;

        IF Sec.fnCanAdministerScope(@ActingPrincipalId, NULL, 'NONE', NULL) = 0
           AND Sec.fnCanAdministerScope(@ActingPrincipalId, NULL, 'ORGUNIT', @SampleCountryOrgUnitId) = 0
           THROW 50028, 'Acting principal lacks coverage to grant this country across accounts.', 1;
    END

    -- Re-activate any previously revoked country grants for this principal
    UPDATE pag
    SET pag.RevokedAt            = NULL,
        pag.RevokedByPrincipalId = NULL,
        pag.ModifiedOnUtc        = SYSUTCDATETIME(),
        pag.ModifiedBy           = 'regrant'
    FROM Sec.PrincipalAccessGrant AS pag
    JOIN Dim.OrgUnit AS ou ON ou.OrgUnitId = pag.OrgUnitId
    WHERE pag.PrincipalId = @PrincipalId
      AND pag.AccessType  = 'ALL'
      AND pag.ScopeType   = 'ORGUNIT'
      AND ou.OrgUnitType  = 'Country'
      AND ou.OrgUnitCode  = @CountryCode
      AND pag.RevokedAt IS NOT NULL;

    -- Insert rows for any country org units that have no grant row at all
    INSERT INTO Sec.PrincipalAccessGrant (PrincipalId, AccessType, ScopeType, OrgUnitId)
    SELECT @PrincipalId, 'ALL', 'ORGUNIT', ou.OrgUnitId
    FROM Dim.OrgUnit AS ou
    WHERE ou.OrgUnitType = 'Country'
      AND ou.OrgUnitCode = @CountryCode
      AND NOT EXISTS (
            SELECT 1
            FROM Sec.PrincipalAccessGrant AS pag
            WHERE pag.PrincipalId = @PrincipalId
              AND pag.AccessType  = 'ALL'
              AND pag.ScopeType   = 'ORGUNIT'
              AND pag.OrgUnitId   = ou.OrgUnitId
        );
END;
GO

PRINT 'Migration 012: Sec.Grant* procedures now re-activate previously-revoked grants instead of silently skipping them.';
GO
