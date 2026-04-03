/*
    Create.sql
    DDL for centralized role-based security and reporting access to support scalable Power BI deployments.
    This script is idempotent; rerunning will only create missing objects.
*/
SET NOCOUNT ON;
GO

-- Ensure required schemas exist ---------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Dim')
    EXEC ('CREATE SCHEMA Dim AUTHORIZATION dbo;');
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Sec')
    EXEC ('CREATE SCHEMA Sec AUTHORIZATION dbo;');
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'App')
    EXEC ('CREATE SCHEMA App AUTHORIZATION dbo;');
GO

-- Dimensional tables --------------------------------------------------------------
IF OBJECT_ID('Dim.Account', 'U') IS NULL
BEGIN
    CREATE TABLE Dim.Account
    (
        AccountId      INT IDENTITY(1,1)      NOT NULL PRIMARY KEY,
        AccountCode    NVARCHAR(50)           NOT NULL,
        AccountName    NVARCHAR(200)          NOT NULL,
        IsActive       BIT                    NOT NULL CONSTRAINT DF_Account_IsActive DEFAULT (1),
        CreatedOnUtc   DATETIME2              NOT NULL CONSTRAINT DF_Account_Created DEFAULT (SYSUTCDATETIME()),
        ModifiedOnUtc  DATETIME2              NOT NULL CONSTRAINT DF_Account_Modified DEFAULT (SYSUTCDATETIME()),
        CreatedBy      NVARCHAR(128)          NOT NULL CONSTRAINT DF_Account_CreatedBy DEFAULT (SESSION_USER),
        ModifiedBy     NVARCHAR(128)          NOT NULL CONSTRAINT DF_Account_ModifiedBy DEFAULT (SESSION_USER)
    );

    CREATE UNIQUE INDEX UX_Account_Code ON Dim.Account (AccountCode);
END;
GO

IF OBJECT_ID('Dim.OrgUnit', 'U') IS NULL
BEGIN
    CREATE TABLE Dim.OrgUnit
    (
        OrgUnitId          INT IDENTITY(1,1)  NOT NULL PRIMARY KEY,
        AccountId          INT                NOT NULL,
        OrgUnitType        NVARCHAR(20)       NOT NULL,
        OrgUnitCode        NVARCHAR(50)       NOT NULL,
        OrgUnitName        NVARCHAR(200)      NOT NULL,
        ParentOrgUnitId    INT                NULL,
        Path               NVARCHAR(850)      NOT NULL,
        CountryCode        NVARCHAR(10)       NULL,
        IsActive           BIT                NOT NULL CONSTRAINT DF_OrgUnit_IsActive DEFAULT (1),
        CreatedOnUtc       DATETIME2          NOT NULL CONSTRAINT DF_OrgUnit_Created DEFAULT (SYSUTCDATETIME()),
        ModifiedOnUtc      DATETIME2          NOT NULL CONSTRAINT DF_OrgUnit_Modified DEFAULT (SYSUTCDATETIME()),
        CreatedBy          NVARCHAR(128)      NOT NULL CONSTRAINT DF_OrgUnit_CreatedBy DEFAULT (SESSION_USER),
        ModifiedBy         NVARCHAR(128)      NOT NULL CONSTRAINT DF_OrgUnit_ModifiedBy DEFAULT (SESSION_USER),
        CONSTRAINT FK_OrgUnit_Account FOREIGN KEY (AccountId) REFERENCES Dim.Account (AccountId),
        CONSTRAINT FK_OrgUnit_Parent FOREIGN KEY (ParentOrgUnitId) REFERENCES Dim.OrgUnit (OrgUnitId)
    );

    ALTER TABLE Dim.OrgUnit
        ADD CONSTRAINT CK_OrgUnit_Type CHECK (OrgUnitType IN ('Division','Country','Site','Region','Branch','Area','Territory'));

    CREATE UNIQUE INDEX UX_OrgUnit_Path ON Dim.OrgUnit (Path);
    CREATE UNIQUE INDEX UX_OrgUnit_CodePerAccount ON Dim.OrgUnit (AccountId, OrgUnitType, OrgUnitCode);
    CREATE INDEX IX_OrgUnit_Parent ON Dim.OrgUnit (ParentOrgUnitId);
    CREATE INDEX IX_OrgUnit_CountryCode ON Dim.OrgUnit (CountryCode) WHERE CountryCode IS NOT NULL;
END;
GO

IF OBJECT_ID('Dim.OrgUnitSourceMap', 'U') IS NULL
BEGIN
    CREATE TABLE Dim.OrgUnitSourceMap
    (
        OrgUnitSourceMapId INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        OrgUnitId          INT             NOT NULL,
        SourceSystem       NVARCHAR(100)   NOT NULL,
        SourceOrgUnitId    NVARCHAR(100)   NOT NULL,
        SourceOrgUnitName  NVARCHAR(200)   NULL,
        IsActive           BIT             NOT NULL CONSTRAINT DF_OrgUnitSourceMap_IsActive DEFAULT (1),
        CreatedOnUtc       DATETIME2       NOT NULL CONSTRAINT DF_OrgUnitSourceMap_Created DEFAULT (SYSUTCDATETIME()),
        ModifiedOnUtc      DATETIME2       NOT NULL CONSTRAINT DF_OrgUnitSourceMap_Modified DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_OrgUnitSourceMap_OrgUnit FOREIGN KEY (OrgUnitId) REFERENCES Dim.OrgUnit (OrgUnitId)
    );

    CREATE UNIQUE INDEX UX_OrgUnitSourceMap_Source
        ON Dim.OrgUnitSourceMap (SourceSystem, SourceOrgUnitId);

    CREATE INDEX IX_OrgUnitSourceMap_OrgUnit
        ON Dim.OrgUnitSourceMap (OrgUnitId);
END;
GO

IF OBJECT_ID('Dim.Package', 'U') IS NULL
BEGIN
    CREATE TABLE Dim.Package
    (
        PackageId      INT IDENTITY(1,1)      NOT NULL PRIMARY KEY,
        PackageCode    NVARCHAR(50)           NOT NULL,
        PackageName    NVARCHAR(200)          NOT NULL,
        PackageGroup   NVARCHAR(100)          NULL,
        IsActive       BIT                    NOT NULL CONSTRAINT DF_Package_IsActive DEFAULT (1),
        CreatedOnUtc   DATETIME2              NOT NULL CONSTRAINT DF_Package_Created DEFAULT (SYSUTCDATETIME()),
        ModifiedOnUtc  DATETIME2              NOT NULL CONSTRAINT DF_Package_Modified DEFAULT (SYSUTCDATETIME()),
        CreatedBy      NVARCHAR(128)          NOT NULL CONSTRAINT DF_Package_CreatedBy DEFAULT (SESSION_USER),
        ModifiedBy     NVARCHAR(128)          NOT NULL CONSTRAINT DF_Package_ModifiedBy DEFAULT (SESSION_USER)
    );

    CREATE UNIQUE INDEX UX_Package_Code ON Dim.Package (PackageCode);
END;
GO

IF OBJECT_ID('Dim.BiReport', 'U') IS NULL
BEGIN
    CREATE TABLE Dim.BiReport
    (
        BiReportId     INT IDENTITY(1,1)      NOT NULL PRIMARY KEY,
        ReportCode     NVARCHAR(100)          NOT NULL,
        ReportName     NVARCHAR(200)          NOT NULL,
        ReportUri      NVARCHAR(500)          NULL,
        IsActive       BIT                    NOT NULL CONSTRAINT DF_BiReport_IsActive DEFAULT (1),
        CreatedOnUtc   DATETIME2              NOT NULL CONSTRAINT DF_BiReport_Created DEFAULT (SYSUTCDATETIME()),
        ModifiedOnUtc  DATETIME2              NOT NULL CONSTRAINT DF_BiReport_Modified DEFAULT (SYSUTCDATETIME()),
        CreatedBy      NVARCHAR(128)          NOT NULL CONSTRAINT DF_BiReport_CreatedBy DEFAULT (SESSION_USER),
        ModifiedBy     NVARCHAR(128)          NOT NULL CONSTRAINT DF_BiReport_ModifiedBy DEFAULT (SESSION_USER)
    );

    CREATE UNIQUE INDEX UX_BiReport_Code ON Dim.BiReport (ReportCode);
END;
GO

IF OBJECT_ID('Dim.BiReportPackage', 'U') IS NULL
BEGIN
    CREATE TABLE Dim.BiReportPackage
    (
        BiReportId INT NOT NULL,
        PackageId  INT NOT NULL,
        CreatedOnUtc   DATETIME2 NOT NULL CONSTRAINT DF_ReportPackage_Created DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_BiReportPackage PRIMARY KEY (BiReportId, PackageId),
        CONSTRAINT FK_ReportPackage_Report FOREIGN KEY (BiReportId) REFERENCES Dim.BiReport (BiReportId),
        CONSTRAINT FK_ReportPackage_Package FOREIGN KEY (PackageId) REFERENCES Dim.Package (PackageId)
    );
END;
GO

-- Security principals -------------------------------------------------------------
IF OBJECT_ID('Sec.Principal', 'U') IS NULL
BEGIN
    CREATE TABLE Sec.Principal
    (
        PrincipalId    INT IDENTITY(1,1)      NOT NULL PRIMARY KEY,
        PrincipalType  NVARCHAR(10)           NOT NULL,
        PrincipalName  NVARCHAR(200)          NOT NULL,
        IsActive       BIT                    NOT NULL CONSTRAINT DF_Principal_IsActive DEFAULT (1),
        CreatedOnUtc   DATETIME2              NOT NULL CONSTRAINT DF_Principal_Created DEFAULT (SYSUTCDATETIME()),
        ModifiedOnUtc  DATETIME2              NOT NULL CONSTRAINT DF_Principal_Modified DEFAULT (SYSUTCDATETIME()),
        CreatedBy      NVARCHAR(128)          NOT NULL CONSTRAINT DF_Principal_CreatedBy DEFAULT (SESSION_USER),
        ModifiedBy     NVARCHAR(128)          NOT NULL CONSTRAINT DF_Principal_ModifiedBy DEFAULT (SESSION_USER)
    );

    ALTER TABLE Sec.Principal
        ADD CONSTRAINT CK_Principal_Type CHECK (PrincipalType IN ('User','Role'));

    CREATE UNIQUE INDEX UX_Principal_Name ON Sec.Principal (PrincipalName, PrincipalType);
END;
GO

IF OBJECT_ID('Sec.[User]', 'U') IS NULL
BEGIN
    CREATE TABLE Sec.[User]
    (
        UserId          INT             NOT NULL PRIMARY KEY,
        UPN             NVARCHAR(320)   NOT NULL,
        DisplayName     NVARCHAR(200)   NULL,
        CreatedOnUtc    DATETIME2       NOT NULL CONSTRAINT DF_User_Created DEFAULT (SYSUTCDATETIME()),
        ModifiedOnUtc   DATETIME2       NOT NULL CONSTRAINT DF_User_Modified DEFAULT (SYSUTCDATETIME()),
        CreatedBy       NVARCHAR(128)   NOT NULL CONSTRAINT DF_User_CreatedBy DEFAULT (SESSION_USER),
        ModifiedBy      NVARCHAR(128)   NOT NULL CONSTRAINT DF_User_ModifiedBy DEFAULT (SESSION_USER),
        CONSTRAINT FK_User_Principal FOREIGN KEY (UserId) REFERENCES Sec.Principal (PrincipalId)
    );

    CREATE UNIQUE INDEX UX_User_UPN ON Sec.[User] (UPN);
END;
GO

IF OBJECT_ID('Sec.Role', 'U') IS NULL
BEGIN
    CREATE TABLE Sec.Role
    (
        RoleId          INT             NOT NULL PRIMARY KEY,
        RoleCode        NVARCHAR(100)   NOT NULL,
        RoleName        NVARCHAR(200)   NOT NULL,
        Description     NVARCHAR(400)   NULL,
        CreatedOnUtc    DATETIME2       NOT NULL CONSTRAINT DF_Role_Created DEFAULT (SYSUTCDATETIME()),
        ModifiedOnUtc   DATETIME2       NOT NULL CONSTRAINT DF_Role_Modified DEFAULT (SYSUTCDATETIME()),
        CreatedBy       NVARCHAR(128)   NOT NULL CONSTRAINT DF_Role_CreatedBy DEFAULT (SESSION_USER),
        ModifiedBy      NVARCHAR(128)   NOT NULL CONSTRAINT DF_Role_ModifiedBy DEFAULT (SESSION_USER),
        CONSTRAINT FK_Role_Principal FOREIGN KEY (RoleId) REFERENCES Sec.Principal (PrincipalId)
    );

    CREATE UNIQUE INDEX UX_Role_Code ON Sec.Role (RoleCode);
END;
GO

IF OBJECT_ID('Sec.RoleMembership', 'U') IS NULL
BEGIN
    CREATE TABLE Sec.RoleMembership
    (
        RoleId              INT NOT NULL,
        MemberPrincipalId   INT NOT NULL,
        AddedOnUtc          DATETIME2 NOT NULL CONSTRAINT DF_RoleMembership_Added DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_RoleMembership PRIMARY KEY (RoleId, MemberPrincipalId),
        CONSTRAINT FK_RoleMembership_Role FOREIGN KEY (RoleId) REFERENCES Sec.Role (RoleId),
        CONSTRAINT FK_RoleMembership_User FOREIGN KEY (MemberPrincipalId) REFERENCES Sec.[User] (UserId)
    );
END;
GO

-- Grant tables --------------------------------------------------------------------
IF OBJECT_ID('Sec.PrincipalPackageGrant', 'U') IS NULL
BEGIN
    CREATE TABLE Sec.PrincipalPackageGrant
    (
        PrincipalPackageGrantId INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        PrincipalId     INT             NOT NULL,
        PackageId       INT             NULL,
        GrantScope      NVARCHAR(30)    NOT NULL,
        GrantedOnUtc    DATETIME2       NOT NULL CONSTRAINT DF_PrincipalPackageGrant_Created DEFAULT (SYSUTCDATETIME()),
        CreatedBy       NVARCHAR(128)   NOT NULL CONSTRAINT DF_PrincipalPackageGrant_CreatedBy DEFAULT (SESSION_USER),
        ModifiedBy      NVARCHAR(128)   NOT NULL CONSTRAINT DF_PrincipalPackageGrant_ModifiedBy DEFAULT (SESSION_USER),
        CONSTRAINT FK_PackageGrant_Principal FOREIGN KEY (PrincipalId) REFERENCES Sec.Principal (PrincipalId),
        CONSTRAINT FK_PackageGrant_Package FOREIGN KEY (PackageId) REFERENCES Dim.Package (PackageId),
        CONSTRAINT CK_PackageGrant_Scope CHECK (GrantScope IN ('ALL_PACKAGES','PACKAGE')),
        CONSTRAINT CK_PackageGrant_Package CHECK ((GrantScope = 'ALL_PACKAGES' AND PackageId IS NULL) OR (GrantScope = 'PACKAGE' AND PackageId IS NOT NULL))
    );

    CREATE UNIQUE INDEX UX_PackageGrant ON Sec.PrincipalPackageGrant (PrincipalId, GrantScope, PackageId);
END;
GO

IF OBJECT_ID('Sec.PrincipalAccessGrant', 'U') IS NULL
BEGIN
    CREATE TABLE Sec.PrincipalAccessGrant
    (
        PrincipalAccessGrantId INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        PrincipalId     INT             NOT NULL,
        AccessType      NVARCHAR(10)    NOT NULL, -- ALL or ACCOUNT
        AccountId       INT             NULL,
        ScopeType       NVARCHAR(15)    NOT NULL, -- NONE, ORGUNIT
        OrgUnitId       INT             NULL,
        GrantedOnUtc    DATETIME2       NOT NULL CONSTRAINT DF_PrincipalAccessGrant_Created DEFAULT (SYSUTCDATETIME()),
        CreatedBy       NVARCHAR(128)   NOT NULL CONSTRAINT DF_PrincipalAccessGrant_CreatedBy DEFAULT (SESSION_USER),
        ModifiedBy      NVARCHAR(128)   NOT NULL CONSTRAINT DF_PrincipalAccessGrant_ModifiedBy DEFAULT (SESSION_USER),
        CONSTRAINT FK_PrincipalAccessGrant_Principal FOREIGN KEY (PrincipalId) REFERENCES Sec.Principal (PrincipalId),
        CONSTRAINT FK_PrincipalAccessGrant_Account FOREIGN KEY (AccountId) REFERENCES Dim.Account (AccountId),
        CONSTRAINT FK_PrincipalAccessGrant_OrgUnit FOREIGN KEY (OrgUnitId) REFERENCES Dim.OrgUnit (OrgUnitId),
        CONSTRAINT CK_PrincipalAccessGrant_AccessType CHECK (AccessType IN ('ALL','ACCOUNT')),
        CONSTRAINT CK_PrincipalAccessGrant_ScopeType CHECK (ScopeType IN ('NONE','ORGUNIT')),
        CONSTRAINT CK_PrincipalAccessGrant_AllAccount CHECK ((AccessType = 'ALL' AND AccountId IS NULL) OR (AccessType = 'ACCOUNT' AND AccountId IS NOT NULL)),
        CONSTRAINT CK_PrincipalAccessGrant_ScopeFields CHECK (
            (ScopeType = 'NONE'     AND OrgUnitId IS NULL) OR
            (ScopeType = 'ORGUNIT'  AND OrgUnitId IS NOT NULL)
        )
    );

    CREATE INDEX IX_PrincipalAccessGrant_Principal ON Sec.PrincipalAccessGrant (PrincipalId);
    CREATE INDEX IX_PrincipalAccessGrant_Scope ON Sec.PrincipalAccessGrant (ScopeType, OrgUnitId);
END;
GO

IF OBJECT_ID('Sec.PrincipalDelegation', 'U') IS NULL
BEGIN
    CREATE TABLE Sec.PrincipalDelegation
    (
        PrincipalDelegationId INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        DelegatorPrincipalId  INT             NOT NULL,
        DelegatePrincipalId   INT             NOT NULL,
        AccessType            NVARCHAR(10)    NOT NULL,
        AccountId             INT             NULL,
        ScopeType             NVARCHAR(15)    NOT NULL,
        OrgUnitId             INT             NULL,
        IsActive              BIT             NOT NULL CONSTRAINT DF_PrincipalDelegation_IsActive DEFAULT (1),
        CreatedOnUtc          DATETIME2       NOT NULL CONSTRAINT DF_PrincipalDelegation_Created DEFAULT (SYSUTCDATETIME()),
        ModifiedOnUtc         DATETIME2       NOT NULL CONSTRAINT DF_PrincipalDelegation_Modified DEFAULT (SYSUTCDATETIME()),
        CreatedBy             NVARCHAR(128)   NOT NULL CONSTRAINT DF_PrincipalDelegation_CreatedBy DEFAULT (SESSION_USER),
        ModifiedBy            NVARCHAR(128)   NOT NULL CONSTRAINT DF_PrincipalDelegation_ModifiedBy DEFAULT (SESSION_USER),
        CONSTRAINT FK_PrincipalDelegation_Delegator FOREIGN KEY (DelegatorPrincipalId) REFERENCES Sec.Principal (PrincipalId),
        CONSTRAINT FK_PrincipalDelegation_Delegate FOREIGN KEY (DelegatePrincipalId) REFERENCES Sec.Principal (PrincipalId),
        CONSTRAINT FK_PrincipalDelegation_Account FOREIGN KEY (AccountId) REFERENCES Dim.Account (AccountId),
        CONSTRAINT FK_PrincipalDelegation_OrgUnit FOREIGN KEY (OrgUnitId) REFERENCES Dim.OrgUnit (OrgUnitId),
        CONSTRAINT CK_PrincipalDelegation_AccessType CHECK (AccessType IN ('ALL','ACCOUNT')),
        CONSTRAINT CK_PrincipalDelegation_ScopeType CHECK (ScopeType IN ('NONE','ORGUNIT')),
        CONSTRAINT CK_PrincipalDelegation_ScopeFields CHECK (
            (ScopeType = 'NONE'    AND OrgUnitId IS NULL) OR
            (ScopeType = 'ORGUNIT' AND OrgUnitId IS NOT NULL)
        ),
        CONSTRAINT CK_PrincipalDelegation_Self CHECK (DelegatorPrincipalId <> DelegatePrincipalId)
    );

    CREATE UNIQUE INDEX UX_PrincipalDelegation_Scope
        ON Sec.PrincipalDelegation (DelegatorPrincipalId, DelegatePrincipalId, AccessType, AccountId, ScopeType, OrgUnitId)
        WHERE IsActive = 1;

    CREATE INDEX IX_PrincipalDelegation_Delegate
        ON Sec.PrincipalDelegation (DelegatePrincipalId, IsActive);
END;
GO

IF OBJECT_ID('Sec.AccountRolePolicy', 'U') IS NULL
BEGIN
  CREATE TABLE Sec.AccountRolePolicy
  (
      AccountRolePolicyId INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
      PolicyName          NVARCHAR(200) NOT NULL,
      -- Templates support tokens: {AccountCode} and {AccountName}
      RoleCodeTemplate    NVARCHAR(100) NOT NULL,  -- e.g. '{AccountCode}_GAD'
      RoleNameTemplate    NVARCHAR(200) NOT NULL,  -- e.g. '{AccountName} Global Account Director'
      ScopeType           NVARCHAR(15)  NOT NULL CONSTRAINT CK_AccRolePolicy_Scope CHECK (ScopeType IN ('NONE','ORGUNIT')),
      OrgUnitType         NVARCHAR(20)  NULL,      -- for ORGUNIT mode (future)
      OrgUnitCode         NVARCHAR(50)  NULL,
      IsActive            BIT NOT NULL CONSTRAINT DF_AccRolePolicy_IsActive DEFAULT(1),
      CreatedOnUtc        DATETIME2 NOT NULL CONSTRAINT DF_AccRolePolicy_Created DEFAULT (SYSUTCDATETIME()),
      ModifiedOnUtc       DATETIME2 NOT NULL CONSTRAINT DF_AccRolePolicy_Mod DEFAULT (SYSUTCDATETIME())
  );

  CREATE UNIQUE INDEX UX_AccountRolePolicy_Unique
    ON Sec.AccountRolePolicy (RoleCodeTemplate, ScopeType, OrgUnitType, OrgUnitCode)
    WHERE IsActive = 1;
END;
GO

IF OBJECT_ID('Sec.AccountAccessPolicy', 'U') IS NULL
BEGIN
    CREATE TABLE Sec.AccountAccessPolicy
    (
        AccountAccessPolicyId INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        PolicyName     NVARCHAR(200)   NOT NULL,
        PrincipalId    INT             NOT NULL,
        ScopeType      NVARCHAR(15)    NOT NULL, -- NONE or ORGUNIT
        OrgUnitType    NVARCHAR(20)    NULL,
        OrgUnitCode    NVARCHAR(50)    NULL,
        IsActive       BIT             NOT NULL CONSTRAINT DF_AccountAccessPolicy_IsActive DEFAULT (1),
        CreatedOnUtc   DATETIME2       NOT NULL CONSTRAINT DF_AccountAccessPolicy_Created DEFAULT (SYSUTCDATETIME()),
        ModifiedOnUtc  DATETIME2       NOT NULL CONSTRAINT DF_AccountAccessPolicy_Modified DEFAULT (SYSUTCDATETIME()),
        CreatedBy      NVARCHAR(128)   NOT NULL CONSTRAINT DF_AccountAccessPolicy_CreatedBy DEFAULT (SESSION_USER),
        ModifiedBy     NVARCHAR(128)   NOT NULL CONSTRAINT DF_AccountAccessPolicy_ModifiedBy DEFAULT (SESSION_USER),
        CONSTRAINT FK_AccountAccessPolicy_Principal FOREIGN KEY (PrincipalId) REFERENCES Sec.Principal (PrincipalId),
        CONSTRAINT CK_AccountAccessPolicy_ScopeType CHECK (ScopeType IN ('NONE','ORGUNIT')),
        CONSTRAINT CK_AccountAccessPolicy_ScopeFields CHECK (
            (ScopeType = 'NONE'    AND OrgUnitType IS NULL AND OrgUnitCode IS NULL) OR
            (ScopeType = 'ORGUNIT' AND OrgUnitType IS NOT NULL AND OrgUnitCode IS NOT NULL)
        )
    );

    CREATE UNIQUE INDEX UX_AccountAccessPolicy_PrincipalScope
        ON Sec.AccountAccessPolicy (PrincipalId, ScopeType, OrgUnitType, OrgUnitCode);
END;
GO

IF OBJECT_ID('Sec.AccountPackagePolicy', 'U') IS NULL
BEGIN
    CREATE TABLE Sec.AccountPackagePolicy
    (
        AccountPackagePolicyId INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        PolicyName      NVARCHAR(200)   NOT NULL,
        PrincipalId     INT             NOT NULL,
        GrantScope      NVARCHAR(30)    NOT NULL, -- ALL_PACKAGES or PACKAGE
        PackageCode     NVARCHAR(50)    NULL,
        IsActive        BIT             NOT NULL CONSTRAINT DF_AccountPackagePolicy_IsActive DEFAULT (1),
        CreatedOnUtc    DATETIME2       NOT NULL CONSTRAINT DF_AccountPackagePolicy_Created DEFAULT (SYSUTCDATETIME()),
        ModifiedOnUtc   DATETIME2       NOT NULL CONSTRAINT DF_AccountPackagePolicy_Modified DEFAULT (SYSUTCDATETIME()),
        CreatedBy       NVARCHAR(128)   NOT NULL CONSTRAINT DF_AccountPackagePolicy_CreatedBy DEFAULT (SESSION_USER),
        ModifiedBy      NVARCHAR(128)   NOT NULL CONSTRAINT DF_AccountPackagePolicy_ModifiedBy DEFAULT (SESSION_USER),
        CONSTRAINT FK_AccountPackagePolicy_Principal FOREIGN KEY (PrincipalId) REFERENCES Sec.Principal (PrincipalId),
        CONSTRAINT CK_AccountPackagePolicy_GrantScope CHECK (GrantScope IN ('ALL_PACKAGES','PACKAGE')),
        CONSTRAINT CK_AccountPackagePolicy_Package CHECK (
            (GrantScope = 'ALL_PACKAGES' AND PackageCode IS NULL) OR
            (GrantScope = 'PACKAGE' AND PackageCode IS NOT NULL)
        )
    );

    CREATE UNIQUE INDEX UX_AccountPackagePolicy_PrincipalScope
        ON Sec.AccountPackagePolicy (PrincipalId, GrantScope, PackageCode);
END;
GO

-- Helper views for effective access ------------------------------------------------
IF OBJECT_ID('Sec.vPrincipalEffectiveAccess', 'V') IS NOT NULL
    DROP VIEW Sec.vPrincipalEffectiveAccess;
GO
CREATE VIEW Sec.vPrincipalEffectiveAccess
AS
    SELECT
        pag.PrincipalId,
        pag.AccessType,
        pag.AccountId,
        pag.ScopeType,
        pag.OrgUnitId
    FROM Sec.PrincipalAccessGrant AS pag
    UNION ALL
    SELECT
        del.DelegatePrincipalId,
        del.AccessType,
        del.AccountId,
        del.ScopeType,
        del.OrgUnitId
    FROM Sec.PrincipalDelegation AS del
    WHERE del.IsActive = 1;
GO

IF OBJECT_ID('Sec.fnCanAdministerScope', 'FN') IS NOT NULL
    DROP FUNCTION Sec.fnCanAdministerScope;
GO
CREATE FUNCTION Sec.fnCanAdministerScope
(
    @PrincipalId INT,
    @AccountId   INT = NULL,
    @ScopeType   NVARCHAR(15),
    @OrgUnitId   INT = NULL
)
RETURNS BIT
AS
BEGIN
    DECLARE @Result BIT = 0;

    IF @PrincipalId IS NULL
        RETURN 0;

    IF @ScopeType = 'NONE'
    BEGIN
        IF @AccountId IS NULL
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM Sec.vPrincipalEffectiveAccess AS eff
                WHERE eff.PrincipalId = @PrincipalId
                  AND eff.AccessType = 'ALL'
                  AND eff.ScopeType = 'NONE'
            )
                SET @Result = 1;
        END
        ELSE
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM Sec.vPrincipalEffectiveAccess AS eff
                WHERE eff.PrincipalId = @PrincipalId
                  AND (
                        (eff.AccessType = 'ALL' AND eff.ScopeType = 'NONE')
                     OR (eff.AccessType = 'ACCOUNT' AND eff.ScopeType = 'NONE' AND eff.AccountId = @AccountId)
                  )
            )
                SET @Result = 1;
        END
    END
    ELSE IF @ScopeType = 'ORGUNIT'
    BEGIN
        DECLARE @TargetAccountId INT = @AccountId;
        DECLARE @TargetPath NVARCHAR(850);

        SELECT
            @TargetAccountId = COALESCE(@TargetAccountId, ou.AccountId),
            @TargetPath = ou.Path
        FROM Dim.OrgUnit AS ou
        WHERE ou.OrgUnitId = @OrgUnitId;

        IF EXISTS (
            SELECT 1
            FROM Sec.vPrincipalEffectiveAccess AS eff
            LEFT JOIN Dim.OrgUnit AS effOrg ON eff.OrgUnitId = effOrg.OrgUnitId
            WHERE eff.PrincipalId = @PrincipalId
              AND (
                    (eff.AccessType = 'ALL' AND eff.ScopeType = 'NONE')
                 OR (eff.AccessType = 'ACCOUNT' AND eff.ScopeType = 'NONE' AND eff.AccountId = @TargetAccountId)
                 OR (eff.AccessType = 'ACCOUNT' AND eff.ScopeType = 'ORGUNIT' AND eff.AccountId = @TargetAccountId
                     AND effOrg.Path IS NOT NULL AND @TargetPath LIKE effOrg.Path + '%')
                 OR (eff.AccessType = 'ALL' AND eff.ScopeType = 'ORGUNIT'
                     AND effOrg.Path IS NOT NULL AND @TargetPath LIKE effOrg.Path + '%')
                 )
        )
            SET @Result = 1;
    END

    RETURN @Result;
END;
GO

IF OBJECT_ID('Sec.vUserGrantPrincipals', 'V') IS NOT NULL
    DROP VIEW Sec.vUserGrantPrincipals;
GO
CREATE VIEW Sec.vUserGrantPrincipals
AS
    -- Each user is always their own principal; roles extend their effective principals.
    SELECT
        u.UserId        AS UserPrincipalId,
        u.UserId        AS GrantPrincipalId
    FROM Sec.[User] AS u
    UNION
    SELECT
        rm.MemberPrincipalId AS UserPrincipalId,
        rm.RoleId            AS GrantPrincipalId
    FROM Sec.RoleMembership AS rm;
GO

IF OBJECT_ID('Sec.vPrincipalPackageAccess', 'V') IS NOT NULL
    DROP VIEW Sec.vPrincipalPackageAccess;
GO
CREATE VIEW Sec.vPrincipalPackageAccess
AS
    -- Resolves effective package access per principal, expanding ALL_PACKAGES grants.
    WITH Expanded AS
    (
        SELECT
            ppg.PrincipalId,
            pkg.PackageId,
            pkg.PackageCode,
            pkg.PackageName,
            ppg.GrantScope
        FROM Sec.PrincipalPackageGrant AS ppg
        CROSS APPLY
        (
            SELECT p.PackageId, p.PackageCode, p.PackageName
            FROM Dim.Package AS p
            WHERE (ppg.GrantScope = 'ALL_PACKAGES' AND p.IsActive = 1)
               OR (ppg.GrantScope = 'PACKAGE' AND p.PackageId = ppg.PackageId AND p.IsActive = 1)
        ) AS pkg
    )
    SELECT DISTINCT
        PrincipalId,
        PackageId,
        PackageCode,
        PackageName,
        GrantScope
    FROM Expanded;
GO

IF OBJECT_ID('Sec.vAuthorizedSitesDynamic', 'V') IS NOT NULL
    DROP VIEW Sec.vAuthorizedSitesDynamic;
GO
CREATE VIEW Sec.vAuthorizedSitesDynamic
AS
    -- Expands effective site-level grants per user, honoring access + scope combinations.
    WITH Grants AS
    (
        SELECT
            up.UserPrincipalId,
            pag.AccessType,
            pag.AccountId,
            pag.ScopeType,
            pag.OrgUnitId
        FROM Sec.vUserGrantPrincipals AS up
        JOIN Sec.PrincipalAccessGrant AS pag
            ON up.GrantPrincipalId = pag.PrincipalId
    ),
    ScopeNone AS
    (
        SELECT DISTINCT
            g.UserPrincipalId,
            site.OrgUnitId
        FROM Grants AS g
        JOIN Dim.OrgUnit AS site
            ON site.OrgUnitType = 'Site'
        WHERE g.ScopeType = 'NONE'
          AND (
                g.AccessType = 'ALL'
             OR (g.AccessType = 'ACCOUNT' AND site.AccountId = g.AccountId)
          )
    ),
    ScopeOrgUnit AS
    (
        SELECT DISTINCT
            g.UserPrincipalId,
            site.OrgUnitId
        FROM Grants AS g
        JOIN Dim.OrgUnit AS base
            ON g.OrgUnitId = base.OrgUnitId
        JOIN Dim.OrgUnit AS site
            ON site.OrgUnitType = 'Site'
           AND site.Path LIKE base.Path + '%'
        WHERE g.ScopeType = 'ORGUNIT'
          AND (
                g.AccessType = 'ALL'
             OR (g.AccessType = 'ACCOUNT' AND site.AccountId = g.AccountId)
          )
    ),
    Expanded AS
    (
        SELECT * FROM ScopeNone
        UNION
        SELECT * FROM ScopeOrgUnit
    )
    SELECT
        u.UserId                    AS UserPrincipalId,
        u.UPN                       AS UserUPN,
        acct.AccountId,
        acct.AccountCode,
        acct.AccountName,
        site.OrgUnitId              AS SiteOrgUnitId,
        site.OrgUnitCode            AS SiteCode,
        site.OrgUnitName            AS SiteName,
        site.CountryCode,
        site.Path,
        map.SourceSystem,
        map.SourceOrgUnitId,
        map.SourceOrgUnitName
    FROM Expanded AS es
    JOIN Sec.[User] AS u
        ON es.UserPrincipalId = u.UserId
    JOIN Dim.OrgUnit AS site
        ON es.OrgUnitId = site.OrgUnitId
    JOIN Dim.Account AS acct
        ON site.AccountId = acct.AccountId
    LEFT JOIN Dim.OrgUnitSourceMap AS map
        ON map.OrgUnitId = site.OrgUnitId
       AND map.IsActive = 1;
GO

IF OBJECT_ID('Sec.vAuthorizedReportsDynamic', 'V') IS NOT NULL
    DROP VIEW Sec.vAuthorizedReportsDynamic;
GO
CREATE VIEW Sec.vAuthorizedReportsDynamic
AS
    -- Calculates every BI report a given user can access after package inheritance.
    SELECT DISTINCT
        u.UserId            AS UserPrincipalId,
        u.UPN               AS UserUPN,
        pkg.PackageId,
        pkg.PackageCode,
        pkg.PackageName,
        br.BiReportId,
        br.ReportCode,
        br.ReportName
    FROM Sec.vUserGrantPrincipals AS up
    JOIN Sec.vPrincipalPackageAccess AS pkg
        ON up.GrantPrincipalId = pkg.PrincipalId
    JOIN Sec.[User] AS u
        ON up.UserPrincipalId = u.UserId
    JOIN Dim.BiReportPackage AS brp
        ON pkg.PackageId = brp.PackageId
    JOIN Dim.BiReport AS br
        ON brp.BiReportId = br.BiReportId
    WHERE br.IsActive = 1;
GO

IF OBJECT_ID('Sec.vUserCoverageSummary', 'V') IS NOT NULL
    DROP VIEW Sec.vUserCoverageSummary;
GO
CREATE VIEW Sec.vUserCoverageSummary
AS
    SELECT
        u.UserId,
        u.UPN,
        ISNULL(reportSummary.PackageCount, 0) AS PackageCount,
        ISNULL(reportSummary.ReportCount, 0)  AS ReportCount,
        ISNULL(siteSummary.SiteCount, 0)      AS SiteCount,
        ISNULL(siteSummary.AccountCount, 0)   AS AccountCount
    FROM Sec.[User] AS u
    OUTER APPLY
    (
        SELECT
            COUNT(DISTINCT r.PackageId) AS PackageCount,
            COUNT(DISTINCT r.BiReportId) AS ReportCount
        FROM Sec.vAuthorizedReportsDynamic AS r
        WHERE r.UserPrincipalId = u.UserId
    ) AS reportSummary
    OUTER APPLY
    (
        SELECT
            COUNT(DISTINCT s.SiteOrgUnitId) AS SiteCount,
            COUNT(DISTINCT s.AccountId)     AS AccountCount
        FROM Sec.vAuthorizedSitesDynamic AS s
        WHERE s.UserPrincipalId = u.UserId
    ) AS siteSummary;
GO

IF OBJECT_ID('Sec.vUserAccessGaps', 'V') IS NOT NULL
    DROP VIEW Sec.vUserAccessGaps;
GO
CREATE VIEW Sec.vUserAccessGaps
AS
    SELECT
        summary.UserId,
        summary.UPN,
        summary.PackageCount,
        summary.ReportCount,
        summary.SiteCount,
        summary.AccountCount,
        CASE
            WHEN summary.SiteCount > 0 AND summary.PackageCount = 0 THEN 'Sites without packages'
            WHEN summary.PackageCount > 0 AND summary.SiteCount = 0 THEN 'Packages without sites'
        END AS GapDescription
    FROM Sec.vUserCoverageSummary AS summary
    WHERE (summary.SiteCount > 0 AND summary.PackageCount = 0)
       OR (summary.PackageCount > 0 AND summary.SiteCount = 0);
GO

-- ================================================================================
-- APP VIEWS
-- ================================================================================

-- --------------------------------------------------------------------------------
-- App.vAccounts
-- Accounts with site count, user count, and policy counts
-- Used by: scrAccounts (A-01)
-- --------------------------------------------------------------------------------
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
        ISNULL(sites.SiteCount, 0)          AS SiteCount,
        -- User count (distinct users with any access grant to this account)
        ISNULL(users.UserCount, 0)          AS UserCount,
        -- Access policy count
        ISNULL(accPol.AccessPolicyCount, 0) AS AccessPolicyCount,
        -- Package policy count
        ISNULL(pkgPol.PackagePolicyCount, 0)AS PackagePolicyCount,
        -- Total policy count
        ISNULL(accPol.AccessPolicyCount, 0) +
        ISNULL(pkgPol.PackagePolicyCount, 0)AS TotalPolicyCount
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

-- --------------------------------------------------------------------------------
-- App.vPackages
-- Packages with report count
-- Used by: scrPackages (A-03)
-- --------------------------------------------------------------------------------
IF OBJECT_ID('App.vPackages', 'V') IS NOT NULL
    DROP VIEW App.vPackages;
GO
CREATE OR ALTER VIEW App.vPackages
AS
    SELECT
        p.PackageId,
        p.PackageCode,
        p.PackageName,
        p.PackageGroup,
        p.IsActive,
        p.CreatedOnUtc,
        p.ModifiedOnUtc,
        ISNULL(reports.ReportCount, 0) AS ReportCount
    FROM Dim.Package AS p
    OUTER APPLY
    (
        SELECT COUNT(*) AS ReportCount
        FROM Dim.BiReportPackage AS brp
        JOIN Dim.BiReport AS br ON br.BiReportId = brp.BiReportId
        WHERE brp.PackageId = p.PackageId
          AND br.IsActive = 1
    ) AS reports;
GO

-- --------------------------------------------------------------------------------
-- App.vBiReports
-- BI Reports with their package assignments
-- Used by: scrBiReports (A-05)
-- --------------------------------------------------------------------------------
IF OBJECT_ID('App.vBiReports', 'V') IS NOT NULL
    DROP VIEW App.vBiReports;
GO
CREATE OR ALTER VIEW App.vBiReports
AS
    SELECT
        br.BiReportId,
        br.ReportCode,
        br.ReportName,
        br.ReportUri,
        br.IsActive,
        br.CreatedOnUtc,
        br.ModifiedOnUtc,
        ISNULL(pkgs.PackageCount, 0)  AS PackageCount,
        ISNULL(pkgs.PackageList, '')  AS PackageList
    FROM Dim.BiReport AS br
    OUTER APPLY
    (
        SELECT
            COUNT(*)                                        AS PackageCount,
            STRING_AGG(p.PackageCode, ', ')                 AS PackageList
        FROM Dim.BiReportPackage AS brp
        JOIN Dim.Package AS p ON p.PackageId = brp.PackageId
        WHERE brp.BiReportId = br.BiReportId
          AND p.IsActive = 1
    ) AS pkgs;
GO

-- --------------------------------------------------------------------------------
-- App.vRoles
-- Roles with member count and grant summary
-- Used by: scrRoles (A-07), scrRoleDetail (A-08)
-- --------------------------------------------------------------------------------
IF OBJECT_ID('App.vRoles', 'V') IS NOT NULL
    DROP VIEW App.vRoles;
GO
CREATE OR ALTER VIEW App.vRoles
AS
    SELECT
        r.RoleId,
        r.RoleCode,
        r.RoleName,
        r.Description,
        p.IsActive,
        r.CreatedOnUtc,
        r.ModifiedOnUtc,
        ISNULL(members.MemberCount, 0)  AS MemberCount,
        ISNULL(grants.AccessGrantCount, 0) AS AccessGrantCount,
        ISNULL(grants.PackageGrantCount, 0) AS PackageGrantCount
    FROM Sec.Role AS r
    JOIN Sec.Principal AS p ON p.PrincipalId = r.RoleId
    OUTER APPLY
    (
        SELECT COUNT(*) AS MemberCount
        FROM Sec.RoleMembership AS rm
        WHERE rm.RoleId = r.RoleId
    ) AS members
    OUTER APPLY
    (
        SELECT
            COUNT(DISTINCT pag.PrincipalAccessGrantId) AS AccessGrantCount,
            COUNT(DISTINCT ppg.PrincipalPackageGrantId) AS PackageGrantCount
        FROM Sec.Principal AS pr
        LEFT JOIN Sec.PrincipalAccessGrant AS pag ON pag.PrincipalId = pr.PrincipalId
        LEFT JOIN Sec.PrincipalPackageGrant AS ppg ON ppg.PrincipalId = pr.PrincipalId
        WHERE pr.PrincipalId = r.RoleId
    ) AS grants;
GO

-- --------------------------------------------------------------------------------
-- App.vRoleMembers
-- Role members with user details
-- Used by: scrRoleDetail (A-08)
-- --------------------------------------------------------------------------------
IF OBJECT_ID('App.vRoleMembers', 'V') IS NOT NULL
    DROP VIEW App.vRoleMembers;
GO
CREATE OR ALTER VIEW App.vRoleMembers
AS
    SELECT
        rm.RoleId,
        rm.MemberPrincipalId,
        rm.AddedOnUtc,
        u.UPN,
        p.PrincipalName AS DisplayName
    FROM Sec.RoleMembership AS rm
    JOIN Sec.[User] AS u ON u.UserId = rm.MemberPrincipalId
    JOIN Sec.Principal AS p ON p.PrincipalId = rm.MemberPrincipalId;
GO

-- --------------------------------------------------------------------------------
-- App.vUsers
-- Users with role memberships, site count, package count and gap flag
-- Used by: scrUsers (A-11), scrUserDetail (A-12)
-- --------------------------------------------------------------------------------
IF OBJECT_ID('App.vUsers', 'V') IS NOT NULL
    DROP VIEW App.vUsers;
GO
CREATE OR ALTER VIEW App.vUsers
AS
    SELECT
        u.UserId,
        u.UPN,
        p.PrincipalName                     AS DisplayName,
        p.IsActive,
        u.CreatedOnUtc,
        u.ModifiedOnUtc,
        ISNULL(roles.RoleCount, 0)          AS RoleCount,
        ISNULL(roles.RoleList, '')          AS RoleList,
        ISNULL(coverage.SiteCount, 0)       AS SiteCount,
        ISNULL(coverage.AccountCount, 0)    AS AccountCount,
        ISNULL(coverage.PackageCount, 0)    AS PackageCount,
        ISNULL(coverage.ReportCount, 0)     AS ReportCount,
        -- Gap flag
        CASE
            WHEN ISNULL(coverage.SiteCount, 0) > 0
             AND ISNULL(coverage.PackageCount, 0) = 0 THEN 'Packages without sites'
            WHEN ISNULL(coverage.PackageCount, 0) > 0
             AND ISNULL(coverage.SiteCount, 0) = 0 THEN 'Sites without packages'
            ELSE 'OK'
        END AS GapStatus
    FROM Sec.[User] AS u
    JOIN Sec.Principal AS p ON p.PrincipalId = u.UserId
    OUTER APPLY
    (
        SELECT
            COUNT(DISTINCT rm.RoleId)               AS RoleCount,
            STRING_AGG(r.RoleName, ', ')            AS RoleList
        FROM Sec.RoleMembership AS rm
        JOIN Sec.Role AS r ON r.RoleId = rm.RoleId
        WHERE rm.MemberPrincipalId = u.UserId
    ) AS roles
    OUTER APPLY
    (
        SELECT
            COUNT(DISTINCT s.SiteOrgUnitId)     AS SiteCount,
            COUNT(DISTINCT s.AccountId)         AS AccountCount,
            COUNT(DISTINCT r.PackageId)         AS PackageCount,
            COUNT(DISTINCT r.BiReportId)        AS ReportCount
        FROM Sec.vAuthorizedSitesDynamic AS s
        FULL OUTER JOIN Sec.vAuthorizedReportsDynamic AS r
            ON r.UserPrincipalId = s.UserPrincipalId
        WHERE COALESCE(s.UserPrincipalId, r.UserPrincipalId) = u.UserId
    ) AS coverage;
GO

-- --------------------------------------------------------------------------------
-- App.vUserRoles
-- Role memberships per user with role details
-- Used by: scrUserDetail (A-12)
-- --------------------------------------------------------------------------------
IF OBJECT_ID('App.vUserRoles', 'V') IS NOT NULL
    DROP VIEW App.vUserRoles;
GO
CREATE OR ALTER VIEW App.vUserRoles
AS
    SELECT
        rm.MemberPrincipalId    AS UserId,
        rm.RoleId,
        r.RoleCode,
        r.RoleName,
        r.Description,
        rm.AddedOnUtc
    FROM Sec.RoleMembership AS rm
    JOIN Sec.Role AS r ON r.RoleId = rm.RoleId;
GO

-- --------------------------------------------------------------------------------
-- App.vPolicies
-- Combined access and package policies with principal names
-- Used by: scrPolicies (A-09)
-- --------------------------------------------------------------------------------
IF OBJECT_ID('App.vAccessPolicies', 'V') IS NOT NULL
    DROP VIEW App.vAccessPolicies;
GO
CREATE OR ALTER VIEW App.vAccessPolicies
AS
    SELECT
        pol.AccountAccessPolicyId   AS PolicyId,
        'Access'                    AS PolicyType,
        pol.PolicyName,
        p.PrincipalName,
        p.PrincipalType,
        pol.ScopeType,
        pol.OrgUnitType,
        pol.OrgUnitCode,
        pol.IsActive,
        pol.CreatedOnUtc,
        pol.ModifiedOnUtc
    FROM Sec.AccountAccessPolicy AS pol
    JOIN Sec.Principal AS p ON p.PrincipalId = pol.PrincipalId;
GO

IF OBJECT_ID('App.vPackagePolicies', 'V') IS NOT NULL
    DROP VIEW App.vPackagePolicies;
GO
CREATE OR ALTER VIEW App.vPackagePolicies
AS
    SELECT
        pol.AccountPackagePolicyId  AS PolicyId,
        'Package'                   AS PolicyType,
        pol.PolicyName,
        p.PrincipalName,
        p.PrincipalType,
        pol.GrantScope,
        pol.PackageCode,
        pol.IsActive,
        pol.CreatedOnUtc,
        pol.ModifiedOnUtc
    FROM Sec.AccountPackagePolicy AS pol
    JOIN Sec.Principal AS p ON p.PrincipalId = pol.PrincipalId;
GO

-- --------------------------------------------------------------------------------
-- App.vGrants
-- All access grants with resolved names
-- Used by: scrUserDetail (A-12), scrRoleDetail (A-08)
-- --------------------------------------------------------------------------------
IF OBJECT_ID('App.vGrants', 'V') IS NOT NULL
    DROP VIEW App.vGrants;
GO
CREATE OR ALTER VIEW App.vGrants
AS
    SELECT
        pag.PrincipalAccessGrantId,
        p.PrincipalId,
        p.PrincipalType,
        p.PrincipalName,
        pag.AccessType,
        pag.ScopeType,
        ISNULL(a.AccountCode, 'ALL')    AS AccountCode,
        ISNULL(a.AccountName, 'All Accounts') AS AccountName,
        ISNULL(ou.OrgUnitType, 'N/A')   AS OrgUnitType,
        ISNULL(ou.OrgUnitCode, 'N/A')   AS OrgUnitCode,
        ISNULL(ou.OrgUnitName, 'N/A')   AS OrgUnitName,
        pag.GrantedOnUtc
    FROM Sec.PrincipalAccessGrant AS pag
    JOIN Sec.Principal AS p ON p.PrincipalId = pag.PrincipalId
    LEFT JOIN Dim.Account AS a ON a.AccountId = pag.AccountId
    LEFT JOIN Dim.OrgUnit AS ou ON ou.OrgUnitId = pag.OrgUnitId;
GO

-- --------------------------------------------------------------------------------
-- App.vPackageGrants
-- All package grants with resolved names
-- Used by: scrUserDetail (A-12), scrRoleDetail (A-08)
-- --------------------------------------------------------------------------------
IF OBJECT_ID('App.vPackageGrants', 'V') IS NOT NULL
    DROP VIEW App.vPackageGrants;
GO
CREATE OR ALTER VIEW App.vPackageGrants
AS
    SELECT
        ppg.PrincipalPackageGrantId,
        p.PrincipalId,
        p.PrincipalType,
        p.PrincipalName,
        ppg.GrantScope,
        ISNULL(pkg.PackageCode, 'ALL')      AS PackageCode,
        ISNULL(pkg.PackageName, 'All Packages') AS PackageName,
        ppg.GrantedOnUtc
    FROM Sec.PrincipalPackageGrant AS ppg
    JOIN Sec.Principal AS p ON p.PrincipalId = ppg.PrincipalId
    LEFT JOIN Dim.Package AS pkg ON pkg.PackageId = ppg.PackageId;
GO

-- --------------------------------------------------------------------------------
-- App.vDelegations
-- Delegations with resolved principal, account and org unit names
-- Used by: scrDelegations (A-17), scrDelegationDetail
-- --------------------------------------------------------------------------------
IF OBJECT_ID('App.vDelegations', 'V') IS NOT NULL
    DROP VIEW App.vDelegations;
GO
CREATE OR ALTER VIEW App.vDelegations
AS
    SELECT
        del.PrincipalDelegationId,
        delegator.PrincipalName             AS DelegatorName,
        delegator.PrincipalType             AS DelegatorType,
        delegate.PrincipalName              AS DelegateName,
        delegate.PrincipalType              AS DelegateType,
        del.AccessType,
        del.ScopeType,
        ISNULL(a.AccountCode, 'ALL')        AS AccountCode,
        ISNULL(a.AccountName, 'All Accounts') AS AccountName,
        ISNULL(ou.OrgUnitType, 'N/A')       AS OrgUnitType,
        ISNULL(ou.OrgUnitCode, 'N/A')       AS OrgUnitCode,
        ISNULL(ou.OrgUnitName, 'N/A')       AS OrgUnitName,
        del.IsActive,
        del.CreatedOnUtc,
        del.ModifiedOnUtc
    FROM Sec.PrincipalDelegation AS del
    JOIN Sec.Principal AS delegator ON delegator.PrincipalId = del.DelegatorPrincipalId
    JOIN Sec.Principal AS delegate  ON delegate.PrincipalId  = del.DelegatePrincipalId
    LEFT JOIN Dim.Account AS a      ON a.AccountId           = del.AccountId
    LEFT JOIN Dim.OrgUnit AS ou     ON ou.OrgUnitId          = del.OrgUnitId;
GO

-- --------------------------------------------------------------------------------
-- App.vOrgUnits
-- Org units with account info and parent info
-- Used by: scrSites (M-03), scrSiteDetail (M-04)
-- --------------------------------------------------------------------------------
IF OBJECT_ID('App.vOrgUnits', 'V') IS NOT NULL
    DROP VIEW App.vOrgUnits;
GO
CREATE OR ALTER VIEW App.vOrgUnits
AS
    SELECT
        ou.OrgUnitId,
        ou.AccountId,
        a.AccountCode,
        a.AccountName,
        ou.OrgUnitType,
        ou.OrgUnitCode,
        ou.OrgUnitName,
        ou.ParentOrgUnitId,
        parent.OrgUnitName          AS ParentOrgUnitName,
        parent.OrgUnitType          AS ParentOrgUnitType,
        ou.Path,
        ou.CountryCode,
        ou.IsActive,
        ou.CreatedOnUtc,
        ou.ModifiedOnUtc,
        ISNULL(children.ChildCount, 0) AS ChildCount,
        ISNULL(maps.SourceCount, 0)    AS SourceMappingCount
    FROM Dim.OrgUnit AS ou
    JOIN Dim.Account AS a ON a.AccountId = ou.AccountId
    LEFT JOIN Dim.OrgUnit AS parent ON parent.OrgUnitId = ou.ParentOrgUnitId
    OUTER APPLY
    (
        SELECT COUNT(*) AS ChildCount
        FROM Dim.OrgUnit AS child
        WHERE child.ParentOrgUnitId = ou.OrgUnitId
          AND child.IsActive = 1
    ) AS children
    OUTER APPLY
    (
        SELECT COUNT(*) AS SourceCount
        FROM Dim.OrgUnitSourceMap AS m
        WHERE m.OrgUnitId = ou.OrgUnitId
          AND m.IsActive = 1
    ) AS maps;
GO

-- --------------------------------------------------------------------------------
-- App.vSourceMappings
-- Source system mappings with org unit details
-- Used by: scrSourceMapping (M-13)
-- --------------------------------------------------------------------------------
IF OBJECT_ID('App.vSourceMappings', 'V') IS NOT NULL
    DROP VIEW App.vSourceMappings;
GO
CREATE OR ALTER VIEW App.vSourceMappings
AS
    SELECT
        m.OrgUnitSourceMapId,
        m.OrgUnitId,
        ou.OrgUnitCode,
        ou.OrgUnitName,
        ou.OrgUnitType,
        a.AccountId,
        a.AccountCode,
        a.AccountName,
        m.SourceSystem,
        m.SourceOrgUnitId,
        m.SourceOrgUnitName,
        m.IsActive,
        m.CreatedOnUtc,
        m.ModifiedOnUtc
    FROM Dim.OrgUnitSourceMap AS m
    JOIN Dim.OrgUnit AS ou ON ou.OrgUnitId = m.OrgUnitId
    JOIN Dim.Account AS a  ON a.AccountId  = ou.AccountId;
GO

-- --------------------------------------------------------------------------------
-- App.vPrincipals
-- All principals (users and roles) for dropdowns
-- Used by: grant wizards, delegation screens
-- --------------------------------------------------------------------------------
IF OBJECT_ID('App.vPrincipals', 'V') IS NOT NULL
    DROP VIEW App.vPrincipals;
GO
CREATE OR ALTER VIEW App.vPrincipals
AS
    SELECT
        p.PrincipalId,
        p.PrincipalType,
        p.PrincipalName,
        p.IsActive,
        -- UPN for users
        u.UPN,
        -- RoleCode for roles
        r.RoleCode
    FROM Sec.Principal AS p
    LEFT JOIN Sec.[User] AS u ON u.UserId = p.PrincipalId
    LEFT JOIN Sec.Role AS r   ON r.RoleId = p.PrincipalId;
GO

-- --------------------------------------------------------------------------------
-- App.vCoverageSummary
-- Full coverage summary per user for coverage map screen
-- Used by: scrCoverageMap (M-11), scrCoverageGaps (M-12)
-- --------------------------------------------------------------------------------
IF OBJECT_ID('App.vCoverageSummary', 'V') IS NOT NULL
    DROP VIEW App.vCoverageSummary;
GO
CREATE OR ALTER VIEW App.vCoverageSummary
AS
    SELECT
        summary.UserId,
        summary.UPN,
        summary.PackageCount,
        summary.ReportCount,
        summary.SiteCount,
        summary.AccountCount,
        CASE
            WHEN summary.SiteCount > 0 AND summary.PackageCount = 0
                THEN 'Sites without packages'
            WHEN summary.PackageCount > 0 AND summary.SiteCount = 0
                THEN 'Packages without sites'
            ELSE 'OK'
        END AS GapStatus
    FROM Sec.vUserCoverageSummary AS summary;
GO


-- Stored procedures ----------------------------------------------------------------


-- Inserts or updates an org unit, enforcing materialized path construction
CREATE OR ALTER PROCEDURE App.InsertOrgUnit
    @AccountCode            NVARCHAR(50),
    @OrgUnitType            NVARCHAR(20),
    @OrgUnitCode            NVARCHAR(50),
    @OrgUnitName            NVARCHAR(200),
    @ParentOrgUnitType      NVARCHAR(20) = NULL,
    @ParentOrgUnitCode      NVARCHAR(50) = NULL,
    @CountryCode            NVARCHAR(10) = NULL,
    @IsActive               BIT = 1,
    @OrgUnitId              INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @AccountId INT = (SELECT AccountId FROM Dim.Account WHERE AccountCode = @AccountCode);
    IF @AccountId IS NULL
        THROW 50001, 'Account not found for provided AccountCode.', 1;

    DECLARE @ParentOrgUnitId INT = NULL;
    DECLARE @ParentPath NVARCHAR(850) = CONCAT('|', @AccountCode, '|');

    IF @ParentOrgUnitCode IS NOT NULL
    BEGIN
        SELECT
            @ParentOrgUnitId = OrgUnitId,
            @ParentPath = Path
        FROM Dim.OrgUnit
        WHERE AccountId = @AccountId
          AND OrgUnitType = @ParentOrgUnitType
          AND OrgUnitCode = @ParentOrgUnitCode;

        IF @ParentOrgUnitId IS NULL
            THROW 50002, 'Parent org unit not found for provided parameters.', 1;
    END

    DECLARE @ExistingId INT = (
        SELECT OrgUnitId
        FROM Dim.OrgUnit
        WHERE AccountId = @AccountId
          AND OrgUnitType = @OrgUnitType
          AND OrgUnitCode = @OrgUnitCode
    );

    DECLARE @Path NVARCHAR(850) = CASE
                                      WHEN @ParentOrgUnitId IS NULL THEN CONCAT('|', @AccountCode, '|', @OrgUnitCode, '|')
                                      ELSE CONCAT(@ParentPath, @OrgUnitCode, '|')
                                  END;

    IF @ExistingId IS NULL
    BEGIN
        INSERT INTO Dim.OrgUnit (AccountId, OrgUnitType, OrgUnitCode, OrgUnitName, ParentOrgUnitId, Path, CountryCode, IsActive)
        VALUES (@AccountId, @OrgUnitType, @OrgUnitCode, @OrgUnitName, @ParentOrgUnitId, @Path,
                CASE WHEN @OrgUnitType IN ('Country','Site') THEN @CountryCode ELSE NULL END,
                @IsActive);

        SET @OrgUnitId = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE Dim.OrgUnit
        SET OrgUnitName = @OrgUnitName,
            ParentOrgUnitId = @ParentOrgUnitId,
            Path = @Path,
            CountryCode = CASE WHEN @OrgUnitType IN ('Country','Site') THEN @CountryCode ELSE CountryCode END,
            IsActive = @IsActive,
            ModifiedOnUtc = SYSUTCDATETIME(),
            ModifiedBy = SESSION_USER
        WHERE OrgUnitId = @ExistingId;

        SET @OrgUnitId = @ExistingId;
    END
END;
GO

-- Ensures full site hierarchy exists for an account/division/country/site combination
CREATE OR ALTER PROCEDURE App.CreateOrEnsureSitePath
    @AccountCode    NVARCHAR(50),
    @DivisionCode   NVARCHAR(50),
    @DivisionName   NVARCHAR(200),
    @CountryCode    NVARCHAR(10),
    @CountryName    NVARCHAR(200),
    @SiteCode       NVARCHAR(50),
    @SiteName       NVARCHAR(200),
    @SiteOrgUnitId  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @DivisionOrgUnitId INT;
    EXEC App.InsertOrgUnit
        @AccountCode = @AccountCode,
        @OrgUnitType = 'Division',
        @OrgUnitCode = @DivisionCode,
        @OrgUnitName = @DivisionName,
        @ParentOrgUnitType = NULL,
        @ParentOrgUnitCode = NULL,
        @CountryCode = NULL,
        @OrgUnitId = @DivisionOrgUnitId OUTPUT;

    DECLARE @CountryOrgUnitId INT;
    EXEC App.InsertOrgUnit
        @AccountCode = @AccountCode,
        @OrgUnitType = 'Country',
        @OrgUnitCode = @CountryCode,
        @OrgUnitName = @CountryName,
        @ParentOrgUnitType = 'Division',
        @ParentOrgUnitCode = @DivisionCode,
        @CountryCode = @CountryCode,
        @OrgUnitId = @CountryOrgUnitId OUTPUT;

    EXEC App.InsertOrgUnit
        @AccountCode = @AccountCode,
        @OrgUnitType = 'Site',
        @OrgUnitCode = @SiteCode,
        @OrgUnitName = @SiteName,
        @ParentOrgUnitType = 'Country',
        @ParentOrgUnitCode = @CountryCode,
        @CountryCode = @CountryCode,
        @OrgUnitId = @SiteOrgUnitId OUTPUT;
END;
GO

-- Upserts a user principal and synchronizes Sec.Principal metadata -----------------
CREATE OR ALTER PROCEDURE App.UpsertUser
    @UPN            NVARCHAR(320),
    @DisplayName    NVARCHAR(200) = NULL,
    @UserId         INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ExistingUserId INT = (
        SELECT UserId
        FROM Sec.[User]
        WHERE UPN = @UPN
    );

    IF @ExistingUserId IS NULL
    BEGIN
        INSERT INTO Sec.Principal (PrincipalType, PrincipalName)
        VALUES ('User', COALESCE(@DisplayName, @UPN));

        SET @ExistingUserId = SCOPE_IDENTITY();

        INSERT INTO Sec.[User] (UserId, UPN, DisplayName)
        VALUES (@ExistingUserId, @UPN, @DisplayName);
    END
    ELSE
    BEGIN
        UPDATE Sec.Principal
        SET PrincipalName = COALESCE(@DisplayName, PrincipalName),
            ModifiedOnUtc = SYSUTCDATETIME(),
            ModifiedBy = SESSION_USER
        WHERE PrincipalId = @ExistingUserId;

        UPDATE Sec.[User]
        SET DisplayName = COALESCE(@DisplayName, DisplayName),
            ModifiedOnUtc = SYSUTCDATETIME(),
            ModifiedBy = SESSION_USER
        WHERE UserId = @ExistingUserId;
    END

    SET @UserId = @ExistingUserId;
END;
GO

-- Upserts a security role and aligns Sec.Principal metadata -----------------------
CREATE OR ALTER PROCEDURE App.UpsertRole
    @RoleCode       NVARCHAR(100),
    @RoleName       NVARCHAR(200),
    @Description    NVARCHAR(400) = NULL,
    @RoleId         INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ExistingRoleId INT = (
        SELECT RoleId
        FROM Sec.Role
        WHERE RoleCode = @RoleCode
    );

    IF @ExistingRoleId IS NULL
    BEGIN
        INSERT INTO Sec.Principal (PrincipalType, PrincipalName)
        VALUES ('Role', COALESCE(@RoleName, @RoleCode));

        SET @ExistingRoleId = SCOPE_IDENTITY();

        INSERT INTO Sec.Role (RoleId, RoleCode, RoleName, Description)
        VALUES (@ExistingRoleId, @RoleCode, @RoleName, @Description);
    END
    ELSE
    BEGIN
        UPDATE Sec.Principal
        SET PrincipalName = COALESCE(@RoleName, PrincipalName),
            ModifiedOnUtc = SYSUTCDATETIME(),
            ModifiedBy = SESSION_USER
        WHERE PrincipalId = @ExistingRoleId;

        UPDATE Sec.Role
        SET RoleName = COALESCE(@RoleName, RoleName),
            Description = @Description,
            ModifiedOnUtc = SYSUTCDATETIME(),
            ModifiedBy = SESSION_USER
        WHERE RoleId = @ExistingRoleId;
    END

    SET @RoleId = @ExistingRoleId;
END;
GO

CREATE OR ALTER PROCEDURE App.ApplyAccountPolicies
    @AccountCode   NVARCHAR(50),
    @ApplyAccess   BIT = 1,
    @ApplyPackages BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @AccountId INT = (SELECT AccountId FROM Dim.Account WHERE AccountCode = @AccountCode);
    IF @AccountId IS NULL
        THROW 50022, 'Account not found for provided code.', 1;

    DECLARE @MissingOrgUnits TABLE
    (
        PolicyName  NVARCHAR(200),
        OrgUnitType NVARCHAR(20),
        OrgUnitCode NVARCHAR(50)
    );

    IF @ApplyAccess = 1
    BEGIN
        -- Full-account scope policies
        INSERT INTO Sec.PrincipalAccessGrant (PrincipalId, AccessType, AccountId, ScopeType)
        SELECT
            pol.PrincipalId,
            'ACCOUNT',
            @AccountId,
            'NONE'
        FROM Sec.AccountAccessPolicy AS pol
        WHERE pol.IsActive = 1
          AND pol.ScopeType = 'NONE'
          AND NOT EXISTS
          (
              SELECT 1
              FROM Sec.PrincipalAccessGrant AS existing
              WHERE existing.PrincipalId = pol.PrincipalId
                AND existing.AccessType = 'ACCOUNT'
                AND existing.AccountId = @AccountId
                AND existing.ScopeType = 'NONE'
          );

        -- Scoped org-unit policies
        INSERT INTO Sec.PrincipalAccessGrant (PrincipalId, AccessType, AccountId, ScopeType, OrgUnitId)
        SELECT
            pol.PrincipalId,
            'ACCOUNT',
            @AccountId,
            'ORGUNIT',
            ou.OrgUnitId
        FROM Sec.AccountAccessPolicy AS pol
        JOIN Dim.OrgUnit AS ou
            ON ou.AccountId = @AccountId
           AND ou.OrgUnitType = pol.OrgUnitType
           AND ou.OrgUnitCode = pol.OrgUnitCode
        WHERE pol.IsActive = 1
          AND pol.ScopeType = 'ORGUNIT'
          AND NOT EXISTS
          (
              SELECT 1
              FROM Sec.PrincipalAccessGrant AS existing
              WHERE existing.PrincipalId = pol.PrincipalId
                AND existing.AccessType = 'ACCOUNT'
                AND existing.AccountId = @AccountId
                AND existing.ScopeType = 'ORGUNIT'
                AND existing.OrgUnitId = ou.OrgUnitId
          );

        -- Track policies whose org units were not found for this account
        INSERT INTO @MissingOrgUnits (PolicyName, OrgUnitType, OrgUnitCode)
        SELECT DISTINCT
            pol.PolicyName,
            pol.OrgUnitType,
            pol.OrgUnitCode
        FROM Sec.AccountAccessPolicy AS pol
        WHERE pol.IsActive = 1
          AND pol.ScopeType = 'ORGUNIT'
          AND NOT EXISTS
          (
              SELECT 1
              FROM Dim.OrgUnit AS ou
              WHERE ou.AccountId = @AccountId
                AND ou.OrgUnitType = pol.OrgUnitType
                AND ou.OrgUnitCode = pol.OrgUnitCode
          );

        -- === Apply AccountRolePolicy (create per-account role and grant coverage) ===
        IF EXISTS (SELECT 1 FROM Sec.AccountRolePolicy WHERE IsActive = 1)
        BEGIN
            DECLARE @AccountName NVARCHAR(200) = (SELECT AccountName FROM Dim.Account WHERE AccountId = @AccountId);

            -- Materialize policy expansion into a table variable (avoid CTE + DECLARE sequencing issues)
            DECLARE @Pol TABLE
            (
                AccountRolePolicyId INT,
                PolicyName          NVARCHAR(200),
                RoleCode            NVARCHAR(100),
                RoleName            NVARCHAR(200),
                ScopeType           NVARCHAR(15),
                OrgUnitType         NVARCHAR(20),
                OrgUnitCode         NVARCHAR(50)
            );

            INSERT INTO @Pol (AccountRolePolicyId, PolicyName, RoleCode, RoleName, ScopeType, OrgUnitType, OrgUnitCode)
            SELECT
                arp.AccountRolePolicyId,
                arp.PolicyName,
                REPLACE(REPLACE(arp.RoleCodeTemplate, '{AccountCode}', @AccountCode), '{AccountName}', @AccountName),
                REPLACE(REPLACE(arp.RoleNameTemplate, '{AccountCode}', @AccountCode), '{AccountName}', @AccountName),
                arp.ScopeType,
                arp.OrgUnitType,
                arp.OrgUnitCode
            FROM Sec.AccountRolePolicy AS arp
            WHERE arp.IsActive = 1;

            -- Upsert missing roles using App.UpsertRole
            DECLARE @RoleId INT, @RoleCode NVARCHAR(100), @RoleName NVARCHAR(200);

            DECLARE RoleCur CURSOR LOCAL FAST_FORWARD FOR
                SELECT p.RoleCode, p.RoleName
                FROM @Pol AS p
                WHERE NOT EXISTS (SELECT 1 FROM Sec.Role AS r WHERE r.RoleCode = p.RoleCode);

            OPEN RoleCur;
            FETCH NEXT FROM RoleCur INTO @RoleCode, @RoleName;
            WHILE @@FETCH_STATUS = 0
            BEGIN
                EXEC App.UpsertRole @RoleCode = @RoleCode, @RoleName = @RoleName, @RoleId = @RoleId OUTPUT;
                FETCH NEXT FROM RoleCur INTO @RoleCode, @RoleName;
            END
            CLOSE RoleCur;
            DEALLOCATE RoleCur;

            -- Grant coverage to each role for this account (idempotent)
            INSERT INTO Sec.PrincipalAccessGrant (PrincipalId, AccessType, AccountId, ScopeType, OrgUnitId)
            SELECT
                r.RoleId,
                'ACCOUNT',
                @AccountId,
                CASE WHEN p.ScopeType = 'NONE' THEN 'NONE' ELSE 'ORGUNIT' END,
                CASE
                    WHEN p.ScopeType = 'ORGUNIT'
                    THEN (
                        SELECT TOP (1) ou.OrgUnitId
                        FROM Dim.OrgUnit AS ou
                        WHERE ou.AccountId = @AccountId
                          AND ou.OrgUnitType = p.OrgUnitType
                          AND ou.OrgUnitCode = p.OrgUnitCode
                        ORDER BY ou.OrgUnitId
                    )
                    ELSE NULL
                END
            FROM @Pol AS p
            JOIN Sec.Role AS r
              ON r.RoleCode = p.RoleCode
            WHERE NOT EXISTS
            (
                SELECT 1
                FROM Sec.PrincipalAccessGrant AS existing
                WHERE existing.PrincipalId = r.RoleId
                  AND existing.AccessType = 'ACCOUNT'
                  AND existing.AccountId = @AccountId
                  AND existing.ScopeType = CASE WHEN p.ScopeType='NONE' THEN 'NONE' ELSE 'ORGUNIT' END
                  AND ISNULL(existing.OrgUnitId, -1) =
                      ISNULL(
                        CASE WHEN p.ScopeType='ORGUNIT' THEN (
                            SELECT TOP (1) ou.OrgUnitId FROM Dim.OrgUnit AS ou
                            WHERE ou.AccountId = @AccountId AND ou.OrgUnitType = p.OrgUnitType AND ou.OrgUnitCode = p.OrgUnitCode
                            ORDER BY ou.OrgUnitId
                        ) ELSE NULL END
                      , -1)
            );
        END
    END;

    IF @ApplyPackages = 1
    BEGIN
        -- All-package policies
        INSERT INTO Sec.PrincipalPackageGrant (PrincipalId, PackageId, GrantScope)
        SELECT
            pol.PrincipalId,
            NULL,
            'ALL_PACKAGES'
        FROM Sec.AccountPackagePolicy AS pol
        WHERE pol.IsActive = 1
          AND pol.GrantScope = 'ALL_PACKAGES'
          AND NOT EXISTS
          (
              SELECT 1
              FROM Sec.PrincipalPackageGrant AS existing
              WHERE existing.PrincipalId = pol.PrincipalId
                AND existing.GrantScope = 'ALL_PACKAGES'
          );

        -- Package-specific policies
        INSERT INTO Sec.PrincipalPackageGrant (PrincipalId, PackageId, GrantScope)
        SELECT
            pol.PrincipalId,
            pkg.PackageId,
            'PACKAGE'
        FROM Sec.AccountPackagePolicy AS pol
        JOIN Dim.Package AS pkg
            ON pkg.PackageCode = pol.PackageCode
        WHERE pol.IsActive = 1
          AND pol.GrantScope = 'PACKAGE'
          AND NOT EXISTS
          (
              SELECT 1
              FROM Sec.PrincipalPackageGrant AS existing
              WHERE existing.PrincipalId = pol.PrincipalId
                AND existing.PackageId = pkg.PackageId
                AND existing.GrantScope = 'PACKAGE'
          );
    END;

    -- Return missing org-unit mappings (if any) to assist operations
    IF EXISTS (SELECT 1 FROM @MissingOrgUnits)
    BEGIN
        SELECT * FROM @MissingOrgUnits;
    END
END;
GO

-- Upsert account metadata supporting automated ingestion
CREATE OR ALTER PROCEDURE App.UpsertAccount
    @AccountCode    NVARCHAR(50),
    @AccountName    NVARCHAR(200),
    @IsActive       BIT = 1,
    @ApplyPolicies  BIT = 1,
    @AccountId      INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ExistingId INT = (SELECT AccountId FROM Dim.Account WHERE AccountCode = @AccountCode);

    IF @ExistingId IS NULL
    BEGIN
        INSERT INTO Dim.Account (AccountCode, AccountName, IsActive)
        VALUES (@AccountCode, @AccountName, @IsActive);

        SET @AccountId = SCOPE_IDENTITY();

        IF @ApplyPolicies = 1
            EXEC App.ApplyAccountPolicies @AccountCode = @AccountCode, @ApplyAccess = 1, @ApplyPackages = 1;
    END
    ELSE
    BEGIN
        UPDATE Dim.Account
        SET AccountName = @AccountName,
            IsActive = @IsActive,
            ModifiedOnUtc = SYSUTCDATETIME(),
            ModifiedBy = SESSION_USER
        WHERE AccountId = @ExistingId;

        SET @AccountId = @ExistingId;
    END
END;
GO

-- Provides consolidated checks for orphaned data and access gaps
CREATE OR ALTER PROCEDURE App.SecurityHealthCheck
AS
BEGIN
    SET NOCOUNT ON;

    -- Orphaned access grants (ORGUNIT scope without backing org unit)
    SELECT
        pag.PrincipalId,
        pr.PrincipalType,
        pr.PrincipalName,
        pag.AccountId,
        pag.ScopeType,
        pag.OrgUnitId,
        pag.GrantedOnUtc
    FROM Sec.PrincipalAccessGrant AS pag
    JOIN Sec.Principal AS pr
        ON pr.PrincipalId = pag.PrincipalId
    WHERE pag.ScopeType = 'ORGUNIT'
      AND NOT EXISTS (
            SELECT 1
            FROM Dim.OrgUnit AS ou
            WHERE ou.OrgUnitId = pag.OrgUnitId
        );

    -- Policies referencing missing principals or packages/org units
    SELECT
        pol.PolicyName,
        pol.ScopeType,
        pol.OrgUnitType,
        pol.OrgUnitCode,
        pol.IsActive
    FROM Sec.AccountAccessPolicy AS pol
    LEFT JOIN Sec.Principal AS pr
        ON pr.PrincipalId = pol.PrincipalId
    WHERE pr.PrincipalId IS NULL;

    SELECT
        pol.PolicyName,
        pol.GrantScope,
        pol.PackageCode,
        pol.IsActive
    FROM Sec.AccountPackagePolicy AS pol
    LEFT JOIN Sec.Principal AS pr
        ON pr.PrincipalId = pol.PrincipalId
    LEFT JOIN Dim.Package AS pkg
        ON pkg.PackageCode = pol.PackageCode
    WHERE pr.PrincipalId IS NULL
       OR (pol.GrantScope = 'PACKAGE' AND pkg.PackageId IS NULL);

    -- Delegations referencing missing principals or scope
    SELECT
        del.PrincipalDelegationId,
        delegator.PrincipalName AS Delegator,
        delegate.PrincipalName  AS Delegate,
        del.AccessType,
        del.ScopeType,
        del.AccountId,
        del.OrgUnitId
    FROM Sec.PrincipalDelegation AS del
    LEFT JOIN Sec.Principal AS delegator ON delegator.PrincipalId = del.DelegatorPrincipalId
    LEFT JOIN Sec.Principal AS delegate  ON delegate.PrincipalId = del.DelegatePrincipalId
    LEFT JOIN Dim.Account AS acct        ON acct.AccountId = del.AccountId
    LEFT JOIN Dim.OrgUnit AS org         ON org.OrgUnitId = del.OrgUnitId
    WHERE del.IsActive = 1
      AND (
            delegator.PrincipalId IS NULL
         OR delegate.PrincipalId IS NULL
         OR (del.AccessType = 'ACCOUNT' AND acct.AccountId IS NULL)
         OR (del.ScopeType = 'ORGUNIT' AND org.OrgUnitId IS NULL)
          );

    -- Users with mismatched report/site coverage
    SELECT *
    FROM Sec.vUserAccessGaps;
END;
GO

-- Helper to resolve principal id based on provided metadata ------------------------
CREATE OR ALTER FUNCTION Sec.fnResolvePrincipalId
(
    @PrincipalType NVARCHAR(10),
    @PrincipalIdentifier NVARCHAR(320)
)
RETURNS INT
AS
BEGIN
    DECLARE @PrincipalId INT;

    IF @PrincipalType = 'User'
    BEGIN
        SELECT @PrincipalId = UserId
        FROM Sec.[User]
        WHERE UPN = @PrincipalIdentifier;

        IF @PrincipalId IS NULL
        BEGIN
            SELECT @PrincipalId = PrincipalId
            FROM Sec.Principal
            WHERE PrincipalType = 'User'
              AND PrincipalName = @PrincipalIdentifier;
        END
    END
    ELSE IF @PrincipalType = 'Role'
    BEGIN
        SELECT @PrincipalId = RoleId
        FROM Sec.Role
        WHERE RoleCode = @PrincipalIdentifier;

        IF @PrincipalId IS NULL
        BEGIN
            SELECT @PrincipalId = PrincipalId
            FROM Sec.Principal
            WHERE PrincipalType = 'Role'
              AND PrincipalName = @PrincipalIdentifier;
        END
    END

    RETURN @PrincipalId;
END;
GO

-- Grants --------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE Sec.GrantGlobalAllPackages
    @PrincipalType NVARCHAR(10),
    @PrincipalIdentifier NVARCHAR(320)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PrincipalId INT = Sec.fnResolvePrincipalId(@PrincipalType, @PrincipalIdentifier);
    IF @PrincipalId IS NULL
        THROW 50010, 'Principal not found for global all-packages grant.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM Sec.PrincipalPackageGrant
        WHERE PrincipalId = @PrincipalId
          AND GrantScope = 'ALL_PACKAGES'
    )
    BEGIN
        INSERT INTO Sec.PrincipalPackageGrant (PrincipalId, PackageId, GrantScope)
        VALUES (@PrincipalId, NULL, 'ALL_PACKAGES');
    END;
END;
GO

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
        SET @ActingPrincipalId = Sec.fnResolvePrincipalId(@ActingPrincipalType, @ActingPrincipalIdentifier);
        IF @ActingPrincipalId IS NULL
            THROW 50024, 'Acting principal not found for delegation.', 1;

        IF Sec.fnCanAdministerScope(@ActingPrincipalId, NULL, 'NONE', NULL) = 0
            THROW 50025, 'Acting principal lacks coverage to grant all accounts.', 1;
    END

    IF NOT EXISTS (
        SELECT 1
        FROM Sec.PrincipalAccessGrant
        WHERE PrincipalId = @PrincipalId
          AND AccessType = 'ALL'
          AND ScopeType = 'NONE'
    )
    BEGIN
        INSERT INTO Sec.PrincipalAccessGrant (PrincipalId, AccessType, ScopeType)
        VALUES (@PrincipalId, 'ALL', 'NONE');
    END;
END;
GO

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

    IF NOT EXISTS (
        SELECT 1
        FROM Sec.PrincipalPackageGrant
        WHERE PrincipalId = @PrincipalId
          AND PackageId = @PackageId
          AND GrantScope = 'PACKAGE'
    )
    BEGIN
        INSERT INTO Sec.PrincipalPackageGrant (PrincipalId, PackageId, GrantScope)
        VALUES (@PrincipalId, @PackageId, 'PACKAGE');
    END;
END;
GO

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
        SET @ActingPrincipalId = Sec.fnResolvePrincipalId(@ActingPrincipalType, @ActingPrincipalIdentifier);
        IF @ActingPrincipalId IS NULL
            THROW 50024, 'Acting principal not found for delegation.', 1;

        IF Sec.fnCanAdministerScope(@ActingPrincipalId, @AccountId, 'NONE', NULL) = 0
            THROW 50026, 'Acting principal lacks coverage to grant full account access.', 1;
    END

    IF NOT EXISTS (
        SELECT 1
        FROM Sec.PrincipalAccessGrant
        WHERE PrincipalId = @PrincipalId
          AND AccessType = 'ACCOUNT'
          AND AccountId = @AccountId
          AND ScopeType = 'NONE'
    )
    BEGIN
        INSERT INTO Sec.PrincipalAccessGrant (PrincipalId, AccessType, AccountId, ScopeType)
        VALUES (@PrincipalId, 'ACCOUNT', @AccountId, 'NONE');
    END;
END;
GO

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
    DECLARE @ScopeType NVARCHAR(15);

    SELECT @OrgUnitId = OrgUnitId
    FROM Dim.OrgUnit
    WHERE AccountId = @AccountId
      AND OrgUnitType = @OrgUnitType
      AND OrgUnitCode = @OrgUnitCode;

    IF @OrgUnitId IS NULL
        THROW 50017, 'Org unit not found for provided parameters.', 1;

    SET @ScopeType = 'ORGUNIT';

    DECLARE @ActingPrincipalId INT = NULL;
    IF @ActingPrincipalIdentifier IS NOT NULL
    BEGIN
        SET @ActingPrincipalType = COALESCE(@ActingPrincipalType, 'User');
        SET @ActingPrincipalId = Sec.fnResolvePrincipalId(@ActingPrincipalType, @ActingPrincipalIdentifier);
        IF @ActingPrincipalId IS NULL
            THROW 50024, 'Acting principal not found for delegation.', 1;

        IF Sec.fnCanAdministerScope(@ActingPrincipalId, @AccountId, 'ORGUNIT', @OrgUnitId) = 0
            THROW 50027, 'Acting principal lacks coverage to grant this org unit.', 1;
    END

    IF NOT EXISTS (
        SELECT 1
        FROM Sec.PrincipalAccessGrant
        WHERE PrincipalId = @PrincipalId
          AND AccessType = 'ACCOUNT'
          AND AccountId = @AccountId
          AND ScopeType = @ScopeType
          AND COALESCE(OrgUnitId, -1) = COALESCE(@OrgUnitId, -1)
    )
    BEGIN
        INSERT INTO Sec.PrincipalAccessGrant (PrincipalId, AccessType, AccountId, ScopeType, OrgUnitId)
        VALUES (@PrincipalId, 'ACCOUNT', @AccountId, @ScopeType, @OrgUnitId);
    END;
END;
GO

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
        SET @ActingPrincipalId = Sec.fnResolvePrincipalId(@ActingPrincipalType, @ActingPrincipalIdentifier);
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

    INSERT INTO Sec.PrincipalAccessGrant (PrincipalId, AccessType, ScopeType, OrgUnitId)
    SELECT
        @PrincipalId,
        'ALL',
        'ORGUNIT',
        ou.OrgUnitId
    FROM Dim.OrgUnit AS ou
    WHERE ou.OrgUnitType = 'Country'
      AND ou.OrgUnitCode = @CountryCode
      AND NOT EXISTS (
            SELECT 1
            FROM Sec.PrincipalAccessGrant AS pag
            WHERE pag.PrincipalId = @PrincipalId
              AND pag.AccessType = 'ALL'
              AND pag.ScopeType = 'ORGUNIT'
              AND pag.OrgUnitId = ou.OrgUnitId
        );
END;
GO

CREATE OR ALTER PROCEDURE Sec.GrantDelegation
    @DelegatorPrincipalType NVARCHAR(10),
    @DelegatorIdentifier    NVARCHAR(320),
    @DelegatePrincipalType  NVARCHAR(10),
    @DelegateIdentifier     NVARCHAR(320),
    @AccessType             NVARCHAR(10),
    @AccountCode            NVARCHAR(50) = NULL,
    @ScopeType              NVARCHAR(15),
    @OrgUnitType            NVARCHAR(20) = NULL,
    @OrgUnitCode            NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @DelegatorId INT = Sec.fnResolvePrincipalId(@DelegatorPrincipalType, @DelegatorIdentifier);
    IF @DelegatorId IS NULL
        THROW 50029, 'Delegator principal not found.', 1;

    DECLARE @DelegateId INT = Sec.fnResolvePrincipalId(@DelegatePrincipalType, @DelegateIdentifier);
    IF @DelegateId IS NULL
        THROW 50030, 'Delegate principal not found.', 1;

    IF @DelegatorId = @DelegateId
        THROW 50031, 'Delegator and delegate cannot be the same principal.', 1;

    IF @AccessType NOT IN ('ALL','ACCOUNT')
        THROW 50032, 'Invalid delegation access type.', 1;

    IF @ScopeType NOT IN ('NONE','ORGUNIT')
        THROW 50033, 'Invalid delegation scope type.', 1;

    DECLARE @AccountId INT = NULL;
    IF @AccessType = 'ACCOUNT'
    BEGIN
        IF @AccountCode IS NULL
            THROW 50034, 'AccountCode required for account-level delegation.', 1;

        SELECT @AccountId = AccountId FROM Dim.Account WHERE AccountCode = @AccountCode;
        IF @AccountId IS NULL
            THROW 50035, 'Account not found for delegation.', 1;
    END

    DECLARE @OrgUnitId INT = NULL;
    IF @ScopeType = 'ORGUNIT'
    BEGIN
        IF @OrgUnitType IS NULL OR @OrgUnitCode IS NULL
            THROW 50036, 'OrgUnitType and OrgUnitCode required for org-unit delegation.', 1;

        IF @AccessType = 'ACCOUNT'
        BEGIN
            SELECT @OrgUnitId = OrgUnitId
            FROM Dim.OrgUnit
            WHERE AccountId = @AccountId
              AND OrgUnitType = @OrgUnitType
              AND OrgUnitCode = @OrgUnitCode;
        END
        ELSE
        BEGIN
            SELECT TOP (1) @OrgUnitId = OrgUnitId
            FROM Dim.OrgUnit
            WHERE OrgUnitType = @OrgUnitType
              AND OrgUnitCode = @OrgUnitCode
            ORDER BY OrgUnitId;
        END

        IF @OrgUnitId IS NULL
            THROW 50037, 'Org unit not found for delegation.', 1;
    END

    IF Sec.fnCanAdministerScope(@DelegatorId, @AccountId, @ScopeType, @OrgUnitId) = 0
        THROW 50038, 'Delegator lacks coverage to grant this delegation.', 1;

    IF EXISTS (
        SELECT 1
        FROM Sec.PrincipalDelegation
        WHERE DelegatorPrincipalId = @DelegatorId
          AND DelegatePrincipalId = @DelegateId
          AND AccessType = @AccessType
          AND ISNULL(AccountId, -1) = ISNULL(@AccountId, -1)
          AND ScopeType = @ScopeType
          AND ISNULL(OrgUnitId, -1) = ISNULL(@OrgUnitId, -1)
    )
    BEGIN
        UPDATE Sec.PrincipalDelegation
        SET IsActive = 1,
            ModifiedOnUtc = SYSUTCDATETIME(),
            ModifiedBy = SESSION_USER
        WHERE DelegatorPrincipalId = @DelegatorId
          AND DelegatePrincipalId = @DelegateId
          AND AccessType = @AccessType
          AND ISNULL(AccountId, -1) = ISNULL(@AccountId, -1)
          AND ScopeType = @ScopeType
          AND ISNULL(OrgUnitId, -1) = ISNULL(@OrgUnitId, -1);
    END
    ELSE
    BEGIN
        INSERT INTO Sec.PrincipalDelegation
            (DelegatorPrincipalId, DelegatePrincipalId, AccessType, AccountId, ScopeType, OrgUnitId)
        VALUES
            (@DelegatorId, @DelegateId, @AccessType, @AccountId, @ScopeType, @OrgUnitId);
    END
END;
GO

CREATE OR ALTER PROCEDURE Sec.RevokeDelegation
    @DelegatorPrincipalType NVARCHAR(10),
    @DelegatorIdentifier    NVARCHAR(320),
    @DelegatePrincipalType  NVARCHAR(10),
    @DelegateIdentifier     NVARCHAR(320),
    @AccessType             NVARCHAR(10),
    @AccountCode            NVARCHAR(50) = NULL,
    @ScopeType              NVARCHAR(15),
    @OrgUnitType            NVARCHAR(20) = NULL,
    @OrgUnitCode            NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @DelegatorId INT = Sec.fnResolvePrincipalId(@DelegatorPrincipalType, @DelegatorIdentifier);
    IF @DelegatorId IS NULL
        THROW 50039, 'Delegator principal not found.', 1;

    DECLARE @DelegateId INT = Sec.fnResolvePrincipalId(@DelegatePrincipalType, @DelegateIdentifier);
    IF @DelegateId IS NULL
        THROW 50040, 'Delegate principal not found.', 1;

    DECLARE @AccountId INT = NULL;
    IF @AccessType = 'ACCOUNT'
    BEGIN
        SELECT @AccountId = AccountId FROM Dim.Account WHERE AccountCode = @AccountCode;
    END

    DECLARE @OrgUnitId INT = NULL;
    IF @ScopeType = 'ORGUNIT'
    BEGIN
        IF @AccessType = 'ACCOUNT'
            SELECT @OrgUnitId = OrgUnitId
            FROM Dim.OrgUnit
            WHERE AccountId = @AccountId
              AND OrgUnitType = @OrgUnitType
              AND OrgUnitCode = @OrgUnitCode;
        ELSE
            SELECT TOP (1) @OrgUnitId = OrgUnitId
            FROM Dim.OrgUnit
            WHERE OrgUnitType = @OrgUnitType
              AND OrgUnitCode = @OrgUnitCode
            ORDER BY OrgUnitId;
    END

    UPDATE Sec.PrincipalDelegation
    SET IsActive = 0,
        ModifiedOnUtc = SYSUTCDATETIME(),
        ModifiedBy = SESSION_USER
    WHERE DelegatorPrincipalId = @DelegatorId
      AND DelegatePrincipalId = @DelegateId
      AND AccessType = @AccessType
      AND ISNULL(AccountId, -1) = ISNULL(@AccountId, -1)
      AND ScopeType = @ScopeType
      AND ISNULL(OrgUnitId, -1) = ISNULL(@OrgUnitId, -1);
END;
GO

-- --------------------------------------------------------------------------------
-- App.UpsertPackage
-- Insert or update a package
-- --------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE App.UpsertPackage
    @PackageCode    NVARCHAR(50),
    @PackageName    NVARCHAR(200),
    @PackageGroup   NVARCHAR(100) = NULL,
    @IsActive       BIT = 1,
    @PackageId      INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ExistingId INT = (
        SELECT PackageId
        FROM Dim.Package
        WHERE PackageCode = @PackageCode
    );

    IF @ExistingId IS NULL
    BEGIN
        INSERT INTO Dim.Package (PackageCode, PackageName, PackageGroup, IsActive)
        VALUES (@PackageCode, @PackageName, @PackageGroup, @IsActive);

        SET @PackageId = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE Dim.Package
        SET PackageName   = @PackageName,
            PackageGroup  = @PackageGroup,
            IsActive      = @IsActive,
            ModifiedOnUtc = SYSUTCDATETIME(),
            ModifiedBy    = SESSION_USER
        WHERE PackageId = @ExistingId;

        SET @PackageId = @ExistingId;
    END
END;
GO

-- --------------------------------------------------------------------------------
-- App.UpsertBiReport
-- Insert or update a BI report and its package assignments
-- --------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE App.UpsertBiReport
    @ReportCode     NVARCHAR(100),
    @ReportName     NVARCHAR(200),
    @ReportUri      NVARCHAR(500) = NULL,
    @IsActive       BIT = 1,
    @BiReportId     INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ExistingId INT = (
        SELECT BiReportId
        FROM Dim.BiReport
        WHERE ReportCode = @ReportCode
    );

    IF @ExistingId IS NULL
    BEGIN
        INSERT INTO Dim.BiReport (ReportCode, ReportName, ReportUri, IsActive)
        VALUES (@ReportCode, @ReportName, @ReportUri, @IsActive);

        SET @BiReportId = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE Dim.BiReport
        SET ReportName    = @ReportName,
            ReportUri     = @ReportUri,
            IsActive      = @IsActive,
            ModifiedOnUtc = SYSUTCDATETIME(),
            ModifiedBy    = SESSION_USER
        WHERE BiReportId = @ExistingId;

        SET @BiReportId = @ExistingId;
    END
END;
GO

-- --------------------------------------------------------------------------------
-- App.AssignReportToPackage
-- Assign a BI report to a package (idempotent)
-- --------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE App.AssignReportToPackage
    @ReportCode     NVARCHAR(100),
    @PackageCode    NVARCHAR(50),
    @Remove         BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ReportId INT = (SELECT BiReportId FROM Dim.BiReport WHERE ReportCode = @ReportCode);
    IF @ReportId IS NULL
        THROW 50050, 'Report not found.', 1;

    DECLARE @PackageId INT = (SELECT PackageId FROM Dim.Package WHERE PackageCode = @PackageCode);
    IF @PackageId IS NULL
        THROW 50051, 'Package not found.', 1;

    IF @Remove = 1
    BEGIN
        DELETE FROM Dim.BiReportPackage
        WHERE BiReportId = @ReportId AND PackageId = @PackageId;
    END
    ELSE
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM Dim.BiReportPackage
            WHERE BiReportId = @ReportId AND PackageId = @PackageId
        )
        BEGIN
            INSERT INTO Dim.BiReportPackage (BiReportId, PackageId)
            VALUES (@ReportId, @PackageId);
        END
    END
END;
GO

-- --------------------------------------------------------------------------------
-- App.AddRoleMember
-- Add a user to a role (idempotent)
-- --------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE App.AddRoleMember
    @RoleCode   NVARCHAR(100),
    @UserUPN    NVARCHAR(320)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @RoleId INT = (SELECT RoleId FROM Sec.Role WHERE RoleCode = @RoleCode);
    IF @RoleId IS NULL
        THROW 50052, 'Role not found.', 1;

    DECLARE @UserId INT = (SELECT UserId FROM Sec.[User] WHERE UPN = @UserUPN);
    IF @UserId IS NULL
        THROW 50053, 'User not found.', 1;

    IF NOT EXISTS (
        SELECT 1 FROM Sec.RoleMembership
        WHERE RoleId = @RoleId AND MemberPrincipalId = @UserId
    )
    BEGIN
        INSERT INTO Sec.RoleMembership (RoleId, MemberPrincipalId)
        VALUES (@RoleId, @UserId);
    END
END;
GO

-- --------------------------------------------------------------------------------
-- App.RemoveRoleMember
-- Remove a user from a role
-- --------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE App.RemoveRoleMember
    @RoleCode   NVARCHAR(100),
    @UserUPN    NVARCHAR(320)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @RoleId INT = (SELECT RoleId FROM Sec.Role WHERE RoleCode = @RoleCode);
    IF @RoleId IS NULL
        THROW 50054, 'Role not found.', 1;

    DECLARE @UserId INT = (SELECT UserId FROM Sec.[User] WHERE UPN = @UserUPN);
    IF @UserId IS NULL
        THROW 50055, 'User not found.', 1;

    DELETE FROM Sec.RoleMembership
    WHERE RoleId = @RoleId AND MemberPrincipalId = @UserId;
END;
GO

-- --------------------------------------------------------------------------------
-- App.UpsertOrgUnitSourceMap
-- Insert or update a source system mapping for an org unit
-- --------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE App.UpsertOrgUnitSourceMap
    @AccountCode        NVARCHAR(50),
    @OrgUnitCode        NVARCHAR(50),
    @OrgUnitType        NVARCHAR(20),
    @SourceSystem       NVARCHAR(100),
    @SourceOrgUnitId    NVARCHAR(100),
    @SourceOrgUnitName  NVARCHAR(200) = NULL,
    @IsActive           BIT = 1,
    @OrgUnitSourceMapId INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @AccountId INT = (SELECT AccountId FROM Dim.Account WHERE AccountCode = @AccountCode);
    IF @AccountId IS NULL
        THROW 50056, 'Account not found.', 1;

    DECLARE @OrgUnitId INT = (
        SELECT OrgUnitId FROM Dim.OrgUnit
        WHERE AccountId = @AccountId
          AND OrgUnitCode = @OrgUnitCode
          AND OrgUnitType = @OrgUnitType
    );
    IF @OrgUnitId IS NULL
        THROW 50057, 'Org unit not found.', 1;

    DECLARE @ExistingId INT = (
        SELECT OrgUnitSourceMapId FROM Dim.OrgUnitSourceMap
        WHERE SourceSystem = @SourceSystem
          AND SourceOrgUnitId = @SourceOrgUnitId
    );

    IF @ExistingId IS NULL
    BEGIN
        INSERT INTO Dim.OrgUnitSourceMap
            (OrgUnitId, SourceSystem, SourceOrgUnitId, SourceOrgUnitName, IsActive)
        VALUES
            (@OrgUnitId, @SourceSystem, @SourceOrgUnitId, @SourceOrgUnitName, @IsActive);

        SET @OrgUnitSourceMapId = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE Dim.OrgUnitSourceMap
        SET OrgUnitId        = @OrgUnitId,
            SourceOrgUnitName = @SourceOrgUnitName,
            IsActive          = @IsActive,
            ModifiedOnUtc     = SYSUTCDATETIME()
        WHERE OrgUnitSourceMapId = @ExistingId;

        SET @OrgUnitSourceMapId = @ExistingId;
    END
END;
GO

-- --------------------------------------------------------------------------------
-- App.GrantAccess
-- Wrapper for granting access from PowerApps
-- Calls appropriate Sec.Grant* procedure based on parameters
-- --------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE App.GrantAccess
    @PrincipalType      NVARCHAR(10),
    @PrincipalIdentifier NVARCHAR(320),
    @GrantType          NVARCHAR(30),    -- GLOBAL_ALL | GLOBAL_PACKAGE | FULL_ACCOUNT | PATH_PREFIX | COUNTRY_ALL
    @PackageCode        NVARCHAR(50)  = NULL,
    @AccountCode        NVARCHAR(50)  = NULL,
    @OrgUnitType        NVARCHAR(20)  = NULL,
    @OrgUnitCode        NVARCHAR(50)  = NULL,
    @CountryCode        NVARCHAR(10)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @GrantType = 'GLOBAL_ALL'
    BEGIN
        EXEC Sec.GrantGlobalAllPackages
            @PrincipalType = @PrincipalType,
            @PrincipalIdentifier = @PrincipalIdentifier;

        EXEC Sec.GrantAllAccounts
            @PrincipalType = @PrincipalType,
            @PrincipalIdentifier = @PrincipalIdentifier;
    END
    ELSE IF @GrantType = 'GLOBAL_PACKAGE'
    BEGIN
        EXEC Sec.GrantGlobal
            @PrincipalType = @PrincipalType,
            @PrincipalIdentifier = @PrincipalIdentifier,
            @PackageCode = @PackageCode;
    END
    ELSE IF @GrantType = 'FULL_ACCOUNT'
    BEGIN
        EXEC Sec.GrantFullAccount
            @PrincipalType = @PrincipalType,
            @PrincipalIdentifier = @PrincipalIdentifier,
            @AccountCode = @AccountCode;
    END
    ELSE IF @GrantType = 'PATH_PREFIX'
    BEGIN
        EXEC Sec.GrantPathPrefix
            @PrincipalType = @PrincipalType,
            @PrincipalIdentifier = @PrincipalIdentifier,
            @AccountCode = @AccountCode,
            @OrgUnitType = @OrgUnitType,
            @OrgUnitCode = @OrgUnitCode;
    END
    ELSE IF @GrantType = 'COUNTRY_ALL'
    BEGIN
        EXEC Sec.GrantCountryAllAccounts
            @PrincipalType = @PrincipalType,
            @PrincipalIdentifier = @PrincipalIdentifier,
            @CountryCode = @CountryCode;
    END
    ELSE
        THROW 50060, 'Invalid GrantType provided.', 1;
END;
GO

-- --------------------------------------------------------------------------------
-- App.RevokeAccess
-- Remove a specific access grant from a principal
-- --------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE App.RevokeAccess
    @PrincipalAccessGrantId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM Sec.PrincipalAccessGrant
        WHERE PrincipalAccessGrantId = @PrincipalAccessGrantId
    )
        THROW 50061, 'Access grant not found.', 1;

    DELETE FROM Sec.PrincipalAccessGrant
    WHERE PrincipalAccessGrantId = @PrincipalAccessGrantId;
END;
GO

-- --------------------------------------------------------------------------------
-- App.RevokePackageGrant
-- Remove a specific package grant from a principal
-- --------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE App.RevokePackageGrant
    @PrincipalPackageGrantId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM Sec.PrincipalPackageGrant
        WHERE PrincipalPackageGrantId = @PrincipalPackageGrantId
    )
        THROW 50062, 'Package grant not found.', 1;

    DELETE FROM Sec.PrincipalPackageGrant
    WHERE PrincipalPackageGrantId = @PrincipalPackageGrantId;
END;
GO

-- --------------------------------------------------------------------------------
-- App.GetUserEffectiveAccess
-- Returns effective site + report access for a given user UPN
-- Used by: scrUserDetail (A-12), coverage map screens
-- --------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE App.GetUserEffectiveAccess
    @UserUPN NVARCHAR(320)
AS
BEGIN
    SET NOCOUNT ON;

    -- Effective sites
    SELECT
        auth.AccountCode,
        auth.AccountName,
        auth.SiteCode,
        auth.SiteName,
        auth.CountryCode,
        auth.Path,
        auth.SourceSystem,
        auth.SourceOrgUnitId,
        auth.SourceOrgUnitName
    FROM Sec.vAuthorizedSitesDynamic AS auth
    WHERE auth.UserUPN = @UserUPN
    ORDER BY auth.AccountCode, auth.SiteCode;

    -- Effective reports
    SELECT
        auth.PackageCode,
        auth.PackageName,
        auth.ReportCode,
        auth.ReportName
    FROM Sec.vAuthorizedReportsDynamic AS auth
    WHERE auth.UserUPN = @UserUPN
    ORDER BY auth.PackageCode, auth.ReportCode;
END;
GO

PRINT 'AppViews.sql completed — all App views and stored procedures created.';

-- Optional helper to remove grants could be added later as needed.

PRINT 'Create.sql completed';
GO