/*
================================================================================
Baseline Create — Consolidated Final State
================================================================================
Description : Single-pass baseline DDL for the platform after applying
              migrations 001 through 008. This script creates objects directly
              in their latest intended shape instead of creating them first and
              altering them later.

Scope       : Dim, Sec, App, Audit, KPI, Workflow, Reporting
Safe to re-run : YES
================================================================================
*/
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
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Audit')
    EXEC ('CREATE SCHEMA Audit AUTHORIZATION dbo;');
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'KPI')
    EXEC ('CREATE SCHEMA KPI AUTHORIZATION dbo;');
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Workflow')
    EXEC ('CREATE SCHEMA Workflow AUTHORIZATION dbo;');
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Reporting')
    EXEC ('CREATE SCHEMA Reporting AUTHORIZATION dbo;');
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

IF OBJECT_ID('Dim.SharedGeoUnit', 'U') IS NULL
BEGIN
    CREATE TABLE Dim.SharedGeoUnit
    (
        SharedGeoUnitId  INT IDENTITY(1,1)  NOT NULL PRIMARY KEY,
        GeoUnitType      NVARCHAR(20)       NOT NULL,
        GeoUnitCode      NVARCHAR(50)       NOT NULL,
        GeoUnitName      NVARCHAR(200)      NOT NULL,
        CountryCode      NVARCHAR(10)       NULL,
        IsActive         BIT                NOT NULL CONSTRAINT DF_SharedGeoUnit_IsActive DEFAULT (1),
        CreatedOnUtc     DATETIME2          NOT NULL CONSTRAINT DF_SharedGeoUnit_Created DEFAULT (SYSUTCDATETIME()),
        ModifiedOnUtc    DATETIME2          NOT NULL CONSTRAINT DF_SharedGeoUnit_Modified DEFAULT (SYSUTCDATETIME()),
        CreatedBy        NVARCHAR(128)      NOT NULL CONSTRAINT DF_SharedGeoUnit_CreatedBy DEFAULT (SESSION_USER),
        ModifiedBy       NVARCHAR(128)      NOT NULL CONSTRAINT DF_SharedGeoUnit_ModifiedBy DEFAULT (SESSION_USER)
    );

    ALTER TABLE Dim.SharedGeoUnit
        ADD CONSTRAINT CK_SharedGeoUnit_Type CHECK (GeoUnitType IN ('Region','SubRegion','Cluster','Country'));

    CREATE UNIQUE INDEX UX_SharedGeoUnit_Code ON Dim.SharedGeoUnit (GeoUnitType, GeoUnitCode);
    CREATE INDEX IX_SharedGeoUnit_CountryCode ON Dim.SharedGeoUnit (CountryCode) WHERE CountryCode IS NOT NULL;
END;
GO

IF OBJECT_ID('Dim.OrgUnit', 'U') IS NULL
BEGIN
    CREATE TABLE Dim.OrgUnit
    (
        OrgUnitId          INT IDENTITY(1,1)  NOT NULL PRIMARY KEY,
        AccountId          INT                NOT NULL,
        SharedGeoUnitId    INT                NULL,
        CountryOrgUnitId   INT                NULL,
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
        CONSTRAINT FK_OrgUnit_Parent FOREIGN KEY (ParentOrgUnitId) REFERENCES Dim.OrgUnit (OrgUnitId),
        CONSTRAINT FK_OrgUnit_SharedGeo FOREIGN KEY (SharedGeoUnitId) REFERENCES Dim.SharedGeoUnit (SharedGeoUnitId),
        CONSTRAINT FK_OrgUnit_Country FOREIGN KEY (CountryOrgUnitId) REFERENCES Dim.OrgUnit (OrgUnitId)
    );

    ALTER TABLE Dim.OrgUnit
        ADD CONSTRAINT CK_OrgUnit_Type CHECK (OrgUnitType IN ('Region','SubRegion','Cluster','Country','Area','Branch','Site'));

    ALTER TABLE Dim.OrgUnit
        ADD CONSTRAINT CK_OrgUnit_SharedLink CHECK
        (
            (OrgUnitType IN ('Region','SubRegion','Cluster','Country') AND SharedGeoUnitId IS NOT NULL)
            OR
            (OrgUnitType IN ('Area','Branch','Site') AND SharedGeoUnitId IS NULL)
        );

    ALTER TABLE Dim.OrgUnit
        ADD CONSTRAINT CK_OrgUnit_CountryLink CHECK
        (
            (OrgUnitType IN ('Area','Branch','Site') AND CountryOrgUnitId IS NOT NULL)
            OR
            (OrgUnitType IN ('Region','SubRegion','Cluster','Country') AND CountryOrgUnitId IS NULL)
        );

    CREATE UNIQUE INDEX UX_OrgUnit_Path ON Dim.OrgUnit (Path);
    CREATE UNIQUE INDEX UX_OrgUnit_CodePerAccount ON Dim.OrgUnit (AccountId, OrgUnitType, OrgUnitCode);
    CREATE UNIQUE INDEX UX_OrgUnit_SharedGeoPerAccount
        ON Dim.OrgUnit (AccountId, SharedGeoUnitId)
        WHERE SharedGeoUnitId IS NOT NULL;
    CREATE INDEX IX_OrgUnit_Parent ON Dim.OrgUnit (ParentOrgUnitId);
    CREATE INDEX IX_OrgUnit_SharedGeo ON Dim.OrgUnit (SharedGeoUnitId) WHERE SharedGeoUnitId IS NOT NULL;
    CREATE INDEX IX_OrgUnit_Country ON Dim.OrgUnit (CountryOrgUnitId) WHERE CountryOrgUnitId IS NOT NULL;
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
        EntraObjectId   NVARCHAR(128)   NULL,
        UserType        NVARCHAR(20)    NOT NULL CONSTRAINT DF_User_UserType DEFAULT ('External'),
        IsActive        BIT             NOT NULL CONSTRAINT DF_User_UserIsActive DEFAULT (1),
        LastLoginAt     DATETIME2       NULL,
        InvitedAt       DATETIME2       NULL,
        InvitedBy       NVARCHAR(128)   NULL,
        CreatedOnUtc    DATETIME2       NOT NULL CONSTRAINT DF_User_Created DEFAULT (SYSUTCDATETIME()),
        ModifiedOnUtc   DATETIME2       NOT NULL CONSTRAINT DF_User_Modified DEFAULT (SYSUTCDATETIME()),
        CreatedBy       NVARCHAR(128)   NOT NULL CONSTRAINT DF_User_CreatedBy DEFAULT (SESSION_USER),
        ModifiedBy      NVARCHAR(128)   NOT NULL CONSTRAINT DF_User_ModifiedBy DEFAULT (SESSION_USER),
        CONSTRAINT FK_User_Principal FOREIGN KEY (UserId) REFERENCES Sec.Principal (PrincipalId),
        CONSTRAINT CK_User_UserType CHECK (UserType IN ('Internal','External'))
    );

    CREATE UNIQUE INDEX UX_User_UPN ON Sec.[User] (UPN);
    CREATE UNIQUE INDEX UQ_User_EntraObjectId
        ON Sec.[User] (EntraObjectId)
        WHERE EntraObjectId IS NOT NULL;
    CREATE INDEX IX_User_IsActive ON Sec.[User] (IsActive);
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
        PrincipalId         INT             NOT NULL,
        PackageId           INT             NULL,
        GrantScope          NVARCHAR(30)    NOT NULL,
        GrantedOnUtc        DATETIME2       NOT NULL CONSTRAINT DF_PrincipalPackageGrant_Created DEFAULT (SYSUTCDATETIME()),
        GrantedByPrincipalId INT            NULL,
        ExpiresAt           DATETIME2       NULL,
        RevokedAt           DATETIME2       NULL,
        RevokedByPrincipalId INT            NULL,
        ModifiedOnUtc       DATETIME2       NOT NULL CONSTRAINT DF_PrincipalPackageGrant_Modified DEFAULT (SYSUTCDATETIME()),
        CreatedBy           NVARCHAR(128)   NOT NULL CONSTRAINT DF_PrincipalPackageGrant_CreatedBy DEFAULT (SESSION_USER),
        ModifiedBy          NVARCHAR(128)   NOT NULL CONSTRAINT DF_PrincipalPackageGrant_ModifiedBy DEFAULT (SESSION_USER),
        CONSTRAINT FK_PackageGrant_Principal FOREIGN KEY (PrincipalId) REFERENCES Sec.Principal (PrincipalId),
        CONSTRAINT FK_PackageGrant_Package FOREIGN KEY (PackageId) REFERENCES Dim.Package (PackageId),
        CONSTRAINT FK_PackageGrant_GrantedBy FOREIGN KEY (GrantedByPrincipalId) REFERENCES Sec.Principal (PrincipalId),
        CONSTRAINT FK_PackageGrant_RevokedBy FOREIGN KEY (RevokedByPrincipalId) REFERENCES Sec.Principal (PrincipalId),
        CONSTRAINT CK_PackageGrant_Scope CHECK (GrantScope IN ('ALL_PACKAGES','PACKAGE')),
        CONSTRAINT CK_PackageGrant_Package CHECK ((GrantScope = 'ALL_PACKAGES' AND PackageId IS NULL) OR (GrantScope = 'PACKAGE' AND PackageId IS NOT NULL))
    );

    CREATE UNIQUE INDEX UX_PackageGrant ON Sec.PrincipalPackageGrant (PrincipalId, GrantScope, PackageId);
    CREATE INDEX IX_PackageGrant_Active
        ON Sec.PrincipalPackageGrant (PrincipalId, GrantScope)
        WHERE RevokedAt IS NULL;
END;
GO

IF OBJECT_ID('Sec.PrincipalAccessGrant', 'U') IS NULL
BEGIN
    CREATE TABLE Sec.PrincipalAccessGrant
    (
        PrincipalAccessGrantId INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        PrincipalId         INT             NOT NULL,
        AccessType          NVARCHAR(10)    NOT NULL,
        AccountId           INT             NULL,
        ScopeType           NVARCHAR(15)    NOT NULL,
        OrgUnitId           INT             NULL,
        GrantedOnUtc        DATETIME2       NOT NULL CONSTRAINT DF_PrincipalAccessGrant_Created DEFAULT (SYSUTCDATETIME()),
        GrantedByPrincipalId INT            NULL,
        ExpiresAt           DATETIME2       NULL,
        RevokedAt           DATETIME2       NULL,
        RevokedByPrincipalId INT            NULL,
        ModifiedOnUtc       DATETIME2       NOT NULL CONSTRAINT DF_PrincipalAccessGrant_Modified DEFAULT (SYSUTCDATETIME()),
        CreatedBy           NVARCHAR(128)   NOT NULL CONSTRAINT DF_PrincipalAccessGrant_CreatedBy DEFAULT (SESSION_USER),
        ModifiedBy          NVARCHAR(128)   NOT NULL CONSTRAINT DF_PrincipalAccessGrant_ModifiedBy DEFAULT (SESSION_USER),
        CONSTRAINT FK_PrincipalAccessGrant_Principal FOREIGN KEY (PrincipalId) REFERENCES Sec.Principal (PrincipalId),
        CONSTRAINT FK_PrincipalAccessGrant_Account FOREIGN KEY (AccountId) REFERENCES Dim.Account (AccountId),
        CONSTRAINT FK_PrincipalAccessGrant_OrgUnit FOREIGN KEY (OrgUnitId) REFERENCES Dim.OrgUnit (OrgUnitId),
        CONSTRAINT FK_AccessGrant_GrantedBy FOREIGN KEY (GrantedByPrincipalId) REFERENCES Sec.Principal (PrincipalId),
        CONSTRAINT FK_AccessGrant_RevokedBy FOREIGN KEY (RevokedByPrincipalId) REFERENCES Sec.Principal (PrincipalId),
        CONSTRAINT CK_PrincipalAccessGrant_AccessType CHECK (AccessType IN ('ALL','ACCOUNT')),
        CONSTRAINT CK_PrincipalAccessGrant_ScopeType CHECK (ScopeType IN ('NONE','ORGUNIT')),
        CONSTRAINT CK_PrincipalAccessGrant_AllAccount CHECK ((AccessType = 'ALL' AND AccountId IS NULL) OR (AccessType = 'ACCOUNT' AND AccountId IS NOT NULL)),
        CONSTRAINT CK_PrincipalAccessGrant_ScopeFields CHECK (
            (ScopeType = 'NONE'    AND OrgUnitId IS NULL) OR
            (ScopeType = 'ORGUNIT' AND OrgUnitId IS NOT NULL)
        )
    );

    CREATE INDEX IX_PrincipalAccessGrant_Principal ON Sec.PrincipalAccessGrant (PrincipalId);
    CREATE INDEX IX_PrincipalAccessGrant_Scope ON Sec.PrincipalAccessGrant (ScopeType, OrgUnitId);
    CREATE INDEX IX_AccessGrant_Active
        ON Sec.PrincipalAccessGrant (PrincipalId, AccessType, AccountId, ScopeType)
        WHERE RevokedAt IS NULL;
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
      -- Templates support tokens: {AccountCode}, {AccountName}, {OrgUnitCode}, and {OrgUnitName}
      RoleCodeTemplate    NVARCHAR(100) NOT NULL,  -- e.g. '{AccountCode}_GAD'
      RoleNameTemplate    NVARCHAR(200) NOT NULL,  -- e.g. '{AccountName} Global Account Director'
      ScopeType           NVARCHAR(15)  NOT NULL CONSTRAINT CK_AccRolePolicy_Scope CHECK (ScopeType IN ('NONE','ORGUNIT')),
      OrgUnitType         NVARCHAR(20)  NULL,
      OrgUnitCode         NVARCHAR(50)  NULL,
      ExpandPerOrgUnit    BIT NOT NULL CONSTRAINT DF_AccRolePolicy_ExpandPerOrgUnit DEFAULT(0),
      IsActive            BIT NOT NULL CONSTRAINT DF_AccRolePolicy_IsActive DEFAULT(1),
      CreatedOnUtc        DATETIME2 NOT NULL CONSTRAINT DF_AccRolePolicy_Created DEFAULT (SYSUTCDATETIME()),
      ModifiedOnUtc       DATETIME2 NOT NULL CONSTRAINT DF_AccRolePolicy_Mod DEFAULT (SYSUTCDATETIME())
  );

END;

IF COL_LENGTH('Sec.AccountRolePolicy', 'ExpandPerOrgUnit') IS NULL
BEGIN
    ALTER TABLE Sec.AccountRolePolicy
        ADD ExpandPerOrgUnit BIT NOT NULL
            CONSTRAINT DF_AccRolePolicy_ExpandPerOrgUnit DEFAULT(0);
END;

IF EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('Sec.AccountRolePolicy')
      AND name = 'UX_AccountRolePolicy_Unique'
)
BEGIN
    DROP INDEX UX_AccountRolePolicy_Unique ON Sec.AccountRolePolicy;
END;

CREATE UNIQUE INDEX UX_AccountRolePolicy_Unique
  ON Sec.AccountRolePolicy (RoleCodeTemplate, ScopeType, OrgUnitType, OrgUnitCode, ExpandPerOrgUnit)
  WHERE IsActive = 1;
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
CREATE OR ALTER VIEW Sec.vPrincipalEffectiveAccess
AS
    -- Direct grants (active only)
    SELECT
        pag.PrincipalId,
        pag.AccessType,
        pag.AccountId,
        pag.ScopeType,
        pag.OrgUnitId
    FROM Sec.PrincipalAccessGrant AS pag
    WHERE pag.RevokedAt IS NULL
      AND (pag.ExpiresAt IS NULL OR pag.ExpiresAt > SYSUTCDATETIME())

    UNION ALL

    -- Active delegations
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
    JOIN Sec.Principal AS up
        ON up.PrincipalId = u.UserId
    WHERE u.IsActive = 1
      AND up.IsActive = 1
    UNION
    SELECT
        rm.MemberPrincipalId AS UserPrincipalId,
        rm.RoleId            AS GrantPrincipalId
    FROM Sec.RoleMembership AS rm
    JOIN Sec.[User] AS u
        ON u.UserId = rm.MemberPrincipalId
    JOIN Sec.Principal AS up
        ON up.PrincipalId = rm.MemberPrincipalId
    JOIN Sec.Principal AS rp
        ON rp.PrincipalId = rm.RoleId
    WHERE u.IsActive = 1
      AND up.IsActive = 1
      AND rp.IsActive = 1;
GO

CREATE OR ALTER VIEW Sec.vPrincipalPackageAccess
AS
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
               OR (ppg.GrantScope = 'PACKAGE'      AND p.PackageId = ppg.PackageId AND p.IsActive = 1)
        ) AS pkg
        WHERE ppg.RevokedAt IS NULL
          AND (ppg.ExpiresAt IS NULL OR ppg.ExpiresAt > SYSUTCDATETIME())
    )
    SELECT DISTINCT
        PrincipalId,
        PackageId,
        PackageCode,
        PackageName,
        GrantScope
    FROM Expanded;
GO

CREATE OR ALTER VIEW Sec.vAuthorizedSitesDynamic
AS
    WITH Grants AS
    (
        -- Route through vPrincipalEffectiveAccess (already filters revoked + expired)
        SELECT
            up.UserPrincipalId,
            eff.AccessType,
            eff.AccountId,
            eff.ScopeType,
            eff.OrgUnitId
        FROM Sec.vUserGrantPrincipals     AS up
        JOIN Sec.vPrincipalEffectiveAccess AS eff
            ON up.GrantPrincipalId = eff.PrincipalId
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
        u.UserId                AS UserPrincipalId,
        u.UPN                   AS UserUPN,
        acct.AccountId,
        acct.AccountCode,
        acct.AccountName,
        site.OrgUnitId          AS SiteOrgUnitId,
        site.OrgUnitCode        AS SiteCode,
        site.OrgUnitName        AS SiteName,
        site.CountryCode,
        site.Path,
        map.SourceSystem,
        map.SourceOrgUnitId,
        map.SourceOrgUnitName
    FROM Expanded AS es
    JOIN Sec.[User]    AS u    ON es.UserPrincipalId = u.UserId
    JOIN Dim.OrgUnit   AS site ON es.OrgUnitId       = site.OrgUnitId
    JOIN Dim.Account   AS acct ON site.AccountId     = acct.AccountId
    LEFT JOIN Dim.OrgUnitSourceMap AS map
        ON map.OrgUnitId = site.OrgUnitId
       AND map.IsActive  = 1;
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
CREATE OR ALTER VIEW App.vUsers
AS
    SELECT
        u.UserId,
        u.UPN,
        p.PrincipalName                     AS DisplayName,
        u.IsActive                          AS IsActive,
        p.IsActive                          AS PrincipalIsActive,
        u.IsActive                          AS UserIsActive,
        u.UserType,
        u.EntraObjectId,
        u.LastLoginAt,
        u.InvitedAt,
        u.InvitedBy,
        u.CreatedOnUtc,
        u.ModifiedOnUtc,
        ISNULL(roles.RoleCount,  0)         AS RoleCount,
        ISNULL(roles.RoleList,   '')        AS RoleList,
        ISNULL(coverage.SiteCount,    0)    AS SiteCount,
        ISNULL(coverage.AccountCount, 0)    AS AccountCount,
        ISNULL(coverage.PackageCount, 0)    AS PackageCount,
        ISNULL(coverage.ReportCount,  0)    AS ReportCount,
        CASE
            WHEN ISNULL(coverage.SiteCount,    0) > 0
             AND ISNULL(coverage.PackageCount, 0) = 0 THEN 'Packages without sites'
            WHEN ISNULL(coverage.PackageCount, 0) > 0
             AND ISNULL(coverage.SiteCount,    0) = 0 THEN 'Sites without packages'
            ELSE 'OK'
        END AS GapStatus
    FROM Sec.[User] AS u
    JOIN Sec.Principal AS p ON p.PrincipalId = u.UserId
    OUTER APPLY
    (
        SELECT
            COUNT(DISTINCT rm.RoleId)       AS RoleCount,
            STRING_AGG(r.RoleName, ', ')    AS RoleList
        FROM Sec.RoleMembership AS rm
        JOIN Sec.Role AS r ON r.RoleId = rm.RoleId
        WHERE rm.MemberPrincipalId = u.UserId
    ) AS roles
    OUTER APPLY
    (
        SELECT
            COUNT(DISTINCT s.SiteOrgUnitId) AS SiteCount,
            COUNT(DISTINCT s.AccountId)     AS AccountCount,
            COUNT(DISTINCT r.PackageId)     AS PackageCount,
            COUNT(DISTINCT r.BiReportId)    AS ReportCount
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
    LEFT JOIN Dim.OrgUnit AS ou ON ou.OrgUnitId = pag.OrgUnitId
    WHERE pag.RevokedAt IS NULL;
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
    LEFT JOIN Dim.Package AS pkg ON pkg.PackageId = ppg.PackageId
    WHERE ppg.RevokedAt IS NULL;
GO

CREATE OR ALTER VIEW App.vGrantHistory
AS
    -- Access grant history
    SELECT
        pag.PrincipalAccessGrantId  AS GrantId,
        'Access'                    AS GrantType,
        p.PrincipalType,
        p.PrincipalName,
        pag.AccessType,
        pag.ScopeType,
        ISNULL(a.AccountCode,  'ALL')           AS AccountCode,
        ISNULL(ou.OrgUnitCode, 'N/A')           AS OrgUnitCode,
        ISNULL(ou.OrgUnitType, 'N/A')           AS OrgUnitType,
        NULL                                     AS PackageCode,
        pag.GrantedOnUtc,
        grantor.PrincipalName                   AS GrantedByName,
        pag.ExpiresAt,
        pag.RevokedAt,
        revoker.PrincipalName                   AS RevokedByName,
        CASE WHEN pag.RevokedAt IS NOT NULL              THEN 'Revoked'
             WHEN pag.ExpiresAt < SYSUTCDATETIME()       THEN 'Expired'
             ELSE 'Active'
        END AS GrantStatus
    FROM Sec.PrincipalAccessGrant AS pag
    JOIN Sec.Principal AS p         ON p.PrincipalId       = pag.PrincipalId
    LEFT JOIN Dim.Account AS a      ON a.AccountId         = pag.AccountId
    LEFT JOIN Dim.OrgUnit AS ou     ON ou.OrgUnitId        = pag.OrgUnitId
    LEFT JOIN Sec.Principal AS grantor ON grantor.PrincipalId = pag.GrantedByPrincipalId
    LEFT JOIN Sec.Principal AS revoker ON revoker.PrincipalId = pag.RevokedByPrincipalId

    UNION ALL

    -- Package grant history
    SELECT
        ppg.PrincipalPackageGrantId AS GrantId,
        'Package'                   AS GrantType,
        p.PrincipalType,
        p.PrincipalName,
        ppg.GrantScope              AS AccessType,
        NULL                        AS ScopeType,
        NULL                        AS AccountCode,
        NULL                        AS OrgUnitCode,
        NULL                        AS OrgUnitType,
        ISNULL(pkg.PackageCode, 'ALL') AS PackageCode,
        ppg.GrantedOnUtc,
        grantor.PrincipalName       AS GrantedByName,
        ppg.ExpiresAt,
        ppg.RevokedAt,
        revoker.PrincipalName       AS RevokedByName,
        CASE WHEN ppg.RevokedAt IS NOT NULL              THEN 'Revoked'
             WHEN ppg.ExpiresAt < SYSUTCDATETIME()       THEN 'Expired'
             ELSE 'Active'
        END AS GrantStatus
    FROM Sec.PrincipalPackageGrant AS ppg
    JOIN Sec.Principal AS p            ON p.PrincipalId       = ppg.PrincipalId
    LEFT JOIN Dim.Package AS pkg       ON pkg.PackageId        = ppg.PackageId
    LEFT JOIN Sec.Principal AS grantor ON grantor.PrincipalId  = ppg.GrantedByPrincipalId
    LEFT JOIN Sec.Principal AS revoker ON revoker.PrincipalId  = ppg.RevokedByPrincipalId;
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
-- App.vSharedGeoUnits
-- Canonical shared geography repository
-- --------------------------------------------------------------------------------
IF OBJECT_ID('App.vSharedGeoUnits', 'V') IS NOT NULL
    DROP VIEW App.vSharedGeoUnits;
GO
CREATE OR ALTER VIEW App.vSharedGeoUnits
AS
    SELECT
        sgu.SharedGeoUnitId,
        sgu.GeoUnitType,
        sgu.GeoUnitCode,
        sgu.GeoUnitName,
        sgu.CountryCode,
        sgu.IsActive,
        sgu.CreatedOnUtc,
        sgu.ModifiedOnUtc
    FROM Dim.SharedGeoUnit AS sgu;
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
        ou.SharedGeoUnitId,
        sgu.GeoUnitCode            AS SharedGeoUnitCode,
        sgu.GeoUnitName            AS SharedGeoUnitName,
        ou.CountryOrgUnitId,
        ctry.OrgUnitCode           AS CountryOrgUnitCode,
        ctry.OrgUnitName           AS CountryOrgUnitName,
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
    LEFT JOIN Dim.SharedGeoUnit AS sgu ON sgu.SharedGeoUnitId = ou.SharedGeoUnitId
    LEFT JOIN Dim.OrgUnit AS ctry ON ctry.OrgUnitId = ou.CountryOrgUnitId
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
        ou.SharedGeoUnitId,
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
    LEFT JOIN Dim.Account AS a  ON a.AccountId  = ou.AccountId;
GO

-- --------------------------------------------------------------------------------
-- App.vPrincipals
-- All principals (users and roles) for dropdowns
-- Used by: grant wizards, delegation screens
-- --------------------------------------------------------------------------------
CREATE OR ALTER VIEW App.vPrincipals
AS
    SELECT
        p.PrincipalId,
        p.PrincipalType,
        p.PrincipalName,
        p.IsActive,
        u.UPN,
        u.UserType,
        u.IsActive      AS UserIsActive,
        u.LastLoginAt,
        r.RoleCode
    FROM Sec.Principal AS p
    LEFT JOIN Sec.[User] AS u ON u.UserId    = p.PrincipalId
    LEFT JOIN Sec.Role   AS r ON r.RoleId    = p.PrincipalId;
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

CREATE OR ALTER PROCEDURE App.UpsertSharedGeoUnit
    @GeoUnitType            NVARCHAR(20),
    @GeoUnitCode            NVARCHAR(50),
    @GeoUnitName            NVARCHAR(200),
    @CountryCode            NVARCHAR(10) = NULL,
    @IsActive               BIT = 1,
    @ExistingSharedGeoUnitId INT = NULL,
    @SharedGeoUnitId        INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF @GeoUnitType NOT IN ('Region','SubRegion','Cluster','Country')
        THROW 50060, 'Shared geography type must be Region, SubRegion, Cluster, or Country.', 1;

    IF @GeoUnitType = 'Country' AND @CountryCode IS NULL
        THROW 50072, 'CountryCode is required when GeoUnitType is Country.', 1;

    IF @GeoUnitType <> 'Country'
        SET @CountryCode = NULL;

    DECLARE @ExistingId INT = NULL;

    IF @ExistingSharedGeoUnitId IS NOT NULL
    BEGIN
        IF NOT EXISTS (
            SELECT 1
            FROM Dim.SharedGeoUnit
            WHERE SharedGeoUnitId = @ExistingSharedGeoUnitId
        )
            THROW 50076, 'SharedGeoUnitId not found for update.', 1;

        IF EXISTS (
            SELECT 1
            FROM Dim.SharedGeoUnit
            WHERE GeoUnitType = @GeoUnitType
              AND GeoUnitCode = @GeoUnitCode
              AND SharedGeoUnitId <> @ExistingSharedGeoUnitId
        )
            THROW 50077, 'Another shared geography item already uses this type/code.', 1;

        SET @ExistingId = @ExistingSharedGeoUnitId;
    END
    ELSE
    BEGIN
        SET @ExistingId = (
            SELECT SharedGeoUnitId
            FROM Dim.SharedGeoUnit
            WHERE GeoUnitType = @GeoUnitType
              AND GeoUnitCode = @GeoUnitCode
        );
    END

    IF @ExistingId IS NULL
    BEGIN
        INSERT INTO Dim.SharedGeoUnit
            (GeoUnitType, GeoUnitCode, GeoUnitName, CountryCode, IsActive)
        VALUES
            (@GeoUnitType, @GeoUnitCode, @GeoUnitName,
             CASE WHEN @GeoUnitType = 'Country' THEN @CountryCode ELSE NULL END,
             @IsActive);

        SET @SharedGeoUnitId = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE Dim.SharedGeoUnit
        SET GeoUnitName = @GeoUnitName,
            CountryCode = CASE WHEN @GeoUnitType = 'Country' THEN @CountryCode ELSE NULL END,
            IsActive = @IsActive,
            ModifiedOnUtc = SYSUTCDATETIME(),
            ModifiedBy = SESSION_USER
        WHERE SharedGeoUnitId = @ExistingId;

        SET @SharedGeoUnitId = @ExistingId;
    END
END;
GO

CREATE OR ALTER PROCEDURE App.AttachSharedGeoUnitToAccount
    @AccountCode       NVARCHAR(50),
    @SharedGeoUnitId   INT,
    @ParentOrgUnitType NVARCHAR(20) = NULL,
    @ParentOrgUnitCode NVARCHAR(50) = NULL,
    @ApplyPolicies     BIT = 0,
    @OrgUnitId         INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @AccountId INT = (SELECT AccountId FROM Dim.Account WHERE AccountCode = @AccountCode);
    IF @AccountId IS NULL
        THROW 50001, 'Account not found for provided AccountCode.', 1;

    DECLARE
        @GeoUnitType NVARCHAR(20),
        @GeoUnitCode NVARCHAR(50),
        @GeoUnitName NVARCHAR(200),
        @CountryCode NVARCHAR(10);

    SELECT
        @GeoUnitType = GeoUnitType,
        @GeoUnitCode = GeoUnitCode,
        @GeoUnitName = GeoUnitName,
        @CountryCode = CountryCode
    FROM Dim.SharedGeoUnit
    WHERE SharedGeoUnitId = @SharedGeoUnitId;

    IF @GeoUnitType IS NULL
        THROW 50063, 'Shared geography not found.', 1;

    SELECT @OrgUnitId = OrgUnitId
    FROM Dim.OrgUnit
    WHERE AccountId = @AccountId
      AND SharedGeoUnitId = @SharedGeoUnitId;

    IF @OrgUnitId IS NOT NULL
    BEGIN
        UPDATE Dim.OrgUnit
        SET OrgUnitType = @GeoUnitType,
            OrgUnitCode = @GeoUnitCode,
            OrgUnitName = @GeoUnitName,
            CountryCode = CASE WHEN @GeoUnitType = 'Country' THEN @CountryCode ELSE NULL END,
            IsActive = 1,
            ModifiedOnUtc = SYSUTCDATETIME(),
            ModifiedBy = SESSION_USER
        WHERE OrgUnitId = @OrgUnitId;

        IF @ApplyPolicies = 1
            EXEC App.ApplyAccountPolicies @AccountCode = @AccountCode, @ApplyAccess = 1, @ApplyPackages = 1;
        RETURN;
    END

    DECLARE @AllowedParentTypes NVARCHAR(200) = CASE @GeoUnitType
        WHEN 'Region'    THEN ''
        WHEN 'SubRegion' THEN 'Region'
        WHEN 'Cluster'   THEN 'Region,SubRegion'
        WHEN 'Country'   THEN 'Region,SubRegion,Cluster'
        ELSE ''
    END;

    DECLARE @ParentOrgUnitId INT = NULL;
    DECLARE @ParentPath NVARCHAR(850) = NULL;

    IF @GeoUnitType = 'Region'
    BEGIN
        IF @ParentOrgUnitType IS NOT NULL OR @ParentOrgUnitCode IS NOT NULL
            THROW 50061, 'Region org units cannot have a parent org unit.', 1;
    END
    ELSE
    BEGIN
        IF @ParentOrgUnitType IS NULL OR @ParentOrgUnitCode IS NULL
            THROW 50062, 'Parent org unit is required for SubRegion, Cluster, and Country.', 1;

        IF CHARINDEX(@ParentOrgUnitType, @AllowedParentTypes) = 0
            THROW 50073, 'Invalid parent type for the selected shared geography type.', 1;

        SELECT
            @ParentOrgUnitId = OrgUnitId,
            @ParentPath = Path
        FROM Dim.OrgUnit
        WHERE AccountId = @AccountId
          AND OrgUnitType = @ParentOrgUnitType
          AND OrgUnitCode = @ParentOrgUnitCode;

        IF @ParentOrgUnitId IS NULL
            THROW 50074, 'Parent org unit not found for the selected account hierarchy.', 1;
    END

    DECLARE @Path NVARCHAR(850) = CASE
        WHEN @ParentOrgUnitId IS NULL THEN CONCAT('|', @AccountCode, '|', @GeoUnitCode, '|')
        ELSE CONCAT(@ParentPath, @GeoUnitCode, '|')
    END;

    INSERT INTO Dim.OrgUnit
        (AccountId, SharedGeoUnitId, CountryOrgUnitId, OrgUnitType, OrgUnitCode, OrgUnitName, ParentOrgUnitId, Path, CountryCode, IsActive)
    VALUES
        (@AccountId, @SharedGeoUnitId, NULL, @GeoUnitType, @GeoUnitCode, @GeoUnitName, @ParentOrgUnitId, @Path,
         CASE WHEN @GeoUnitType = 'Country' THEN @CountryCode ELSE NULL END,
         1);

    SET @OrgUnitId = SCOPE_IDENTITY();

    IF @ApplyPolicies = 1
        EXEC App.ApplyAccountPolicies @AccountCode = @AccountCode, @ApplyAccess = 1, @ApplyPackages = 1;
END;
GO

-- Inserts or updates a local account org unit (Area / Branch / Site)
CREATE OR ALTER PROCEDURE App.InsertOrgUnit
    @AccountCode            NVARCHAR(50),
    @OrgUnitType            NVARCHAR(20),
    @OrgUnitCode            NVARCHAR(50),
    @OrgUnitName            NVARCHAR(200),
    @ParentOrgUnitType      NVARCHAR(20) = NULL,
    @ParentOrgUnitCode      NVARCHAR(50) = NULL,
    @CountrySharedGeoUnitId INT = NULL,
    @IsActive               BIT = 1,
    @ApplyPolicies          BIT = 0,
    @OrgUnitId              INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF @OrgUnitType NOT IN ('Area','Branch','Site')
        THROW 50064, 'App.InsertOrgUnit only accepts Area, Branch, or Site.', 1;

    DECLARE @AccountId INT = (SELECT AccountId FROM Dim.Account WHERE AccountCode = @AccountCode);
    IF @AccountId IS NULL
        THROW 50001, 'Account not found for provided AccountCode.', 1;

    DECLARE @ParentOrgUnitId INT = NULL;
    DECLARE @ParentPath NVARCHAR(850) = NULL;
    DECLARE @ParentCountryOrgUnitId INT = NULL;

    IF @ParentOrgUnitCode IS NOT NULL
    BEGIN
        SELECT
            @ParentOrgUnitId = OrgUnitId,
            @ParentPath = Path,
            @ParentCountryOrgUnitId = CountryOrgUnitId
        FROM Dim.OrgUnit
        WHERE AccountId = @AccountId
          AND OrgUnitType = @ParentOrgUnitType
          AND OrgUnitCode = @ParentOrgUnitCode;

        IF @ParentOrgUnitId IS NULL
            THROW 50002, 'Parent org unit not found for provided parameters.', 1;
    END

    DECLARE @AllowedParentTypes NVARCHAR(200) = CASE @OrgUnitType
        WHEN 'Area'   THEN 'Country'
        WHEN 'Branch' THEN 'Country,Area'
        WHEN 'Site'   THEN 'Country,Area,Branch'
        ELSE ''
    END;

    IF @ParentOrgUnitCode IS NULL OR @ParentOrgUnitType IS NULL
        THROW 50065, 'Parent org unit is required for Area, Branch, and Site.', 1;

    IF CHARINDEX(@ParentOrgUnitType, @AllowedParentTypes) = 0
        THROW 50066, 'Invalid parent type for the given org unit type.', 1;

    DECLARE @CountryOrgUnitId INT = NULL;
    IF @CountrySharedGeoUnitId IS NOT NULL
    BEGIN
        SELECT @CountryOrgUnitId = OrgUnitId
        FROM Dim.OrgUnit
        WHERE AccountId = @AccountId
          AND SharedGeoUnitId = @CountrySharedGeoUnitId
          AND OrgUnitType = 'Country';

        IF @CountryOrgUnitId IS NULL
            THROW 50067, 'CountrySharedGeoUnitId must reference an existing Country org unit for the account.', 1;
    END

    IF @CountryOrgUnitId IS NULL
    BEGIN
        SET @CountryOrgUnitId = CASE
            WHEN @ParentOrgUnitType = 'Country' THEN @ParentOrgUnitId
            ELSE @ParentCountryOrgUnitId
        END;
    END

    IF @CountryOrgUnitId IS NULL
        THROW 50068, 'A country selection is required for Area, Branch, and Site.', 1;

    IF @ParentOrgUnitType = 'Country' AND @ParentOrgUnitId <> @CountryOrgUnitId
        THROW 50069, 'Selected parent country does not match the chosen country.', 1;

    IF @ParentOrgUnitType IN ('Area','Branch') AND @ParentCountryOrgUnitId <> @CountryOrgUnitId
        THROW 50070, 'Parent org unit belongs to a different country.', 1;

    DECLARE @ExistingId INT = (
        SELECT OrgUnitId
        FROM Dim.OrgUnit
        WHERE AccountId = @AccountId
          AND OrgUnitType = @OrgUnitType
          AND OrgUnitCode = @OrgUnitCode
    );

    DECLARE @CountryCode NVARCHAR(10) = (
        SELECT CountryCode
        FROM Dim.OrgUnit
        WHERE OrgUnitId = @CountryOrgUnitId
    );

    DECLARE @Path NVARCHAR(850) = CONCAT(@ParentPath, @OrgUnitCode, '|');

    IF @ExistingId IS NULL
    BEGIN
        INSERT INTO Dim.OrgUnit
            (AccountId, SharedGeoUnitId, CountryOrgUnitId, OrgUnitType, OrgUnitCode, OrgUnitName, ParentOrgUnitId, Path, CountryCode, IsActive)
        VALUES
            (@AccountId, NULL, @CountryOrgUnitId, @OrgUnitType, @OrgUnitCode, @OrgUnitName, @ParentOrgUnitId, @Path, @CountryCode, @IsActive);

        SET @OrgUnitId = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE Dim.OrgUnit
        SET OrgUnitName = @OrgUnitName,
            ParentOrgUnitId = @ParentOrgUnitId,
            CountryOrgUnitId = @CountryOrgUnitId,
            Path = @Path,
            CountryCode = @CountryCode,
            IsActive = @IsActive,
            ModifiedOnUtc = SYSUTCDATETIME(),
            ModifiedBy = SESSION_USER
        WHERE OrgUnitId = @ExistingId;

        SET @OrgUnitId = @ExistingId;
    END

    IF @ApplyPolicies = 1
        EXEC App.ApplyAccountPolicies @AccountCode = @AccountCode, @ApplyAccess = 1, @ApplyPackages = 1;
END;
GO

-- Ensures full hierarchy exists for an account/shared geography/local operating path
CREATE OR ALTER PROCEDURE App.CreateOrEnsureSitePath
    @AccountCode    NVARCHAR(50),
    @RegionCode     NVARCHAR(50),
    @SubRegionCode  NVARCHAR(50) = NULL,
    @ClusterCode    NVARCHAR(50) = NULL,
    @CountryCode    NVARCHAR(10),
    @AreaCode       NVARCHAR(50) = NULL,
    @AreaName       NVARCHAR(200) = NULL,
    @BranchCode     NVARCHAR(50) = NULL,
    @BranchName     NVARCHAR(200) = NULL,
    @SiteCode       NVARCHAR(50),
    @SiteName       NVARCHAR(200),
    @ApplyPolicies  BIT = 0,
    @SiteOrgUnitId  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @RegionSharedGeoUnitId INT,
        @SubRegionSharedGeoUnitId INT,
        @ClusterSharedGeoUnitId INT,
        @CountrySharedGeoUnitId INT;

    SELECT @RegionSharedGeoUnitId = SharedGeoUnitId
    FROM Dim.SharedGeoUnit
    WHERE GeoUnitType = 'Region'
      AND GeoUnitCode = @RegionCode;

    IF @RegionSharedGeoUnitId IS NULL
        THROW 50071, 'Region not found in shared geography repository.', 1;

    IF @SubRegionCode IS NOT NULL
    BEGIN
        SELECT @SubRegionSharedGeoUnitId = SharedGeoUnitId
        FROM Dim.SharedGeoUnit
        WHERE GeoUnitType = 'SubRegion'
          AND GeoUnitCode = @SubRegionCode;

        IF @SubRegionSharedGeoUnitId IS NULL
            THROW 50073, 'SubRegion not found in shared geography repository.', 1;
    END

    IF @ClusterCode IS NOT NULL
    BEGIN
        SELECT @ClusterSharedGeoUnitId = SharedGeoUnitId
        FROM Dim.SharedGeoUnit
        WHERE GeoUnitType = 'Cluster'
          AND GeoUnitCode = @ClusterCode;

        IF @ClusterSharedGeoUnitId IS NULL
            THROW 50074, 'Cluster not found in shared geography repository.', 1;
    END

    SELECT @CountrySharedGeoUnitId = SharedGeoUnitId
    FROM Dim.SharedGeoUnit
    WHERE GeoUnitType = 'Country'
      AND GeoUnitCode = @CountryCode;

    IF @CountrySharedGeoUnitId IS NULL
        THROW 50075, 'Country not found in shared geography repository.', 1;

    DECLARE @RegionOrgUnitId INT;
    DECLARE @SubRegionOrgUnitId INT;
    DECLARE @ClusterOrgUnitId INT;
    DECLARE @CountryOrgUnitId INT;
    DECLARE @ClusterParentType NVARCHAR(20);
    DECLARE @ClusterParentCode NVARCHAR(50);
    DECLARE @CountryParentType NVARCHAR(20);
    DECLARE @CountryParentCode NVARCHAR(50);

    EXEC App.AttachSharedGeoUnitToAccount
        @AccountCode = @AccountCode,
        @SharedGeoUnitId = @RegionSharedGeoUnitId,
        @ParentOrgUnitType = NULL,
        @ParentOrgUnitCode = NULL,
        @ApplyPolicies = 0,
        @OrgUnitId = @RegionOrgUnitId OUTPUT;

    IF @SubRegionSharedGeoUnitId IS NOT NULL
    BEGIN
        EXEC App.AttachSharedGeoUnitToAccount
            @AccountCode = @AccountCode,
            @SharedGeoUnitId = @SubRegionSharedGeoUnitId,
            @ParentOrgUnitType = 'Region',
            @ParentOrgUnitCode = @RegionCode,
            @ApplyPolicies = 0,
            @OrgUnitId = @SubRegionOrgUnitId OUTPUT;
    END

    IF @ClusterSharedGeoUnitId IS NOT NULL
    BEGIN
        SET @ClusterParentType = CASE
                                     WHEN @SubRegionSharedGeoUnitId IS NOT NULL THEN 'SubRegion'
                                     ELSE 'Region'
                                 END;
        SET @ClusterParentCode = CASE
                                     WHEN @SubRegionSharedGeoUnitId IS NOT NULL THEN @SubRegionCode
                                     ELSE @RegionCode
                                 END;

        EXEC App.AttachSharedGeoUnitToAccount
            @AccountCode = @AccountCode,
            @SharedGeoUnitId = @ClusterSharedGeoUnitId,
            @ParentOrgUnitType = @ClusterParentType,
            @ParentOrgUnitCode = @ClusterParentCode,
            @ApplyPolicies = 0,
            @OrgUnitId = @ClusterOrgUnitId OUTPUT;
    END

    SET @CountryParentType = CASE
                                 WHEN @ClusterSharedGeoUnitId IS NOT NULL THEN 'Cluster'
                                 WHEN @SubRegionSharedGeoUnitId IS NOT NULL THEN 'SubRegion'
                                 ELSE 'Region'
                             END;
    SET @CountryParentCode = CASE
                                 WHEN @ClusterSharedGeoUnitId IS NOT NULL THEN @ClusterCode
                                 WHEN @SubRegionSharedGeoUnitId IS NOT NULL THEN @SubRegionCode
                                 ELSE @RegionCode
                             END;

    EXEC App.AttachSharedGeoUnitToAccount
        @AccountCode = @AccountCode,
        @SharedGeoUnitId = @CountrySharedGeoUnitId,
        @ParentOrgUnitType = @CountryParentType,
        @ParentOrgUnitCode = @CountryParentCode,
        @ApplyPolicies = 0,
        @OrgUnitId = @CountryOrgUnitId OUTPUT;

    DECLARE @ParentType NVARCHAR(20) = 'Country';
    DECLARE @ParentCode NVARCHAR(50) = @CountryCode;

    IF @AreaCode IS NOT NULL AND @AreaName IS NOT NULL
    BEGIN
        DECLARE @AreaOrgUnitId INT;
        EXEC App.InsertOrgUnit
            @AccountCode = @AccountCode,
            @OrgUnitType = 'Area',
            @OrgUnitCode = @AreaCode,
            @OrgUnitName = @AreaName,
            @ParentOrgUnitType = @ParentType,
            @ParentOrgUnitCode = @ParentCode,
            @CountrySharedGeoUnitId = @CountrySharedGeoUnitId,
            @ApplyPolicies = 0,
            @OrgUnitId = @AreaOrgUnitId OUTPUT;

        SET @ParentType = 'Area';
        SET @ParentCode = @AreaCode;
    END

    IF @BranchCode IS NOT NULL AND @BranchName IS NOT NULL
    BEGIN
        DECLARE @BranchOrgUnitId INT;
        EXEC App.InsertOrgUnit
            @AccountCode = @AccountCode,
            @OrgUnitType = 'Branch',
            @OrgUnitCode = @BranchCode,
            @OrgUnitName = @BranchName,
            @ParentOrgUnitType = @ParentType,
            @ParentOrgUnitCode = @ParentCode,
            @CountrySharedGeoUnitId = @CountrySharedGeoUnitId,
            @ApplyPolicies = 0,
            @OrgUnitId = @BranchOrgUnitId OUTPUT;

        SET @ParentType = 'Branch';
        SET @ParentCode = @BranchCode;
    END

    EXEC App.InsertOrgUnit
        @AccountCode = @AccountCode,
        @OrgUnitType = 'Site',
        @OrgUnitCode = @SiteCode,
        @OrgUnitName = @SiteName,
        @ParentOrgUnitType = @ParentType,
        @ParentOrgUnitCode = @ParentCode,
        @CountrySharedGeoUnitId = @CountrySharedGeoUnitId,
        @ApplyPolicies = 0,
        @OrgUnitId = @SiteOrgUnitId OUTPUT;

    IF @ApplyPolicies = 1
        EXEC App.ApplyAccountPolicies @AccountCode = @AccountCode, @ApplyAccess = 1, @ApplyPackages = 1;
END;
GO

-- Upserts a user principal and synchronizes Sec.Principal metadata -----------------
CREATE OR ALTER PROCEDURE App.UpsertUser
    @UPN            NVARCHAR(320),
    @DisplayName    NVARCHAR(200)   = NULL,
    @EntraObjectId  NVARCHAR(128)   = NULL,
    @UserType       NVARCHAR(20)    = 'External',
    @IsActive       BIT             = 1,
    @InvitedBy      NVARCHAR(128)   = NULL,
    @UserId         INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ExistingUserId INT = (
        SELECT UserId FROM Sec.[User] WHERE UPN = @UPN
    );

    IF @ExistingUserId IS NULL
    BEGIN
        INSERT INTO Sec.Principal (PrincipalType, PrincipalName)
        VALUES ('User', COALESCE(@DisplayName, @UPN));

        SET @ExistingUserId = SCOPE_IDENTITY();

        INSERT INTO Sec.[User]
            (UserId, UPN, DisplayName, EntraObjectId, UserType, IsActive, InvitedAt, InvitedBy)
        VALUES
            (@ExistingUserId, @UPN, @DisplayName, @EntraObjectId, @UserType, @IsActive,
             CASE WHEN @InvitedBy IS NOT NULL THEN SYSUTCDATETIME() ELSE NULL END,
             @InvitedBy);
    END
    ELSE
    BEGIN
        UPDATE Sec.Principal
        SET PrincipalName = COALESCE(@DisplayName, PrincipalName),
            ModifiedOnUtc = SYSUTCDATETIME(),
            ModifiedBy    = SESSION_USER
        WHERE PrincipalId = @ExistingUserId;

        UPDATE Sec.[User]
        SET DisplayName   = COALESCE(@DisplayName, DisplayName),
            EntraObjectId = COALESCE(@EntraObjectId, EntraObjectId),
            UserType      = @UserType,
            IsActive      = @IsActive,
            ModifiedOnUtc = SYSUTCDATETIME(),
            ModifiedBy    = SESSION_USER
        WHERE UserId = @ExistingUserId;
    END

    SET @UserId = @ExistingUserId;
END;
GO

CREATE OR ALTER PROCEDURE App.RecordUserLogin
    @EntraObjectId  NVARCHAR(128),
    @UPN            NVARCHAR(320)   = NULL,
    @DisplayName    NVARCHAR(200)   = NULL,
    @UserId         INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    -- Look up by EntraObjectId first, fall back to UPN
    SELECT @UserId = UserId
    FROM Sec.[User]
    WHERE EntraObjectId = @EntraObjectId;

    IF @UserId IS NULL AND @UPN IS NOT NULL
    BEGIN
        SELECT @UserId = UserId FROM Sec.[User] WHERE UPN = @UPN;

        -- Back-fill EntraObjectId if user was created before Entra integration
        IF @UserId IS NOT NULL
            UPDATE Sec.[User]
            SET EntraObjectId = @EntraObjectId,
                ModifiedOnUtc = SYSUTCDATETIME()
            WHERE UserId = @UserId;
    END

    -- Just-in-time provisioning: create user on first login if not found
    IF @UserId IS NULL AND @UPN IS NOT NULL
    BEGIN
        EXEC App.UpsertUser
            @UPN           = @UPN,
            @DisplayName   = @DisplayName,
            @EntraObjectId = @EntraObjectId,
            @UserType      = 'External',
            @IsActive      = 1,
            @UserId        = @UserId OUTPUT;
    END

    -- Update last login timestamp
    IF @UserId IS NOT NULL
        UPDATE Sec.[User]
        SET LastLoginAt   = SYSUTCDATETIME(),
            DisplayName   = COALESCE(@DisplayName, DisplayName),
            ModifiedOnUtc = SYSUTCDATETIME()
        WHERE UserId = @UserId;
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
        SELECT @ExistingRoleId = p.PrincipalId
        FROM Sec.Principal AS p
        LEFT JOIN Sec.Role AS r
            ON r.RoleId = p.PrincipalId
        WHERE p.PrincipalType = 'Role'
          AND p.PrincipalName = COALESCE(@RoleName, @RoleCode)
          AND (r.RoleId IS NULL OR r.RoleCode = @RoleCode);
    END

    IF @ExistingRoleId IS NULL
    BEGIN
        INSERT INTO Sec.Principal (PrincipalType, PrincipalName)
        VALUES ('Role', COALESCE(@RoleName, @RoleCode));

        SET @ExistingRoleId = SCOPE_IDENTITY();
    END

    IF EXISTS (SELECT 1 FROM Sec.Role WHERE RoleId = @ExistingRoleId)
    BEGIN
        UPDATE Sec.Principal
        SET PrincipalName = COALESCE(@RoleName, PrincipalName),
            IsActive = 1,
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
    ELSE
    BEGIN
        UPDATE Sec.Principal
        SET PrincipalName = COALESCE(@RoleName, PrincipalName),
            IsActive = 1,
            ModifiedOnUtc = SYSUTCDATETIME(),
            ModifiedBy = SESSION_USER
        WHERE PrincipalId = @ExistingRoleId;

        INSERT INTO Sec.Role (RoleId, RoleCode, RoleName, Description)
        VALUES (@ExistingRoleId, @RoleCode, @RoleName, @Description);
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
                ScopeType           NVARCHAR(15),
                OrgUnitType         NVARCHAR(20),
                OrgUnitCode         NVARCHAR(50),
                ExpandPerOrgUnit    BIT,
                RoleCodeTemplate    NVARCHAR(100),
                RoleNameTemplate    NVARCHAR(200)
            );

            INSERT INTO @Pol (AccountRolePolicyId, PolicyName, ScopeType, OrgUnitType, OrgUnitCode, ExpandPerOrgUnit, RoleCodeTemplate, RoleNameTemplate)
            SELECT
                arp.AccountRolePolicyId,
                arp.PolicyName,
                arp.ScopeType,
                arp.OrgUnitType,
                arp.OrgUnitCode,
                arp.ExpandPerOrgUnit,
                arp.RoleCodeTemplate,
                arp.RoleNameTemplate
            FROM Sec.AccountRolePolicy AS arp
            WHERE arp.IsActive = 1;

            DECLARE @ExpandedPol TABLE
            (
                AccountRolePolicyId INT,
                PolicyName          NVARCHAR(200),
                RoleCode            NVARCHAR(100),
                RoleName            NVARCHAR(200),
                ScopeType           NVARCHAR(15),
                OrgUnitId           INT NULL
            );

            INSERT INTO @ExpandedPol (AccountRolePolicyId, PolicyName, RoleCode, RoleName, ScopeType, OrgUnitId)
            SELECT
                p.AccountRolePolicyId,
                p.PolicyName,
                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                    p.RoleCodeTemplate,
                    '{AccountCode}', @AccountCode),
                    '{ACCOUNTCODE}', @AccountCode),
                    '{AccountName}', @AccountName),
                    '{ACCOUNTNAME}', @AccountName),
                    '{OrgUnitCode}', ''),
                    '{ORGUNITCODE}', ''),
                    '{OrgUnitName}', ''),
                    '{ORGUNITNAME}', ''),
                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                    p.RoleNameTemplate,
                    '{AccountCode}', @AccountCode),
                    '{ACCOUNTCODE}', @AccountCode),
                    '{AccountName}', @AccountName),
                    '{ACCOUNTNAME}', @AccountName),
                    '{OrgUnitCode}', ''),
                    '{ORGUNITCODE}', ''),
                    '{OrgUnitName}', ''),
                    '{ORGUNITNAME}', ''),
                p.ScopeType,
                NULL
            FROM @Pol AS p
            WHERE p.ScopeType = 'NONE';

            INSERT INTO @ExpandedPol (AccountRolePolicyId, PolicyName, RoleCode, RoleName, ScopeType, OrgUnitId)
            SELECT
                p.AccountRolePolicyId,
                p.PolicyName,
                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                    p.RoleCodeTemplate,
                    '{AccountCode}', @AccountCode),
                    '{ACCOUNTCODE}', @AccountCode),
                    '{AccountName}', @AccountName),
                    '{ACCOUNTNAME}', @AccountName),
                    '{OrgUnitCode}', ou.OrgUnitCode),
                    '{ORGUNITCODE}', ou.OrgUnitCode),
                    '{OrgUnitName}', ou.OrgUnitName),
                    '{ORGUNITNAME}', ou.OrgUnitName),
                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                    p.RoleNameTemplate,
                    '{AccountCode}', @AccountCode),
                    '{ACCOUNTCODE}', @AccountCode),
                    '{AccountName}', @AccountName),
                    '{ACCOUNTNAME}', @AccountName),
                    '{OrgUnitCode}', ou.OrgUnitCode),
                    '{ORGUNITCODE}', ou.OrgUnitCode),
                    '{OrgUnitName}', ou.OrgUnitName),
                    '{ORGUNITNAME}', ou.OrgUnitName),
                p.ScopeType,
                ou.OrgUnitId
            FROM @Pol AS p
            JOIN Dim.OrgUnit AS ou
              ON ou.AccountId = @AccountId
             AND ou.OrgUnitType = p.OrgUnitType
             AND (
                    (p.ExpandPerOrgUnit = 1 AND (p.OrgUnitCode IS NULL OR ou.OrgUnitCode = p.OrgUnitCode))
                    OR
                    (p.ExpandPerOrgUnit = 0 AND ou.OrgUnitCode = p.OrgUnitCode)
                )
            WHERE p.ScopeType = 'ORGUNIT';

            -- Upsert missing roles using App.UpsertRole
            DECLARE @RoleId INT, @RoleCode NVARCHAR(100), @RoleName NVARCHAR(200);

            DECLARE RoleCur CURSOR LOCAL FAST_FORWARD FOR
                SELECT p.RoleCode, p.RoleName
                FROM @ExpandedPol AS p
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
                p.OrgUnitId
            FROM @ExpandedPol AS p
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
                      ISNULL(p.OrgUnitId, -1)
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
    @PrincipalAccessGrantId INT,
    @RevokedByUPN           NVARCHAR(320) = NULL   -- caller's UPN; NULL = system
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM Sec.PrincipalAccessGrant
        WHERE PrincipalAccessGrantId = @PrincipalAccessGrantId
    )
        THROW 50061, 'Access grant not found.', 1;

    IF EXISTS (
        SELECT 1 FROM Sec.PrincipalAccessGrant
        WHERE PrincipalAccessGrantId = @PrincipalAccessGrantId
          AND RevokedAt IS NOT NULL
    )
        THROW 50063, 'Access grant has already been revoked.', 1;

    DECLARE @RevokedByPrincipalId INT = NULL;
    IF @RevokedByUPN IS NOT NULL
        SELECT @RevokedByPrincipalId = UserId FROM Sec.[User] WHERE UPN = @RevokedByUPN;

    UPDATE Sec.PrincipalAccessGrant
    SET RevokedAt            = SYSUTCDATETIME(),
        RevokedByPrincipalId = @RevokedByPrincipalId,
        ModifiedOnUtc        = SYSUTCDATETIME(),
        ModifiedBy           = COALESCE(@RevokedByUPN, SESSION_USER)
    WHERE PrincipalAccessGrantId = @PrincipalAccessGrantId;
END;
GO

-- --------------------------------------------------------------------------------
-- App.RevokePackageGrant
-- Remove a specific package grant from a principal
-- --------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE App.RevokePackageGrant
    @PrincipalPackageGrantId INT,
    @RevokedByUPN            NVARCHAR(320) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM Sec.PrincipalPackageGrant
        WHERE PrincipalPackageGrantId = @PrincipalPackageGrantId
    )
        THROW 50062, 'Package grant not found.', 1;

    IF EXISTS (
        SELECT 1 FROM Sec.PrincipalPackageGrant
        WHERE PrincipalPackageGrantId = @PrincipalPackageGrantId
          AND RevokedAt IS NOT NULL
    )
        THROW 50064, 'Package grant has already been revoked.', 1;

    DECLARE @RevokedByPrincipalId INT = NULL;
    IF @RevokedByUPN IS NOT NULL
        SELECT @RevokedByPrincipalId = UserId FROM Sec.[User] WHERE UPN = @RevokedByUPN;

    UPDATE Sec.PrincipalPackageGrant
    SET RevokedAt            = SYSUTCDATETIME(),
        RevokedByPrincipalId = @RevokedByPrincipalId,
        ModifiedOnUtc        = SYSUTCDATETIME(),
        ModifiedBy           = COALESCE(@RevokedByUPN, SESSION_USER)
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

-- Audit tables ---------------------------------------------------------------
IF OBJECT_ID('Audit.ApplicationLog', 'U') IS NULL
BEGIN
    CREATE TABLE Audit.ApplicationLog
    (
        LogId            BIGINT IDENTITY(1,1)   NOT NULL PRIMARY KEY,
        -- Who
        ActorUserId      INT            NULL,    -- Sec.User.UserId (NULL = system/anonymous)
        ActorUPN         NVARCHAR(320)  NULL,    -- denormalised for readability without joins
        -- What
        Action           NVARCHAR(100)  NOT NULL, -- e.g. 'GrantAccess', 'RevokeAccess', 'SubmitKPI'
        EntityType       NVARCHAR(100)  NOT NULL, -- e.g. 'AccessGrant', 'KpiSubmission'
        EntityId         NVARCHAR(100)  NULL,     -- PK of affected row (as string for flexibility)
        -- Detail
        OldValue         NVARCHAR(MAX)  NULL,     -- JSON before-image (nullable — not all actions have one)
        NewValue         NVARCHAR(MAX)  NULL,     -- JSON after-image
        Notes            NVARCHAR(500)  NULL,     -- freetext context
        -- Context
        IPAddress        NVARCHAR(45)   NULL,     -- IPv4 or IPv6
        UserAgent        NVARCHAR(500)  NULL,
        CorrelationId    UNIQUEIDENTIFIER NULL,   -- ties all log rows from one API request together
        -- When
        LoggedAt         DATETIME2      NOT NULL  CONSTRAINT DF_AuditLog_LoggedAt DEFAULT (SYSUTCDATETIME()),
        -- Retention
        RetainUntil      DATETIME2      NOT NULL  -- set by usp_WriteLog; cannot be past < LoggedAt
    );

    -- Primary access patterns
    CREATE INDEX IX_AuditLog_EntityType_EntityId ON Audit.ApplicationLog (EntityType, EntityId);
    CREATE INDEX IX_AuditLog_ActorUserId         ON Audit.ApplicationLog (ActorUserId) WHERE ActorUserId IS NOT NULL;
    CREATE INDEX IX_AuditLog_LoggedAt            ON Audit.ApplicationLog (LoggedAt);
    CREATE INDEX IX_AuditLog_CorrelationId       ON Audit.ApplicationLog (CorrelationId) WHERE CorrelationId IS NOT NULL;
    CREATE INDEX IX_AuditLog_RetainUntil         ON Audit.ApplicationLog (RetainUntil);  -- for purge

    PRINT '  + Audit.ApplicationLog created';
END;
GO

IF OBJECT_ID('Audit.RetentionPolicy', 'U') IS NULL
BEGIN
    CREATE TABLE Audit.RetentionPolicy
    (
        EntityType       NVARCHAR(100) NOT NULL PRIMARY KEY,
        RetentionDays    INT           NOT NULL CONSTRAINT CK_RetentionPolicy_Days CHECK (RetentionDays > 0),
        Notes            NVARCHAR(200) NULL,
        ModifiedOnUtc    DATETIME2     NOT NULL CONSTRAINT DF_RetentionPolicy_Modified DEFAULT (SYSUTCDATETIME())
    );

    -- Default retention: 7 years for all types
    INSERT INTO Audit.RetentionPolicy (EntityType, RetentionDays, Notes)
    VALUES
        ('DEFAULT',        2555, '7 years — applies when no specific policy exists'),
        ('AccessGrant',    2555, '7 years — regulatory requirement'),
        ('PackageGrant',   2555, '7 years — regulatory requirement'),
        ('Delegation',     2555, '7 years — regulatory requirement'),
        ('KpiSubmission',  2555, '7 years — financial data retention'),
        ('UserLogin',       365, '1 year — operational use only');

    PRINT '  + Audit.RetentionPolicy created and seeded';
END;
GO

CREATE OR ALTER TRIGGER Audit.trg_AuditLog_NoMutate
ON Audit.ApplicationLog
INSTEAD OF UPDATE, DELETE
AS
BEGIN
    THROW 50090, 'Audit.ApplicationLog is insert-only. Updates and deletes are not permitted.', 1;
END;
GO

CREATE OR ALTER PROCEDURE Audit.usp_WriteLog
    @ActorUserId    INT             = NULL,
    @ActorUPN       NVARCHAR(320)   = NULL,
    @Action         NVARCHAR(100),
    @EntityType     NVARCHAR(100),
    @EntityId       NVARCHAR(100)   = NULL,
    @OldValue       NVARCHAR(MAX)   = NULL,
    @NewValue       NVARCHAR(MAX)   = NULL,
    @Notes          NVARCHAR(500)   = NULL,
    @IPAddress      NVARCHAR(45)    = NULL,
    @UserAgent      NVARCHAR(500)   = NULL,
    @CorrelationId  UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Resolve retention window
    DECLARE @RetentionDays INT;

    SELECT @RetentionDays = RetentionDays
    FROM Audit.RetentionPolicy
    WHERE EntityType = @EntityType;

    IF @RetentionDays IS NULL
        SELECT @RetentionDays = RetentionDays
        FROM Audit.RetentionPolicy
        WHERE EntityType = 'DEFAULT';

    DECLARE @RetainUntil DATETIME2 = DATEADD(DAY, @RetentionDays, SYSUTCDATETIME());

    INSERT INTO Audit.ApplicationLog
        (ActorUserId, ActorUPN, Action, EntityType, EntityId,
         OldValue, NewValue, Notes, IPAddress, UserAgent, CorrelationId, RetainUntil)
    VALUES
        (@ActorUserId, @ActorUPN, @Action, @EntityType, @EntityId,
         @OldValue, @NewValue, @Notes, @IPAddress, @UserAgent, @CorrelationId, @RetainUntil);
END;
GO

CREATE OR ALTER PROCEDURE Audit.usp_PurgeExpiredLogs
    @DryRun    BIT = 1,      -- default: report only, do not delete
    @BatchSize INT = 10000   -- delete in batches to avoid log bloat
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Cutoff    DATETIME2 = SYSUTCDATETIME();
    DECLARE @Deleted   INT       = 0;
    DECLARE @Total     INT       = 0;

    SELECT @Total = COUNT(*)
    FROM Audit.ApplicationLog
    WHERE RetainUntil < @Cutoff;

    SELECT
        @Total          AS ExpiredRowCount,
        @Cutoff         AS PurgeCutoff,
        @DryRun         AS DryRun,
        @BatchSize      AS BatchSize;

    IF @DryRun = 0
    BEGIN
        -- Disable immutability trigger temporarily for purge only
        -- NOTE: purge requires elevated DB permission (db_owner or ALTER on trigger)
        EXEC ('DISABLE TRIGGER Audit.trg_AuditLog_NoMutate ON Audit.ApplicationLog;');

        WHILE @Total > 0
        BEGIN
            DELETE TOP (@BatchSize)
            FROM Audit.ApplicationLog
            WHERE RetainUntil < @Cutoff;

            SET @Deleted = @Deleted + @@ROWCOUNT;
            SET @Total   = @Total   - @@ROWCOUNT;

            IF @@ROWCOUNT = 0 BREAK;
        END

        EXEC ('ENABLE TRIGGER Audit.trg_AuditLog_NoMutate ON Audit.ApplicationLog;');

        SELECT @Deleted AS RowsPurged;
    END
END;
GO

CREATE OR ALTER VIEW App.vAuditLog
AS
    SELECT
        al.LogId,
        al.ActorUserId,
        al.ActorUPN,
        al.Action,
        al.EntityType,
        al.EntityId,
        al.Notes,
        al.IPAddress,
        al.CorrelationId,
        al.LoggedAt,
        al.RetainUntil,
        -- Expose old/new value as-is; parsing is the API consumer's responsibility
        al.OldValue,
        al.NewValue,
        -- Resolved actor display name (may be NULL for system actions)
        p.PrincipalName AS ActorDisplayName
    FROM Audit.ApplicationLog AS al
    LEFT JOIN Sec.[User]    AS u ON u.UserId       = al.ActorUserId
    LEFT JOIN Sec.Principal AS p ON p.PrincipalId  = u.UserId;
GO

-- KPI and Workflow tables ----------------------------------------------------
IF OBJECT_ID('KPI.Definition', 'U') IS NULL
BEGIN
    CREATE TABLE KPI.Definition
    (
        KPIID           INT IDENTITY(1,1)   NOT NULL PRIMARY KEY,
        -- External-safe identifier for API exposure (never expose raw INT PKs)
        ExternalId      UNIQUEIDENTIFIER    NOT NULL CONSTRAINT DF_KpiDef_ExternalId DEFAULT (NEWID()),
        -- Identity
        KPICode         NVARCHAR(50)        NOT NULL,
        KPIName         NVARCHAR(200)       NOT NULL,
        KPIDescription  NVARCHAR(1000)      NULL,
        -- Classification
        Category        NVARCHAR(100)       NULL,   -- e.g. Safety, Quality, Productivity, Finance
        Unit            NVARCHAR(50)        NULL,   -- e.g. %, count, hours, EUR
        -- Data shape
        DataType        NVARCHAR(20)        NOT NULL
            CONSTRAINT CK_KpiDef_DataType
                CHECK (DataType IN ('Numeric','Percentage','Boolean','Text','Currency','DropDown')),
        AllowMultiValue BIT                 NOT NULL CONSTRAINT DF_KpiDef_AllowMultiValue DEFAULT (0),
        -- How values are collected
        CollectionType  NVARCHAR(20)        NOT NULL
            CONSTRAINT CK_KpiDef_CollectionType
                CHECK (CollectionType IN ('Manual','Automated','BulkUpload')),
        -- For automated KPIs: reference to the source system metric identifier
        SourceSystemRef NVARCHAR(200)       NULL,
        -- Direction: is higher better or lower better? Used for RAG threshold logic.
        ThresholdDirection NVARCHAR(10)     NULL
            CONSTRAINT CK_KpiDef_ThresholdDir
                CHECK (ThresholdDirection IN ('Higher','Lower') OR ThresholdDirection IS NULL),
        -- Lifecycle
        IsActive        BIT                 NOT NULL CONSTRAINT DF_KpiDef_IsActive    DEFAULT (1),
        CreatedOnUtc    DATETIME2           NOT NULL CONSTRAINT DF_KpiDef_Created     DEFAULT (SYSUTCDATETIME()),
        ModifiedOnUtc   DATETIME2           NOT NULL CONSTRAINT DF_KpiDef_Modified    DEFAULT (SYSUTCDATETIME()),
        CreatedBy       NVARCHAR(128)       NOT NULL CONSTRAINT DF_KpiDef_CreatedBy   DEFAULT (SESSION_USER),
        ModifiedBy      NVARCHAR(128)       NOT NULL CONSTRAINT DF_KpiDef_ModifiedBy  DEFAULT (SESSION_USER)
    );

    CREATE UNIQUE INDEX UX_KpiDef_Code       ON KPI.Definition (KPICode);
    CREATE UNIQUE INDEX UX_KpiDef_ExternalId ON KPI.Definition (ExternalId);
    CREATE INDEX        IX_KpiDef_Category   ON KPI.Definition (Category)       WHERE Category IS NOT NULL;
    CREATE INDEX        IX_KpiDef_IsActive   ON KPI.Definition (IsActive);

    PRINT '  + KPI.Definition created';
END;
GO

IF OBJECT_ID('KPI.DropDownOption', 'U') IS NULL
BEGIN
    CREATE TABLE KPI.DropDownOption
    (
        DropDownOptionID INT IDENTITY(1,1)  NOT NULL PRIMARY KEY,
        KPIID            INT                NOT NULL,
        OptionValue      NVARCHAR(200)      NOT NULL,
        SortOrder        INT                NOT NULL CONSTRAINT DF_KpiDDOpt_Sort DEFAULT (0),
        IsActive         BIT                NOT NULL CONSTRAINT DF_KpiDDOpt_Active DEFAULT (1),
        CONSTRAINT FK_KpiDDOpt_Definition FOREIGN KEY (KPIID)
            REFERENCES KPI.Definition (KPIID) ON DELETE CASCADE,
        CONSTRAINT UQ_KpiDDOpt_Value UNIQUE (KPIID, OptionValue)
    );

    CREATE INDEX IX_KpiDDOpt_KPIID ON KPI.DropDownOption (KPIID) WHERE IsActive = 1;

    PRINT '  + KPI.DropDownOption created';
END;
GO

IF OBJECT_ID('KPI.Period', 'U') IS NULL
BEGIN
    CREATE TABLE KPI.Period
    (
        PeriodID            INT IDENTITY(1,1)   NOT NULL PRIMARY KEY,
        ExternalId          UNIQUEIDENTIFIER    NOT NULL CONSTRAINT DF_KpiPeriod_ExternalId DEFAULT (NEWID()),
        -- Which schedule this period belongs to (periods are per-schedule, not global)
        PeriodScheduleID    INT                 NOT NULL,
        -- Human-readable label, e.g. '2026-03'
        PeriodLabel         NVARCHAR(20)        NOT NULL,
        PeriodYear          SMALLINT            NOT NULL,
        PeriodMonth         TINYINT             NOT NULL
            CONSTRAINT CK_KpiPeriod_Month CHECK (PeriodMonth BETWEEN 1 AND 12),
        -- Submission window
        SubmissionOpenDate  DATE                NOT NULL,
        SubmissionCloseDate DATE                NOT NULL,
        -- Lifecycle: Draft → Open → Closed
        Status              NVARCHAR(20)        NOT NULL CONSTRAINT DF_KpiPeriod_Status DEFAULT ('Draft')
            CONSTRAINT CK_KpiPeriod_Status
                CHECK (Status IN ('Draft','Open','Closed')),
        -- When 1 (default), Power Automate daily job auto-opens and auto-closes
        -- based on SubmissionOpenDate / SubmissionCloseDate. Set to 0 to hold manually.
        AutoTransition      BIT                 NOT NULL CONSTRAINT DF_KpiPeriod_AutoTransition DEFAULT (1),
        -- Optional notes for operations team
        Notes               NVARCHAR(500)       NULL,
        -- Audit
        CreatedOnUtc        DATETIME2           NOT NULL CONSTRAINT DF_KpiPeriod_Created    DEFAULT (SYSUTCDATETIME()),
        ModifiedOnUtc       DATETIME2           NOT NULL CONSTRAINT DF_KpiPeriod_Modified   DEFAULT (SYSUTCDATETIME()),
        CreatedBy           NVARCHAR(128)       NOT NULL CONSTRAINT DF_KpiPeriod_CreatedBy  DEFAULT (SESSION_USER),
        ModifiedBy          NVARCHAR(128)       NOT NULL CONSTRAINT DF_KpiPeriod_ModifiedBy DEFAULT (SESSION_USER),
        -- Business rule: close date must be after open date
        CONSTRAINT CK_KpiPeriod_Dates CHECK (SubmissionCloseDate >= SubmissionOpenDate)
        -- FK to PeriodSchedule added after that table is created below
    );

    -- Unique per schedule (different schedules can have the same calendar month)
    CREATE UNIQUE INDEX UX_KpiPeriod_ScheduleYearMonth ON KPI.Period (PeriodScheduleID, PeriodYear, PeriodMonth);
    CREATE UNIQUE INDEX UX_KpiPeriod_ExternalId        ON KPI.Period (ExternalId);
    CREATE INDEX        IX_KpiPeriod_Status            ON KPI.Period (Status);
    CREATE INDEX        IX_KpiPeriod_Schedule          ON KPI.Period (PeriodScheduleID);

    PRINT '  + KPI.Period created';
END;
GO

IF OBJECT_ID('KPI.PeriodSchedule', 'U') IS NULL
BEGIN
    CREATE TABLE KPI.PeriodSchedule
    (
        PeriodScheduleID    INT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_KpiPeriodSchedule PRIMARY KEY,
        ExternalId          UNIQUEIDENTIFIER NOT NULL
            CONSTRAINT DF_KpiPeriodSchedule_ExternalId DEFAULT NEWSEQUENTIALID(),
        ScheduleName        NVARCHAR(200) NOT NULL,
        FrequencyType       NVARCHAR(20) NOT NULL
            CONSTRAINT CK_KpiPeriodSchedule_FrequencyType
                CHECK (FrequencyType IN ('Monthly','EveryNMonths','Quarterly','SemiAnnual','Annual')),
        FrequencyInterval   TINYINT NULL,
        StartDate           DATE NOT NULL,
        EndDate             DATE NULL,
        SubmissionOpenDay   TINYINT NOT NULL,
        SubmissionCloseDay  TINYINT NOT NULL,
        GenerateMonthsAhead TINYINT NOT NULL
            CONSTRAINT DF_KpiPeriodSchedule_GenerateMonthsAhead DEFAULT (6),
        Notes               NVARCHAR(500) NULL,
        IsActive            BIT NOT NULL
            CONSTRAINT DF_KpiPeriodSchedule_IsActive DEFAULT (1),
        CreatedOnUtc        DATETIME2(3) NOT NULL
            CONSTRAINT DF_KpiPeriodSchedule_CreatedOn DEFAULT SYSUTCDATETIME(),
        CreatedBy           NVARCHAR(128) NULL
            CONSTRAINT DF_KpiPeriodSchedule_CreatedBy DEFAULT SESSION_USER,
        ModifiedOnUtc       DATETIME2(3) NULL,
        ModifiedBy          NVARCHAR(128) NULL,

        CONSTRAINT CK_KpiPeriodSchedule_DateRange
            CHECK (EndDate IS NULL OR EndDate >= StartDate),
        CONSTRAINT CK_KpiPeriodSchedule_OpenDay
            CHECK (SubmissionOpenDay BETWEEN 1 AND 28),
        CONSTRAINT CK_KpiPeriodSchedule_CloseDay
            CHECK (SubmissionCloseDay BETWEEN 1 AND 31),
        CONSTRAINT CK_KpiPeriodSchedule_DayOrder
            CHECK (SubmissionCloseDay >= SubmissionOpenDay),
        CONSTRAINT CK_KpiPeriodSchedule_FrequencyInterval
            CHECK (
                (FrequencyType = 'EveryNMonths' AND FrequencyInterval BETWEEN 2 AND 12)
                OR (FrequencyType <> 'EveryNMonths' AND FrequencyInterval IS NULL)
            ),
        CONSTRAINT CK_KpiPeriodSchedule_Horizon
            CHECK (GenerateMonthsAhead BETWEEN 1 AND 24)
    );

    CREATE UNIQUE INDEX UX_KpiPeriodSchedule_ExternalId
        ON KPI.PeriodSchedule (ExternalId);
    CREATE UNIQUE INDEX UX_KpiPeriodSchedule_Name
        ON KPI.PeriodSchedule (ScheduleName);
    CREATE INDEX IX_KpiPeriodSchedule_IsActive
        ON KPI.PeriodSchedule (IsActive);

    PRINT '  + KPI.PeriodSchedule created';
END;
GO

-- KPI.Period references KPI.PeriodSchedule — add FK now that both tables exist
IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'FK_KpiPeriod_Schedule'
)
    ALTER TABLE KPI.Period
        ADD CONSTRAINT FK_KpiPeriod_Schedule
            FOREIGN KEY (PeriodScheduleID) REFERENCES KPI.PeriodSchedule (PeriodScheduleID);
GO

IF OBJECT_ID('KPI.Assignment', 'U') IS NULL
BEGIN
    CREATE TABLE KPI.Assignment
    (
        AssignmentID        INT IDENTITY(1,1)   NOT NULL PRIMARY KEY,
        ExternalId          UNIQUEIDENTIFIER    NOT NULL CONSTRAINT DF_KpiAsgn_ExternalId DEFAULT (NEWID()),
        -- What KPI
        KPIID               INT                 NOT NULL,
        -- Scope: account-wide (OrgUnitId IS NULL) or site-specific
        AccountId           INT                 NOT NULL,
        OrgUnitId           INT                 NULL,   -- NULL = account-wide
        -- When
        PeriodID            INT                 NOT NULL,
        -- Submission requirement
        IsRequired          BIT                 NOT NULL CONSTRAINT DF_KpiAsgn_IsRequired DEFAULT (1),
        -- Target
        TargetValue         DECIMAL(18,4)       NULL,
        -- RAG thresholds (inherited direction from KPI.Definition unless overridden)
        ThresholdGreen      DECIMAL(18,4)       NULL,
        ThresholdAmber      DECIMAL(18,4)       NULL,
        ThresholdRed        DECIMAL(18,4)       NULL,
        ThresholdDirection  NVARCHAR(10)        NULL    -- NULL = inherit from KPI.Definition
            CONSTRAINT CK_KpiAsgn_ThresholdDir
                CHECK (ThresholdDirection IN ('Higher','Lower') OR ThresholdDirection IS NULL),
        -- Notes visible to submitters
        SubmitterGuidance   NVARCHAR(1000)      NULL,
        -- Source template (NULL for manually created assignments).
        -- Used by views to inherit CustomKpiName / CustomKpiDescription.
        AssignmentTemplateID INT                NULL,
        -- Admin
        AssignedByPrincipalId INT               NULL,
        IsActive            BIT                 NOT NULL CONSTRAINT DF_KpiAsgn_IsActive   DEFAULT (1),
        CreatedOnUtc        DATETIME2           NOT NULL CONSTRAINT DF_KpiAsgn_Created    DEFAULT (SYSUTCDATETIME()),
        ModifiedOnUtc       DATETIME2           NOT NULL CONSTRAINT DF_KpiAsgn_Modified   DEFAULT (SYSUTCDATETIME()),
        CreatedBy           NVARCHAR(128)       NOT NULL CONSTRAINT DF_KpiAsgn_CreatedBy  DEFAULT (SESSION_USER),
        ModifiedBy          NVARCHAR(128)       NOT NULL CONSTRAINT DF_KpiAsgn_ModifiedBy DEFAULT (SESSION_USER),
        -- FKs
        CONSTRAINT FK_KpiAsgn_Definition FOREIGN KEY (KPIID)      REFERENCES KPI.Definition (KPIID),
        CONSTRAINT FK_KpiAsgn_Account    FOREIGN KEY (AccountId)   REFERENCES Dim.Account    (AccountId),
        CONSTRAINT FK_KpiAsgn_OrgUnit    FOREIGN KEY (OrgUnitId)   REFERENCES Dim.OrgUnit    (OrgUnitId),
        CONSTRAINT FK_KpiAsgn_Period     FOREIGN KEY (PeriodID)    REFERENCES KPI.Period      (PeriodID),
        CONSTRAINT FK_KpiAsgn_AssignedBy FOREIGN KEY (AssignedByPrincipalId)
                                                                   REFERENCES Sec.Principal   (PrincipalId),
        -- FK_KpiAsgn_Template added after KPI.AssignmentTemplate via ALTER TABLE below
        -- Business rule: OrgUnitId must belong to AccountId when provided
        -- (enforced procedurally in App.usp_AssignKpi; DB can't express cross-row easily)
    );

    CREATE UNIQUE INDEX UX_KpiAsgn_ExternalId      ON KPI.Assignment (ExternalId);
    CREATE UNIQUE INDEX UX_KpiAsgn_SiteLevel
        ON KPI.Assignment (KPIID, OrgUnitId, PeriodID)
        WHERE OrgUnitId IS NOT NULL;
    CREATE UNIQUE INDEX UX_KpiAsgn_AccountLevel
        ON KPI.Assignment (KPIID, AccountId, PeriodID)
        WHERE OrgUnitId IS NULL;
    CREATE INDEX        IX_KpiAsgn_AccountPeriod    ON KPI.Assignment (AccountId, PeriodID);
    CREATE INDEX        IX_KpiAsgn_KPIPeriod        ON KPI.Assignment (KPIID, PeriodID);
    CREATE INDEX        IX_KpiAsgn_OrgUnitPeriod    ON KPI.Assignment (OrgUnitId, PeriodID) WHERE OrgUnitId IS NOT NULL;
    CREATE INDEX        IX_KpiAsgn_IsActive         ON KPI.Assignment (IsActive);

    PRINT '  + KPI.Assignment created';
END;
GO

IF OBJECT_ID('KPI.AssignmentTemplate', 'U') IS NULL
BEGIN
    CREATE TABLE KPI.AssignmentTemplate
    (
        AssignmentTemplateID INT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_KpiAssignmentTemplate PRIMARY KEY,
        ExternalId           UNIQUEIDENTIFIER NOT NULL
            CONSTRAINT DF_KpiAssignmentTemplate_ExternalId DEFAULT NEWSEQUENTIALID(),
        KPIID                INT NOT NULL,
        PeriodScheduleID     INT NOT NULL,
        AccountId            INT NOT NULL,
        OrgUnitId            INT NULL,
        StartPeriodYear      SMALLINT NOT NULL,
        StartPeriodMonth     TINYINT NOT NULL,
        EndPeriodYear        SMALLINT NULL,
        EndPeriodMonth       TINYINT NULL,
        IsRequired           BIT NOT NULL
            CONSTRAINT DF_KpiAssignmentTemplate_IsRequired DEFAULT (1),
        TargetValue          DECIMAL(18,4) NULL,
        ThresholdGreen       DECIMAL(18,4) NULL,
        ThresholdAmber       DECIMAL(18,4) NULL,
        ThresholdRed         DECIMAL(18,4) NULL,
        ThresholdDirection   NVARCHAR(10) NULL,
        SubmitterGuidance    NVARCHAR(1000) NULL,
        -- Optional override of the library KPI name/description for this account.
        -- When set, the effective name/description shown to submitters and in reports
        -- is the custom value; otherwise the KPI.Definition defaults are used.
        CustomKpiName        NVARCHAR(200) NULL,
        CustomKpiDescription NVARCHAR(1000) NULL,
        IsActive             BIT NOT NULL
            CONSTRAINT DF_KpiAssignmentTemplate_IsActive DEFAULT (1),
        CreatedOnUtc         DATETIME2(3) NOT NULL
            CONSTRAINT DF_KpiAssignmentTemplate_CreatedOn DEFAULT SYSUTCDATETIME(),
        CreatedBy            NVARCHAR(128) NULL
            CONSTRAINT DF_KpiAssignmentTemplate_CreatedBy DEFAULT SESSION_USER,
        ModifiedOnUtc        DATETIME2(3) NULL,
        ModifiedBy           NVARCHAR(128) NULL,

        CONSTRAINT FK_KpiTemplate_Definition FOREIGN KEY (KPIID)    REFERENCES KPI.Definition (KPIID),
        CONSTRAINT FK_KpiTemplate_Schedule   FOREIGN KEY (PeriodScheduleID) REFERENCES KPI.PeriodSchedule (PeriodScheduleID),
        CONSTRAINT FK_KpiTemplate_Account    FOREIGN KEY (AccountId) REFERENCES Dim.Account    (AccountId),
        CONSTRAINT FK_KpiTemplate_OrgUnit    FOREIGN KEY (OrgUnitId) REFERENCES Dim.OrgUnit    (OrgUnitId),
        CONSTRAINT CK_KpiTemplate_StartMonth CHECK (StartPeriodMonth BETWEEN 1 AND 12),
        CONSTRAINT CK_KpiTemplate_EndMonth   CHECK (EndPeriodMonth IS NULL OR EndPeriodMonth BETWEEN 1 AND 12),
        CONSTRAINT CK_KpiTemplate_EndRange
            CHECK (
                EndPeriodYear IS NULL
                OR EndPeriodMonth IS NULL
                OR (EndPeriodYear * 100 + EndPeriodMonth) >= (StartPeriodYear * 100 + StartPeriodMonth)
            ),
        CONSTRAINT CK_KpiTemplate_EndPair
            CHECK (
                (EndPeriodYear IS NULL AND EndPeriodMonth IS NULL)
                OR (EndPeriodYear IS NOT NULL AND EndPeriodMonth IS NOT NULL)
            )
    );

    CREATE UNIQUE INDEX UX_KpiAssignmentTemplate_ExternalId
        ON KPI.AssignmentTemplate (ExternalId);
    CREATE UNIQUE INDEX UX_KpiAssignmentTemplate_Scope
        ON KPI.AssignmentTemplate (KPIID, PeriodScheduleID, AccountId, OrgUnitId);
    CREATE INDEX IX_KpiAssignmentTemplate_IsActive
        ON KPI.AssignmentTemplate (IsActive);
    CREATE INDEX IX_KpiAssignmentTemplate_Range
        ON KPI.AssignmentTemplate (StartPeriodYear, StartPeriodMonth, EndPeriodYear, EndPeriodMonth);

    PRINT '  + KPI.AssignmentTemplate created';
END;
GO

IF OBJECT_ID('KPI.AssignmentTemplateDropDownOption', 'U') IS NULL
BEGIN
    CREATE TABLE KPI.AssignmentTemplateDropDownOption
    (
        TemplateDropDownOptionID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        AssignmentTemplateID     INT               NOT NULL,
        OptionValue              NVARCHAR(200)     NOT NULL,
        SortOrder                INT               NOT NULL CONSTRAINT DF_KpiTplDDOpt_Sort DEFAULT (0),
        CONSTRAINT FK_KpiTplDDOpt_Template FOREIGN KEY (AssignmentTemplateID)
            REFERENCES KPI.AssignmentTemplate (AssignmentTemplateID) ON DELETE CASCADE,
        CONSTRAINT UQ_KpiTplDDOpt_Value UNIQUE (AssignmentTemplateID, OptionValue)
    );

    CREATE INDEX IX_KpiTplDDOpt_Template ON KPI.AssignmentTemplateDropDownOption (AssignmentTemplateID);

    PRINT '  + KPI.AssignmentTemplateDropDownOption created';
END;
GO

-- Deferred FK: KPI.Assignment → KPI.AssignmentTemplate (forward ref resolved here)
IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = 'FK_KpiAsgn_Template' AND parent_object_id = OBJECT_ID('KPI.Assignment')
)
    ALTER TABLE KPI.Assignment
        ADD CONSTRAINT FK_KpiAsgn_Template FOREIGN KEY (AssignmentTemplateID)
            REFERENCES KPI.AssignmentTemplate (AssignmentTemplateID);
GO

IF OBJECT_ID('KPI.EscalationContact', 'U') IS NULL
BEGIN
    CREATE TABLE KPI.EscalationContact
    (
        EscalationContactID INT IDENTITY(1,1)   NOT NULL PRIMARY KEY,
        -- Scope: which site and period this contact applies to
        OrgUnitId           INT                 NOT NULL,   -- must be a Site-type OrgUnit
        PeriodID            INT                 NOT NULL,
        -- Level in the reminder chain
        -- 1 = SiteResponsible  (first reminder)
        -- 2 = AccountResponsible (second reminder, if site contact unresponsive)
        -- 3 = AccountManager    (escalation, if account contact unresponsive)
        EscalationLevel     TINYINT             NOT NULL
            CONSTRAINT CK_Escalation_Level CHECK (EscalationLevel BETWEEN 1 AND 3),
        -- Who gets notified at this level
        PrincipalId         INT                 NOT NULL,
        -- How many days after the previous reminder fires before this level activates
        -- Level 1: days after SubmissionOpenDate
        -- Level 2: days after Level 1 reminder sent
        -- Level 3: days after Level 2 reminder sent
        ReminderDelayDays   TINYINT             NOT NULL CONSTRAINT DF_Escalation_Delay DEFAULT (2),
        IsActive            BIT                 NOT NULL CONSTRAINT DF_Escalation_IsActive DEFAULT (1),
        CreatedOnUtc        DATETIME2           NOT NULL CONSTRAINT DF_Escalation_Created  DEFAULT (SYSUTCDATETIME()),
        ModifiedOnUtc       DATETIME2           NOT NULL CONSTRAINT DF_Escalation_Modified DEFAULT (SYSUTCDATETIME()),
        -- FKs
        CONSTRAINT FK_Escalation_OrgUnit   FOREIGN KEY (OrgUnitId)   REFERENCES Dim.OrgUnit    (OrgUnitId),
        CONSTRAINT FK_Escalation_Period    FOREIGN KEY (PeriodID)     REFERENCES KPI.Period      (PeriodID),
        CONSTRAINT FK_Escalation_Principal FOREIGN KEY (PrincipalId)  REFERENCES Sec.Principal   (PrincipalId)
    );

    -- One active contact per level per site+period
    CREATE UNIQUE INDEX UX_Escalation_LevelPerSitePeriod
        ON KPI.EscalationContact (OrgUnitId, PeriodID, EscalationLevel)
        WHERE IsActive = 1;

    CREATE INDEX IX_Escalation_SitePeriod ON KPI.EscalationContact (OrgUnitId, PeriodID);
    CREATE INDEX IX_Escalation_Principal  ON KPI.EscalationContact (PrincipalId);

    PRINT '  + KPI.EscalationContact created';
END;
GO

IF OBJECT_ID('KPI.Submission', 'U') IS NULL
BEGIN
    CREATE TABLE KPI.Submission
    (
        SubmissionID            INT IDENTITY(1,1)   NOT NULL PRIMARY KEY,
        ExternalId              UNIQUEIDENTIFIER    NOT NULL
            CONSTRAINT DF_KpiSub_ExternalId DEFAULT (NEWID()),
        -- Which assignment this fulfils
        AssignmentID            INT                 NOT NULL,
        -- Who submitted
        SubmittedByPrincipalId  INT                 NULL,   -- NULL for automated
        SubmittedAt             DATETIME2           NOT NULL
            CONSTRAINT DF_KpiSub_SubmittedAt DEFAULT (SYSUTCDATETIME()),
        -- Value: numeric, text, or boolean depending on KPI.Definition.DataType
        SubmissionValue         DECIMAL(18,4)       NULL,
        SubmissionText          NVARCHAR(1000)      NULL,  -- also used for DropDown selections
        SubmissionBoolean       BIT                 NULL,  -- used when DataType = 'Boolean'
        SubmissionNotes         NVARCHAR(500)       NULL,
        -- Source
        SourceType              NVARCHAR(20)        NOT NULL
            CONSTRAINT CK_KpiSub_SourceType
                CHECK (SourceType IN ('Manual','Automated','BulkUpload')),
        -- Lock
        LockState               NVARCHAR(25)        NOT NULL
            CONSTRAINT DF_KpiSub_LockState  DEFAULT ('Unlocked')
            CONSTRAINT CK_KpiSub_LockState
                CHECK (LockState IN ('Unlocked','Locked','LockedByAuto','LockedByPeriodClose')),
        LockedAt                DATETIME2           NULL,
        LockedByPrincipalId     INT                 NULL,
        -- Validation flag (set by data quality checks)
        IsValid                 BIT                 NOT NULL
            CONSTRAINT DF_KpiSub_IsValid DEFAULT (1),
        ValidationNotes         NVARCHAR(500)       NULL,
        -- Optimistic concurrency token
        RowVersion              ROWVERSION          NOT NULL,
        -- Audit
        CreatedOnUtc            DATETIME2           NOT NULL
            CONSTRAINT DF_KpiSub_Created    DEFAULT (SYSUTCDATETIME()),
        ModifiedOnUtc           DATETIME2           NOT NULL
            CONSTRAINT DF_KpiSub_Modified   DEFAULT (SYSUTCDATETIME()),
        -- FKs
        CONSTRAINT FK_KpiSub_Assignment  FOREIGN KEY (AssignmentID)
            REFERENCES KPI.Assignment (AssignmentID),
        CONSTRAINT FK_KpiSub_Submitter   FOREIGN KEY (SubmittedByPrincipalId)
            REFERENCES Sec.Principal  (PrincipalId),
        CONSTRAINT FK_KpiSub_LockedBy    FOREIGN KEY (LockedByPrincipalId)
            REFERENCES Sec.Principal  (PrincipalId)
    );

    -- One submission per assignment
    CREATE UNIQUE INDEX UX_KpiSub_Assignment    ON KPI.Submission (AssignmentID);
    CREATE UNIQUE INDEX UX_KpiSub_ExternalId    ON KPI.Submission (ExternalId);
    CREATE INDEX        IX_KpiSub_LockState     ON KPI.Submission (LockState);
    CREATE INDEX        IX_KpiSub_SubmittedBy   ON KPI.Submission (SubmittedByPrincipalId)
        WHERE SubmittedByPrincipalId IS NOT NULL;

    PRINT '  + KPI.Submission created';
END;
GO

IF OBJECT_ID('KPI.SubmissionAudit', 'U') IS NULL
BEGIN
    CREATE TABLE KPI.SubmissionAudit
    (
        AuditID             BIGINT IDENTITY(1,1)    NOT NULL PRIMARY KEY,
        SubmissionID        INT                     NOT NULL,
        ChangedByPrincipalId INT                   NULL,
        ChangedAt           DATETIME2               NOT NULL
            CONSTRAINT DF_KpiSubAudit_ChangedAt DEFAULT (SYSUTCDATETIME()),
        Action              NVARCHAR(20)            NOT NULL   -- Insert, Update, Lock, Unlock
            CONSTRAINT CK_KpiSubAudit_Action
                CHECK (Action IN ('Insert','Update','Lock','PeriodClose')),
        OldValue            NVARCHAR(MAX)           NULL,      -- JSON of changed fields before
        NewValue            NVARCHAR(MAX)           NULL,      -- JSON of changed fields after
        ChangeReason        NVARCHAR(500)           NULL,
        -- FKs
        CONSTRAINT FK_KpiSubAudit_Submission FOREIGN KEY (SubmissionID)
            REFERENCES KPI.Submission (SubmissionID),
        CONSTRAINT FK_KpiSubAudit_ChangedBy  FOREIGN KEY (ChangedByPrincipalId)
            REFERENCES Sec.Principal  (PrincipalId)
    );

    CREATE INDEX IX_KpiSubAudit_Submission ON KPI.SubmissionAudit (SubmissionID);
    CREATE INDEX IX_KpiSubAudit_ChangedAt  ON KPI.SubmissionAudit (ChangedAt);

    PRINT '  + KPI.SubmissionAudit created';
END;
GO

IF OBJECT_ID('KPI.SubmissionToken', 'U') IS NULL
BEGIN
    CREATE TABLE KPI.SubmissionToken
    (
        TokenId         UNIQUEIDENTIFIER    NOT NULL
            CONSTRAINT PK_KpiSubToken  PRIMARY KEY
            CONSTRAINT DF_KpiSubToken_TokenId  DEFAULT NEWID(),
        SiteOrgUnitId   INT                 NOT NULL,
        AccountId       INT                 NOT NULL,  -- denormalised; always = OrgUnit.AccountId
        PeriodId        INT                 NOT NULL,
        ExpiresAtUtc    DATETIME2           NOT NULL,
        CreatedBy       NVARCHAR(128)       NOT NULL,
        CreatedAtUtc    DATETIME2           NOT NULL
            CONSTRAINT DF_KpiSubToken_CreatedAt  DEFAULT SYSUTCDATETIME(),
        RevokedAtUtc    DATETIME2           NULL,
        CONSTRAINT FK_KpiSubToken_Site   FOREIGN KEY (SiteOrgUnitId) REFERENCES Dim.OrgUnit  (OrgUnitId),
        CONSTRAINT FK_KpiSubToken_Acct   FOREIGN KEY (AccountId)     REFERENCES Dim.Account  (AccountId),
        CONSTRAINT FK_KpiSubToken_Period FOREIGN KEY (PeriodId)      REFERENCES KPI.Period   (PeriodID)
    );

    CREATE INDEX IX_KpiSubToken_SitePeriod ON KPI.SubmissionToken (SiteOrgUnitId, PeriodId);

    PRINT '  + KPI.SubmissionToken created';
END;
GO

IF OBJECT_ID('Workflow.ReminderState', 'U') IS NULL
BEGIN
    CREATE TABLE Workflow.ReminderState
    (
        ReminderStateID         INT IDENTITY(1,1)   NOT NULL PRIMARY KEY,
        OrgUnitId               INT                 NOT NULL,   -- Site
        PeriodID                INT                 NOT NULL,
        -- Current escalation level (matches KPI.EscalationContact.EscalationLevel)
        CurrentLevel            TINYINT             NOT NULL
            CONSTRAINT DF_Reminder_Level DEFAULT (1)
            CONSTRAINT CK_Reminder_Level CHECK (CurrentLevel BETWEEN 1 AND 3),
        LastReminderSentAt      DATETIME2           NULL,
        NextReminderDueAt       DATETIME2           NULL,
        -- Resolved when all required KPIs for this site+period are submitted
        IsResolved              BIT                 NOT NULL
            CONSTRAINT DF_Reminder_IsResolved DEFAULT (0),
        ResolvedAt              DATETIME2           NULL,
        CreatedOnUtc            DATETIME2           NOT NULL
            CONSTRAINT DF_Reminder_Created  DEFAULT (SYSUTCDATETIME()),
        ModifiedOnUtc           DATETIME2           NOT NULL
            CONSTRAINT DF_Reminder_Modified DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_Reminder_OrgUnit FOREIGN KEY (OrgUnitId) REFERENCES Dim.OrgUnit (OrgUnitId),
        CONSTRAINT FK_Reminder_Period  FOREIGN KEY (PeriodID)  REFERENCES KPI.Period  (PeriodID)
    );

    CREATE UNIQUE INDEX UX_Reminder_SitePeriod ON Workflow.ReminderState (OrgUnitId, PeriodID);
    CREATE INDEX IX_Reminder_Unresolved
        ON Workflow.ReminderState (NextReminderDueAt)
        WHERE IsResolved = 0;

    PRINT '  + Workflow.ReminderState created';
END;
GO

IF OBJECT_ID('Workflow.NotificationLog', 'U') IS NULL
BEGIN
    CREATE TABLE Workflow.NotificationLog
    (
        NotificationID      INT IDENTITY(1,1)   NOT NULL PRIMARY KEY,
        ReminderStateID     INT                 NOT NULL,
        SentToPrincipalId   INT                 NOT NULL,
        EscalationLevel     TINYINT             NOT NULL,
        NotificationType    NVARCHAR(20)        NOT NULL
            CONSTRAINT CK_Notif_Type CHECK (NotificationType IN ('Email','Teams','SMS')),
        SentAt              DATETIME2           NOT NULL
            CONSTRAINT DF_Notif_SentAt DEFAULT (SYSUTCDATETIME()),
        DeliveryStatus      NVARCHAR(20)        NULL,    -- Sent, Delivered, Failed, Bounced
        ExternalMessageId   NVARCHAR(200)       NULL,    -- ID from email/Teams provider
        CONSTRAINT FK_Notif_ReminderState FOREIGN KEY (ReminderStateID)
            REFERENCES Workflow.ReminderState (ReminderStateID),
        CONSTRAINT FK_Notif_Recipient     FOREIGN KEY (SentToPrincipalId)
            REFERENCES Sec.Principal (PrincipalId)
    );

    CREATE INDEX IX_Notif_ReminderState ON Workflow.NotificationLog (ReminderStateID);
    CREATE INDEX IX_Notif_SentAt        ON Workflow.NotificationLog (SentAt);

    PRINT '  + Workflow.NotificationLog created';
END;
GO

CREATE OR ALTER TRIGGER KPI.trg_Submission_LockEnforce
ON KPI.Submission
INSTEAD OF UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Block value changes on locked rows
    IF EXISTS (
        SELECT 1
        FROM inserted  AS i
        JOIN deleted   AS d ON i.SubmissionID = d.SubmissionID
        WHERE d.LockState <> 'Unlocked'
          AND (
                ISNULL(CAST(i.SubmissionValue   AS NVARCHAR(50)),  '') <>
                ISNULL(CAST(d.SubmissionValue   AS NVARCHAR(50)),  '')
             OR ISNULL(i.SubmissionText,  '') <> ISNULL(d.SubmissionText,  '')
             OR ISNULL(i.SubmissionNotes, '') <> ISNULL(d.SubmissionNotes, '')
             OR ISNULL(CAST(i.SubmissionBoolean AS NVARCHAR(5)), '') <>
                ISNULL(CAST(d.SubmissionBoolean AS NVARCHAR(5)), '')
             OR i.SourceType <> d.SourceType
          )
    )
    BEGIN
        THROW 50200, 'Cannot modify a locked submission. Value and source columns are immutable once locked.', 1;
    END

    -- Pass through all mutable columns (INSTEAD OF replaces the statement,
    -- so every column that can be written must be listed explicitly here)
    UPDATE s
    SET s.SubmittedByPrincipalId = i.SubmittedByPrincipalId,
        s.SubmittedAt            = i.SubmittedAt,
        s.SubmissionValue        = i.SubmissionValue,
        s.SubmissionText         = i.SubmissionText,
        s.SubmissionBoolean      = i.SubmissionBoolean,
        s.SubmissionNotes        = i.SubmissionNotes,
        s.SourceType             = i.SourceType,
        s.LockState              = i.LockState,
        s.LockedAt               = i.LockedAt,
        s.LockedByPrincipalId    = i.LockedByPrincipalId,
        s.IsValid                = i.IsValid,
        s.ValidationNotes        = i.ValidationNotes,
        s.ModifiedOnUtc          = SYSUTCDATETIME()
    FROM KPI.Submission AS s
    JOIN inserted AS i ON s.SubmissionID = i.SubmissionID;
END;
GO

-- KPI admin and submission views --------------------------------------------
CREATE OR ALTER VIEW App.vKpiDefinitions
AS
    -- Used by: KPI library screen (K-01), assign KPI modal
    SELECT
        d.KPIID,
        d.ExternalId,
        d.KPICode,
        d.KPIName,
        d.KPIDescription,
        d.Category,
        d.Unit,
        d.DataType,
        d.AllowMultiValue,
        d.CollectionType,
        d.ThresholdDirection,
        d.SourceSystemRef,
        d.IsActive,
        d.CreatedOnUtc,
        d.ModifiedOnUtc,
        -- How many accounts currently have this KPI assigned (active assignments only)
        ISNULL(assignments.AssignmentCount, 0) AS AssignmentCount,
        -- Drop-down options as a pipe-delimited list (NULL for non-DropDown types)
        CASE WHEN d.DataType = 'DropDown' THEN (
            SELECT STRING_AGG(opt.OptionValue, '||') WITHIN GROUP (ORDER BY opt.SortOrder)
            FROM KPI.DropDownOption AS opt
            WHERE opt.KPIID = d.KPIID AND opt.IsActive = 1
        ) ELSE NULL END AS DropDownOptionsRaw
    FROM KPI.Definition AS d
    OUTER APPLY
    (
        SELECT COUNT(*) AS AssignmentCount
        FROM KPI.Assignment AS a
        WHERE a.KPIID     = d.KPIID
          AND a.IsActive  = 1
    ) AS assignments;
GO

CREATE OR ALTER VIEW App.vKpiPeriodSchedules
AS
    -- Periods are now per-schedule, so the count is a simple filter on PeriodScheduleID.
    SELECT
        ps.PeriodScheduleID,
        ps.ExternalId,
        ps.ScheduleName,
        ps.FrequencyType,
        ps.FrequencyInterval,
        ps.StartDate,
        ps.EndDate,
        ps.SubmissionOpenDay,
        ps.SubmissionCloseDay,
        ps.GenerateMonthsAhead,
        ps.Notes,
        ps.IsActive,
        ISNULL(periods.GeneratedPeriodCount, 0) AS GeneratedPeriodCount,
        periods.FirstGeneratedPeriodLabel,
        periods.LastGeneratedPeriodLabel
    FROM KPI.PeriodSchedule AS ps
    OUTER APPLY
    (
        SELECT
            COUNT(*)           AS GeneratedPeriodCount,
            MIN(p.PeriodLabel) AS FirstGeneratedPeriodLabel,
            MAX(p.PeriodLabel) AS LastGeneratedPeriodLabel
        FROM KPI.Period AS p
        WHERE p.PeriodScheduleID = ps.PeriodScheduleID
    ) AS periods;
GO

CREATE OR ALTER VIEW App.vKpiPeriods
AS
    -- Used by: period management screen (K-02), submission monitoring
    SELECT
        p.PeriodID,
        p.ExternalId,
        p.PeriodScheduleID,
        ps.ScheduleName,
        ps.FrequencyType,
        p.PeriodLabel,
        p.PeriodYear,
        p.PeriodMonth,
        p.SubmissionOpenDate,
        p.SubmissionCloseDate,
        p.Status,
        p.AutoTransition,
        p.Notes,
        p.CreatedOnUtc,
        p.ModifiedOnUtc,
        -- Is the submission window currently open?
        CASE
            WHEN p.Status = 'Open'
             AND CAST(SYSUTCDATETIME() AS DATE) BETWEEN p.SubmissionOpenDate AND p.SubmissionCloseDate
            THEN 1 ELSE 0
        END AS IsCurrentlyOpen,
        -- Days remaining in submission window (NULL if not open)
        CASE
            WHEN p.Status = 'Open'
            THEN DATEDIFF(DAY, CAST(SYSUTCDATETIME() AS DATE), p.SubmissionCloseDate)
            ELSE NULL
        END AS DaysRemaining
    FROM KPI.Period AS p
    JOIN KPI.PeriodSchedule AS ps ON ps.PeriodScheduleID = p.PeriodScheduleID;
GO

CREATE OR ALTER VIEW App.vKpiAssignmentTemplates
AS
    SELECT
        t.AssignmentTemplateID,
        t.ExternalId,
        d.KPICode,
        d.KPIName,
        d.Category,
        sched.PeriodScheduleID,
        sched.ScheduleName,
        sched.FrequencyType,
        sched.FrequencyInterval,
        acct.AccountId,
        acct.AccountCode,
        acct.AccountName,
        t.OrgUnitId,
        ou.OrgUnitCode AS SiteCode,
        ou.OrgUnitName AS SiteName,
        CASE WHEN t.OrgUnitId IS NULL THEN 1 ELSE 0 END AS IsAccountWide,
        t.StartPeriodYear,
        t.StartPeriodMonth,
        t.EndPeriodYear,
        t.EndPeriodMonth,
        t.IsRequired,
        t.TargetValue,
        t.ThresholdGreen,
        t.ThresholdAmber,
        t.ThresholdRed,
        COALESCE(t.ThresholdDirection, d.ThresholdDirection) AS EffectiveThresholdDirection,
        t.SubmitterGuidance,
        t.CustomKpiName,
        t.CustomKpiDescription,
        COALESCE(t.CustomKpiName,        d.KPIName)        AS EffectiveKpiName,
        COALESCE(t.CustomKpiDescription, d.KPIDescription) AS EffectiveKpiDescription,
        t.IsActive,
        ISNULL(instances.GeneratedAssignmentCount, 0) AS GeneratedAssignmentCount
    FROM KPI.AssignmentTemplate AS t
    JOIN KPI.Definition         AS d    ON d.KPIID = t.KPIID
    LEFT JOIN KPI.PeriodSchedule AS sched ON sched.PeriodScheduleID = t.PeriodScheduleID
    JOIN Dim.Account            AS acct ON acct.AccountId = t.AccountId
    LEFT JOIN Dim.OrgUnit       AS ou   ON ou.OrgUnitId = t.OrgUnitId
    OUTER APPLY
    (
        SELECT COUNT(*) AS GeneratedAssignmentCount
        FROM KPI.Assignment AS a
        JOIN KPI.Period     AS p ON p.PeriodID = a.PeriodID
        WHERE a.KPIID = t.KPIID
          AND a.AccountId = t.AccountId
          AND (
                (t.OrgUnitId IS NULL AND a.OrgUnitId IS NULL)
                OR a.OrgUnitId = t.OrgUnitId
              )
          AND (p.PeriodYear * 100 + p.PeriodMonth) >= (
                COALESCE(t.StartPeriodYear, YEAR(sched.StartDate)) * 100
                + COALESCE(t.StartPeriodMonth, MONTH(sched.StartDate))
              )
          AND (
                COALESCE(t.EndPeriodYear, YEAR(sched.EndDate)) IS NULL
                OR (p.PeriodYear * 100 + p.PeriodMonth) <= (
                    COALESCE(t.EndPeriodYear, YEAR(sched.EndDate)) * 100
                    + COALESCE(t.EndPeriodMonth, MONTH(sched.EndDate))
                )
              )
          AND (
                DATEDIFF(
                    MONTH,
                    DATEFROMPARTS(YEAR(sched.StartDate), MONTH(sched.StartDate), 1),
                    DATEFROMPARTS(p.PeriodYear, p.PeriodMonth, 1)
                )
                %
                CASE
                    WHEN sched.FrequencyType = 'Monthly' THEN 1
                    WHEN sched.FrequencyType = 'EveryNMonths' THEN sched.FrequencyInterval
                    WHEN sched.FrequencyType = 'Quarterly' THEN 3
                    WHEN sched.FrequencyType = 'SemiAnnual' THEN 6
                    WHEN sched.FrequencyType = 'Annual' THEN 12
                    ELSE 1
                END
              ) = 0
    ) AS instances;
GO

CREATE OR ALTER VIEW App.vKpiAssignments
AS
    -- Used by: assignment management screen (K-03), assign KPI modal
    SELECT
        a.AssignmentID,
        a.ExternalId,
        a.KPIID,
        d.KPICode,
        d.KPIName,
        d.Category,
        d.DataType,
        d.CollectionType,
        a.AccountId,
        acct.AccountCode,
        acct.AccountName,
        a.OrgUnitId,
        ou.OrgUnitCode      AS SiteCode,
        ou.OrgUnitName      AS SiteName,
        ou.CountryCode,
        -- NULL OrgUnitId = account-wide assignment
        CASE WHEN a.OrgUnitId IS NULL THEN 1 ELSE 0 END AS IsAccountWide,
        a.PeriodID,
        p.PeriodScheduleID,
        p.PeriodLabel,
        p.PeriodYear,
        p.PeriodMonth,
        p.Status            AS PeriodStatus,
        a.IsRequired,
        a.TargetValue,
        a.ThresholdGreen,
        a.ThresholdAmber,
        a.ThresholdRed,
        -- Effective threshold direction: assignment override > definition default
        COALESCE(a.ThresholdDirection, d.ThresholdDirection) AS EffectiveThresholdDirection,
        a.SubmitterGuidance,
        -- Source template (NULL for manually created assignments)
        a.AssignmentTemplateID,
        -- Effective name / description: template override → library default
        COALESCE(tmpl.CustomKpiName,        d.KPIName)        AS EffectiveKpiName,
        COALESCE(tmpl.CustomKpiDescription, d.KPIDescription) AS EffectiveKpiDescription,
        a.IsActive,
        a.CreatedOnUtc,
        a.ModifiedOnUtc,
        -- Escalation contact count for this site+period
        ISNULL(esc.ContactCount, 0) AS EscalationContactCount
    FROM KPI.Assignment AS a
    JOIN KPI.Definition             AS d    ON d.KPIID       = a.KPIID
    JOIN Dim.Account                AS acct ON acct.AccountId = a.AccountId
    JOIN KPI.Period                 AS p    ON p.PeriodID    = a.PeriodID
    LEFT JOIN Dim.OrgUnit           AS ou   ON ou.OrgUnitId  = a.OrgUnitId
    LEFT JOIN KPI.AssignmentTemplate AS tmpl ON tmpl.AssignmentTemplateID = a.AssignmentTemplateID
    OUTER APPLY
    (
        SELECT COUNT(*) AS ContactCount
        FROM KPI.EscalationContact AS ec
        WHERE ec.OrgUnitId = a.OrgUnitId
          AND ec.PeriodID  = a.PeriodID
          AND ec.IsActive  = 1
    ) AS esc;
GO

CREATE OR ALTER VIEW App.vEffectiveKpiAssignments
AS
    -- Resolution view: for each (site, KPI, period), a site-specific assignment
    -- shadows any account-wide assignment for the same KPI + period.
    -- Account-wide assignments are expanded to each active site in the account,
    -- but suppressed wherever a site-specific override already exists.
    --
    -- Use this view for submission-facing queries.
    -- Use vKpiAssignments for the admin management screen (shows raw rows).

    -- Branch 1: site-specific assignments — always authoritative for their own site.
    SELECT
        a.AssignmentID,
        a.ExternalId,
        a.KPIID,
        d.KPICode,
        d.KPIName,
        d.Category,
        d.DataType,
        d.CollectionType,
        a.AccountId,
        acct.AccountCode,
        acct.AccountName,
        ou.OrgUnitId,
        ou.OrgUnitCode                                                    AS SiteCode,
        ou.OrgUnitName                                                    AS SiteName,
        ou.CountryCode,
        CAST(0 AS BIT)                                                    AS IsAccountWide,
        a.PeriodID,
        p.PeriodScheduleID,
        p.PeriodLabel,
        p.PeriodYear,
        p.PeriodMonth,
        p.Status                                                          AS PeriodStatus,
        a.IsRequired,
        a.TargetValue,
        a.ThresholdGreen,
        a.ThresholdAmber,
        a.ThresholdRed,
        COALESCE(a.ThresholdDirection, d.ThresholdDirection)              AS EffectiveThresholdDirection,
        a.SubmitterGuidance,
        a.AssignmentTemplateID,
        COALESCE(tmpl.CustomKpiName,        d.KPIName)                    AS EffectiveKpiName,
        COALESCE(tmpl.CustomKpiDescription, d.KPIDescription)             AS EffectiveKpiDescription,
        a.IsActive,
        a.CreatedOnUtc,
        a.ModifiedOnUtc
    FROM KPI.Assignment              AS a
    JOIN KPI.Definition              AS d    ON d.KPIID        = a.KPIID
    JOIN Dim.Account                 AS acct ON acct.AccountId = a.AccountId
    JOIN KPI.Period                  AS p    ON p.PeriodID     = a.PeriodID
    JOIN Dim.OrgUnit                 AS ou   ON ou.OrgUnitId   = a.OrgUnitId  -- INNER: site rows only
    LEFT JOIN KPI.AssignmentTemplate AS tmpl ON tmpl.AssignmentTemplateID = a.AssignmentTemplateID
    WHERE a.OrgUnitId IS NOT NULL

    UNION ALL

    -- Branch 2: account-wide assignments, expanded to each active site in the account.
    -- Suppressed for any site that already has an active site-specific assignment
    -- for the same KPIID + PeriodID (site-specific takes precedence).
    SELECT
        a.AssignmentID,
        a.ExternalId,
        a.KPIID,
        d.KPICode,
        d.KPIName,
        d.Category,
        d.DataType,
        d.CollectionType,
        a.AccountId,
        acct.AccountCode,
        acct.AccountName,
        site.OrgUnitId,
        site.OrgUnitCode                                                  AS SiteCode,
        site.OrgUnitName                                                  AS SiteName,
        site.CountryCode,
        CAST(1 AS BIT)                                                    AS IsAccountWide,
        a.PeriodID,
        p.PeriodScheduleID,
        p.PeriodLabel,
        p.PeriodYear,
        p.PeriodMonth,
        p.Status                                                          AS PeriodStatus,
        a.IsRequired,
        a.TargetValue,
        a.ThresholdGreen,
        a.ThresholdAmber,
        a.ThresholdRed,
        COALESCE(a.ThresholdDirection, d.ThresholdDirection)              AS EffectiveThresholdDirection,
        a.SubmitterGuidance,
        a.AssignmentTemplateID,
        COALESCE(tmpl.CustomKpiName,        d.KPIName)                    AS EffectiveKpiName,
        COALESCE(tmpl.CustomKpiDescription, d.KPIDescription)             AS EffectiveKpiDescription,
        a.IsActive,
        a.CreatedOnUtc,
        a.ModifiedOnUtc
    FROM KPI.Assignment              AS a
    JOIN KPI.Definition              AS d    ON d.KPIID        = a.KPIID
    JOIN Dim.Account                 AS acct ON acct.AccountId = a.AccountId
    JOIN KPI.Period                  AS p    ON p.PeriodID     = a.PeriodID
    JOIN Dim.OrgUnit                 AS site
        ON  site.AccountId   = a.AccountId
        AND site.OrgUnitType = 'Site'
        AND site.IsActive    = 1
    LEFT JOIN KPI.AssignmentTemplate AS tmpl ON tmpl.AssignmentTemplateID = a.AssignmentTemplateID
    WHERE a.OrgUnitId IS NULL
      AND NOT EXISTS (
            SELECT 1
            FROM   KPI.Assignment AS sa
            WHERE  sa.KPIID     = a.KPIID
              AND  sa.OrgUnitId = site.OrgUnitId
              AND  sa.PeriodID  = a.PeriodID
              AND  sa.IsActive  = 1
      );
GO

CREATE OR ALTER VIEW App.vSiteCompletionSummary
AS
    -- Expand both site-specific and account-wide assignments to individual site rows.
    -- Account-wide assignments share a single submission row; if submitted it counts
    -- as complete for every site in the account.
    -- Site-specific assignments shadow account-wide ones for the same KPI + period.
    WITH AllSiteAssignments AS
    (
        -- 1. Site-specific: one row per assignment, scoped to its own site
        SELECT
            a.AssignmentID,
            a.PeriodID,
            a.AccountId,
            a.OrgUnitId     AS SiteOrgUnitId
        FROM KPI.Assignment AS a
        JOIN Dim.OrgUnit    AS ou
            ON  ou.OrgUnitId   = a.OrgUnitId
            AND ou.OrgUnitType = 'Site'
        WHERE a.IsActive    = 1
          AND a.OrgUnitId   IS NOT NULL

        UNION ALL

        -- 2. Account-wide: expand to every active Site under the same account.
        -- Suppressed where a site-specific assignment exists for the same KPI + period.
        SELECT
            a.AssignmentID,
            a.PeriodID,
            a.AccountId,
            site.OrgUnitId  AS SiteOrgUnitId
        FROM KPI.Assignment AS a
        JOIN Dim.OrgUnit    AS site
            ON  site.AccountId   = a.AccountId
            AND site.OrgUnitType = 'Site'
            AND site.IsActive    = 1
        WHERE a.IsActive    = 1
          AND a.OrgUnitId   IS NULL       -- account-wide flag
          AND NOT EXISTS (
                SELECT 1 FROM KPI.Assignment AS sa
                WHERE  sa.KPIID     = a.KPIID
                  AND  sa.OrgUnitId = site.OrgUnitId
                  AND  sa.PeriodID  = a.PeriodID
                  AND  sa.IsActive  = 1
          )
    )
    SELECT
        acct.AccountId,
        acct.AccountCode,
        acct.AccountName,
        site.OrgUnitId          AS SiteOrgUnitId,
        site.OrgUnitCode        AS SiteCode,
        site.OrgUnitName        AS SiteName,
        site.CountryCode,
        p.PeriodID,
        p.PeriodLabel,
        p.Status                AS PeriodStatus,
        -- Total required assignments for this site+period (site-specific + account-wide)
        COUNT(sa.AssignmentID)                                   AS TotalRequired,
        -- Submitted (account-wide submission counts for all sites in the account)
        SUM(CASE WHEN sub.SubmissionID IS NOT NULL
                  AND sub.LockState <> 'LockedByPeriodClose'
                 THEN 1 ELSE 0 END)                             AS TotalSubmitted,
        -- Locked (confirmed)
        SUM(CASE WHEN sub.LockState IN ('Locked','LockedByAuto','LockedByPeriodClose')
                 THEN 1 ELSE 0 END)                             AS TotalLocked,
        -- Missing (assigned but no submission yet)
        SUM(CASE WHEN sub.SubmissionID IS NULL THEN 1 ELSE 0 END) AS TotalMissing,
        -- Completion percentage
        CASE
            WHEN COUNT(sa.AssignmentID) = 0 THEN NULL
            ELSE CAST(
                    SUM(CASE WHEN sub.SubmissionID IS NOT NULL
                              AND sub.LockState <> 'LockedByPeriodClose'
                             THEN 1 ELSE 0 END) * 100.0
                    / COUNT(sa.AssignmentID)
                 AS DECIMAL(5,1))
        END                                                     AS CompletionPct,
        -- Exception flags for the Account Director view
        -- IsLateRisk: period is still Open, ≤3 days remain, and more than half the work is missing
        CAST(CASE
            WHEN p.Status = 'Open'
             AND DATEDIFF(DAY, CAST(SYSUTCDATETIME() AS DATE), p.SubmissionCloseDate) <= 3
             AND SUM(CASE WHEN sub.SubmissionID IS NULL THEN 1 ELSE 0 END) * 100.0
                 / NULLIF(COUNT(sa.AssignmentID), 0) > 50
            THEN 1 ELSE 0
        END AS BIT)                                             AS IsLateRisk,
        -- IsOverdue: period has Closed with submissions still missing
        CAST(CASE
            WHEN p.Status = 'Closed'
             AND SUM(CASE WHEN sub.SubmissionID IS NULL THEN 1 ELSE 0 END) > 0
            THEN 1 ELSE 0
        END AS BIT)                                             AS IsOverdue,
        -- Schedule context
        p.PeriodScheduleID,
        sched.ScheduleName,
        -- Reminder state (keyed to site+period)
        rs.CurrentLevel         AS ReminderLevel,
        rs.LastReminderSentAt,
        rs.NextReminderDueAt,
        rs.IsResolved           AS ReminderResolved
    FROM AllSiteAssignments      AS sa
    JOIN KPI.Period              AS p     ON p.PeriodID    = sa.PeriodID
    JOIN KPI.PeriodSchedule     AS sched ON sched.PeriodScheduleID = p.PeriodScheduleID
    JOIN Dim.OrgUnit             AS site  ON site.OrgUnitId = sa.SiteOrgUnitId
    JOIN Dim.Account             AS acct  ON acct.AccountId = sa.AccountId
    LEFT JOIN KPI.Submission     AS sub   ON sub.AssignmentID = sa.AssignmentID
    LEFT JOIN Workflow.ReminderState AS rs
        ON rs.OrgUnitId = sa.SiteOrgUnitId
       AND rs.PeriodID  = sa.PeriodID
    GROUP BY
        acct.AccountId, acct.AccountCode, acct.AccountName,
        site.OrgUnitId, site.OrgUnitCode, site.OrgUnitName, site.CountryCode,
        p.PeriodID, p.PeriodLabel, p.Status, p.SubmissionCloseDate, p.PeriodScheduleID,
        sched.ScheduleName,
        rs.CurrentLevel, rs.LastReminderSentAt, rs.NextReminderDueAt, rs.IsResolved;
GO

CREATE OR ALTER VIEW App.vKpiSubmissions
AS
    SELECT
        sub.SubmissionID,
        sub.ExternalId,
        sub.AssignmentID,
        -- KPI info
        d.KPICode,
        d.KPIName,
        d.Category,
        d.DataType,
        d.Unit,
        -- Period info
        p.PeriodLabel,
        p.PeriodYear,
        p.PeriodMonth,
        p.Status            AS PeriodStatus,
        -- Site info
        site.OrgUnitId      AS SiteOrgUnitId,
        site.OrgUnitCode    AS SiteCode,
        site.OrgUnitName    AS SiteName,
        site.CountryCode,
        acct.AccountCode,
        acct.AccountName,
        -- Thresholds (effective: assignment override > definition default)
        a.TargetValue,
        a.ThresholdGreen,
        a.ThresholdAmber,
        a.ThresholdRed,
        COALESCE(a.ThresholdDirection, d.ThresholdDirection) AS EffectiveThresholdDirection,
        -- Submission values
        sub.SubmissionValue,
        sub.SubmissionText,
        sub.SubmissionBoolean,
        sub.SubmissionNotes,
        sub.SourceType,
        -- Submitter
        submitter.UPN       AS SubmittedByUPN,
        sub.SubmittedAt,
        -- Lock
        sub.LockState,
        sub.LockedAt,
        locker.UPN          AS LockedByUPN,
        -- Validation
        sub.IsValid,
        sub.ValidationNotes,
        -- RAG status (computed; NULL if no thresholds set or non-numeric)
        CASE
            WHEN d.DataType NOT IN ('Numeric','Percentage','Currency') THEN NULL
            WHEN sub.SubmissionValue IS NULL                           THEN NULL
            WHEN a.ThresholdGreen IS NULL                              THEN NULL
            WHEN COALESCE(a.ThresholdDirection, d.ThresholdDirection) = 'Higher'
            THEN
                CASE
                    WHEN sub.SubmissionValue >= a.ThresholdGreen THEN 'Green'
                    WHEN sub.SubmissionValue >= a.ThresholdAmber THEN 'Amber'
                    ELSE 'Red'
                END
            WHEN COALESCE(a.ThresholdDirection, d.ThresholdDirection) = 'Lower'
            THEN
                CASE
                    WHEN sub.SubmissionValue <= a.ThresholdGreen THEN 'Green'
                    WHEN sub.SubmissionValue <= a.ThresholdAmber THEN 'Amber'
                    ELSE 'Red'
                END
            ELSE NULL
        END                 AS RAGStatus,
        sub.CreatedOnUtc,
        sub.ModifiedOnUtc
    FROM KPI.Submission AS sub
    JOIN KPI.Assignment AS a    ON a.AssignmentID   = sub.AssignmentID
    JOIN KPI.Definition AS d    ON d.KPIID          = a.KPIID
    JOIN KPI.Period     AS p    ON p.PeriodID        = a.PeriodID
    JOIN Dim.OrgUnit    AS site ON site.OrgUnitId    = a.OrgUnitId
    JOIN Dim.Account    AS acct ON acct.AccountId    = a.AccountId
    LEFT JOIN Sec.[User] AS submitter ON submitter.UserId = sub.SubmittedByPrincipalId
    LEFT JOIN Sec.[User] AS locker    ON locker.UserId    = sub.LockedByPrincipalId;
GO

-- KPI admin and submission procedures ---------------------------------------
CREATE OR ALTER PROCEDURE App.usp_UpsertKpiDefinition
    @KPICode                NVARCHAR(50),
    @KPIName                NVARCHAR(200),
    @KPIDescription         NVARCHAR(1000)  = NULL,
    @Category               NVARCHAR(100)   = NULL,
    @Unit                   NVARCHAR(50)    = NULL,
    @DataType               NVARCHAR(20)    = 'Numeric',
    @AllowMultiValue        BIT             = 0,
    @CollectionType         NVARCHAR(20)    = 'Manual',
    @ThresholdDirection     NVARCHAR(10)    = NULL,
    @SourceSystemRef        NVARCHAR(200)   = NULL,
    @IsActive               BIT             = 1,
    -- Drop-down options: pipe-delimited string, e.g. 'Option A||Option B||Option C'
    -- Pass NULL to leave existing options unchanged; pass empty string '' to clear all options
    @DropDownOptionsPipe    NVARCHAR(MAX)   = NULL,
    @ActorUPN               NVARCHAR(320)   = NULL,
    @KPIID                  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @KPIID = (SELECT KPIID FROM KPI.Definition WHERE KPICode = @KPICode);

    IF @KPIID IS NULL
    BEGIN
        INSERT INTO KPI.Definition
            (KPICode, KPIName, KPIDescription, Category, Unit,
             DataType, AllowMultiValue, CollectionType, ThresholdDirection, SourceSystemRef, IsActive)
        VALUES
            (@KPICode, @KPIName, @KPIDescription, @Category, @Unit,
             @DataType, @AllowMultiValue, @CollectionType, @ThresholdDirection, @SourceSystemRef, @IsActive);

        SET @KPIID = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE KPI.Definition
        SET KPIName            = @KPIName,
            KPIDescription     = @KPIDescription,
            Category           = @Category,
            Unit               = @Unit,
            DataType           = @DataType,
            AllowMultiValue    = @AllowMultiValue,
            CollectionType     = @CollectionType,
            ThresholdDirection = @ThresholdDirection,
            SourceSystemRef    = @SourceSystemRef,
            IsActive           = @IsActive,
            ModifiedOnUtc      = SYSUTCDATETIME(),
            ModifiedBy         = COALESCE(@ActorUPN, SESSION_USER)
        WHERE KPIID = @KPIID;
    END

    -- Sync drop-down options when provided (NULL = don't touch, '' = clear all)
    IF @DropDownOptionsPipe IS NOT NULL
    BEGIN
        -- Remove all existing options and replace with the provided set
        DELETE FROM KPI.DropDownOption WHERE KPIID = @KPIID;

        IF LEN(@DropDownOptionsPipe) > 0
        BEGIN
            INSERT INTO KPI.DropDownOption (KPIID, OptionValue, SortOrder)
            SELECT
                @KPIID,
                LTRIM(RTRIM(value)),
                ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1   -- 0-based sort order
            FROM STRING_SPLIT(@DropDownOptionsPipe, '|')
            WHERE LEN(LTRIM(RTRIM(value))) > 0
              -- De-duplicate: skip values already inserted (STRING_SPLIT may include empty tokens from '||')
              AND LTRIM(RTRIM(value)) NOT IN (
                  SELECT OptionValue FROM KPI.DropDownOption WHERE KPIID = @KPIID
              );
        END
    END
END;
GO

CREATE OR ALTER PROCEDURE App.usp_UpsertKpiPeriod
    @PeriodScheduleID    INT,
    @PeriodYear          SMALLINT,
    @PeriodMonth         TINYINT,
    @SubmissionOpenDate  DATE,
    @SubmissionCloseDate DATE,
    @AutoTransition      BIT            = 1,
    @Notes               NVARCHAR(500)  = NULL,
    @ActorUPN            NVARCHAR(320)  = NULL,
    @PeriodID            INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM KPI.PeriodSchedule WHERE PeriodScheduleID = @PeriodScheduleID)
        THROW 50099, 'PeriodScheduleID not found.', 1;

    IF @SubmissionCloseDate < @SubmissionOpenDate
        THROW 50100, 'SubmissionCloseDate must be on or after SubmissionOpenDate.', 1;

    DECLARE @Label NVARCHAR(20) =
        CONCAT(CAST(@PeriodYear AS NVARCHAR(4)), '-',
               RIGHT('0' + CAST(@PeriodMonth AS NVARCHAR(2)), 2));

    SET @PeriodID = (
        SELECT PeriodID FROM KPI.Period
        WHERE PeriodScheduleID = @PeriodScheduleID
          AND PeriodYear  = @PeriodYear
          AND PeriodMonth = @PeriodMonth
    );

    IF @PeriodID IS NULL
    BEGIN
        INSERT INTO KPI.Period
            (PeriodScheduleID, PeriodLabel, PeriodYear, PeriodMonth,
             SubmissionOpenDate, SubmissionCloseDate, AutoTransition, Notes)
        VALUES
            (@PeriodScheduleID, @Label, @PeriodYear, @PeriodMonth,
             @SubmissionOpenDate, @SubmissionCloseDate, @AutoTransition, @Notes);

        SET @PeriodID = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        -- Cannot modify a Closed period
        IF EXISTS (SELECT 1 FROM KPI.Period WHERE PeriodID = @PeriodID AND Status = 'Closed')
            THROW 50101, 'Cannot modify a Closed period.', 1;

        UPDATE KPI.Period
        SET PeriodLabel         = @Label,
            SubmissionOpenDate  = @SubmissionOpenDate,
            SubmissionCloseDate = @SubmissionCloseDate,
            AutoTransition      = @AutoTransition,
            Notes               = @Notes,
            ModifiedOnUtc       = SYSUTCDATETIME(),
            ModifiedBy          = COALESCE(@ActorUPN, SESSION_USER)
        WHERE PeriodID = @PeriodID;
    END
END;
GO

CREATE OR ALTER PROCEDURE App.usp_OpenPeriod
    @PeriodID   INT,
    @ActorUPN   NVARCHAR(320) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM KPI.Period WHERE PeriodID = @PeriodID)
        THROW 50102, 'Period not found.', 1;

    DECLARE @CurrentStatus NVARCHAR(20) = (
        SELECT Status FROM KPI.Period WHERE PeriodID = @PeriodID
    );

    IF @CurrentStatus = 'Open'
    BEGIN
        PRINT 'Period is already Open — no action taken.';
        RETURN;
    END

    IF @CurrentStatus NOT IN ('Draft')
        THROW 50103, 'Only Draft periods can be opened.', 1;

    UPDATE KPI.Period
    SET Status        = 'Open',
        ModifiedOnUtc = SYSUTCDATETIME(),
        ModifiedBy    = COALESCE(@ActorUPN, SESSION_USER)
    WHERE PeriodID = @PeriodID;

    -- Look up the schedule so we can scope downstream calls
    DECLARE @ScheduleID INT = (
        SELECT PeriodScheduleID FROM KPI.Period WHERE PeriodID = @PeriodID
    );

    -- Materialise any templates that belong to this schedule
    EXEC App.usp_MaterializeKpiAssignmentTemplates
        @PeriodScheduleIDFilter = @ScheduleID,
        @ActorUPN               = @ActorUPN;

    -- Initialise reminder state rows for sites with required assignments.
    -- Capture result set so it doesn't surface to the outer caller.
    DECLARE @ReminderResult TABLE (ReminderStateRowsCreated INT);
    INSERT INTO @ReminderResult
    EXEC App.usp_InitialiseReminderState
        @PeriodID = @PeriodID,
        @ActorUPN = @ActorUPN;

    PRINT 'Period opened.';
END;
GO

CREATE OR ALTER PROCEDURE App.usp_AssignKpi
    @KPICode              NVARCHAR(50),
    @AccountCode          NVARCHAR(50),
    @OrgUnitCode          NVARCHAR(50)    = NULL,   -- NULL = account-wide
    @OrgUnitType          NVARCHAR(20)    = 'Site',
    @PeriodScheduleID     INT,
    @PeriodYear           SMALLINT,
    @PeriodMonth          TINYINT,
    @AssignmentTemplateID INT             = NULL,
    @IsRequired           BIT             = 1,
    @TargetValue          DECIMAL(18,4)   = NULL,
    @ThresholdGreen       DECIMAL(18,4)   = NULL,
    @ThresholdAmber       DECIMAL(18,4)   = NULL,
    @ThresholdRed         DECIMAL(18,4)   = NULL,
    @ThresholdDirection   NVARCHAR(10)    = NULL,
    @SubmitterGuidance    NVARCHAR(1000)  = NULL,
    @ActorUPN             NVARCHAR(320)   = NULL,
    @AssignmentID         INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    -- Resolve KPI
    DECLARE @KPIID INT = (SELECT KPIID FROM KPI.Definition WHERE KPICode = @KPICode AND IsActive = 1);
    IF @KPIID IS NULL
        THROW 50110, 'KPI not found or inactive for provided KPICode.', 1;

    -- Resolve Account
    DECLARE @AccountId INT = (SELECT AccountId FROM Dim.Account WHERE AccountCode = @AccountCode AND IsActive = 1);
    IF @AccountId IS NULL
        THROW 50111, 'Account not found or inactive.', 1;

    -- Resolve OrgUnit (site) if provided
    DECLARE @OrgUnitId INT = NULL;
    IF @OrgUnitCode IS NOT NULL
    BEGIN
        SELECT @OrgUnitId = OrgUnitId
        FROM Dim.OrgUnit
        WHERE AccountId    = @AccountId
          AND OrgUnitCode  = @OrgUnitCode
          AND OrgUnitType  = @OrgUnitType
          AND IsActive     = 1;

        IF @OrgUnitId IS NULL
            THROW 50112, 'OrgUnit not found or inactive for provided AccountCode + OrgUnitCode.', 1;
    END

    -- Resolve Period (scoped to schedule)
    DECLARE @PeriodID INT = (
        SELECT PeriodID FROM KPI.Period
        WHERE PeriodScheduleID = @PeriodScheduleID
          AND PeriodYear       = @PeriodYear
          AND PeriodMonth      = @PeriodMonth
    );
    IF @PeriodID IS NULL
        THROW 50113, 'Period not found for this schedule/year/month. Create the period first using App.usp_UpsertKpiPeriod.', 1;

    -- Resolve actor
    DECLARE @ActorPrincipalId INT = NULL;
    IF @ActorUPN IS NOT NULL
        SELECT @ActorPrincipalId = UserId FROM Sec.[User] WHERE UPN = @ActorUPN;

    -- Enforce account-level uniqueness (UNIQUE constraint only covers site-level)
    IF @OrgUnitId IS NULL
    BEGIN
        SET @AssignmentID = (
            SELECT AssignmentID FROM KPI.Assignment
            WHERE KPIID = @KPIID AND AccountId = @AccountId AND OrgUnitId IS NULL AND PeriodID = @PeriodID
        );
    END
    ELSE
    BEGIN
        -- Site-level: covered by UQ_KpiAsgn_SiteLevel constraint
        SET @AssignmentID = (
            SELECT AssignmentID FROM KPI.Assignment
            WHERE KPIID = @KPIID AND OrgUnitId = @OrgUnitId AND PeriodID = @PeriodID
        );
    END

    IF @AssignmentID IS NULL
    BEGIN
        INSERT INTO KPI.Assignment
            (KPIID, AccountId, OrgUnitId, PeriodID, AssignmentTemplateID, IsRequired,
             TargetValue, ThresholdGreen, ThresholdAmber, ThresholdRed,
             ThresholdDirection, SubmitterGuidance, AssignedByPrincipalId)
        VALUES
            (@KPIID, @AccountId, @OrgUnitId, @PeriodID, @AssignmentTemplateID, @IsRequired,
             @TargetValue, @ThresholdGreen, @ThresholdAmber, @ThresholdRed,
             @ThresholdDirection, @SubmitterGuidance, @ActorPrincipalId);

        SET @AssignmentID = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE KPI.Assignment
        SET IsRequired          = @IsRequired,
            TargetValue         = @TargetValue,
            ThresholdGreen      = @ThresholdGreen,
            ThresholdAmber      = @ThresholdAmber,
            ThresholdRed        = @ThresholdRed,
            ThresholdDirection  = @ThresholdDirection,
            SubmitterGuidance   = @SubmitterGuidance,
            IsActive            = 1,   -- reactivate if previously deactivated
            ModifiedOnUtc       = SYSUTCDATETIME(),
            ModifiedBy          = COALESCE(@ActorUPN, SESSION_USER)
        WHERE AssignmentID = @AssignmentID;
    END
END;
GO

CREATE OR ALTER PROCEDURE App.usp_UpsertKpiPeriodSchedule
    @ScheduleName        NVARCHAR(200),
    @FrequencyType       NVARCHAR(20),
    @FrequencyInterval   TINYINT        = NULL,
    @StartDate           DATE,
    @EndDate             DATE           = NULL,
    @SubmissionOpenDay   TINYINT,
    @SubmissionCloseDay  TINYINT,
    @GenerateMonthsAhead TINYINT        = 6,
    @Notes               NVARCHAR(500)  = NULL,
    @ActorUPN            NVARCHAR(320)  = NULL,
    @PeriodScheduleID    INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF @EndDate IS NOT NULL AND @EndDate < @StartDate
        THROW 50116, 'EndDate must be on or after StartDate.', 1;

    IF @SubmissionOpenDay NOT BETWEEN 1 AND 28
        THROW 50117, 'SubmissionOpenDay must be between 1 and 28.', 1;

    IF @SubmissionCloseDay NOT BETWEEN 1 AND 31
        THROW 50118, 'SubmissionCloseDay must be between 1 and 31.', 1;

    IF @SubmissionCloseDay < @SubmissionOpenDay
        THROW 50119, 'SubmissionCloseDay must be on or after SubmissionOpenDay.', 1;

    IF @FrequencyType NOT IN ('Monthly','EveryNMonths','Quarterly','SemiAnnual','Annual')
        THROW 50120, 'FrequencyType is invalid.', 1;

    IF (@FrequencyType = 'EveryNMonths' AND (@FrequencyInterval IS NULL OR @FrequencyInterval NOT BETWEEN 2 AND 12))
        THROW 50121, 'FrequencyInterval must be between 2 and 12 for EveryNMonths schedules.', 1;

    IF (@FrequencyType <> 'EveryNMonths' AND @FrequencyInterval IS NOT NULL)
        THROW 50122, 'FrequencyInterval must be NULL unless FrequencyType is EveryNMonths.', 1;

    SET @PeriodScheduleID = (
        SELECT PeriodScheduleID
        FROM KPI.PeriodSchedule
        WHERE ScheduleName = @ScheduleName
    );

    IF @PeriodScheduleID IS NULL
    BEGIN
        INSERT INTO KPI.PeriodSchedule
            (ScheduleName, FrequencyType, FrequencyInterval, StartDate, EndDate, SubmissionOpenDay, SubmissionCloseDay, GenerateMonthsAhead, Notes)
        VALUES
            (@ScheduleName, @FrequencyType, @FrequencyInterval, @StartDate, @EndDate, @SubmissionOpenDay, @SubmissionCloseDay, @GenerateMonthsAhead, @Notes);

        SET @PeriodScheduleID = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE KPI.PeriodSchedule
        SET FrequencyType       = @FrequencyType,
            FrequencyInterval   = @FrequencyInterval,
            StartDate           = @StartDate,
            EndDate             = @EndDate,
            SubmissionOpenDay   = @SubmissionOpenDay,
            SubmissionCloseDay  = @SubmissionCloseDay,
            GenerateMonthsAhead = @GenerateMonthsAhead,
            Notes               = @Notes,
            IsActive            = 1,
            ModifiedOnUtc       = SYSUTCDATETIME(),
            ModifiedBy          = COALESCE(@ActorUPN, SESSION_USER)
        WHERE PeriodScheduleID = @PeriodScheduleID;
    END
END;
GO

CREATE OR ALTER PROCEDURE App.usp_GenerateKpiPeriods
    @PeriodScheduleID INT            = NULL,
    @ActorUPN         NVARCHAR(320)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CurrentScheduleId   INT;
    DECLARE @StartDate           DATE;
    DECLARE @EndDate             DATE;
    DECLARE @FrequencyType       NVARCHAR(20);
    DECLARE @FrequencyInterval   TINYINT;
    DECLARE @SubmissionOpenDay   TINYINT;
    DECLARE @SubmissionCloseDay  TINYINT;
    DECLARE @GenerateMonthsAhead TINYINT;
    DECLARE @ScheduleName        NVARCHAR(200);
    DECLARE @GenerationEnd       DATE;
    DECLARE @StepMonths          INT;

    DECLARE schedule_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT PeriodScheduleID, StartDate, EndDate, FrequencyType, FrequencyInterval, SubmissionOpenDay, SubmissionCloseDay, GenerateMonthsAhead, ScheduleName
        FROM KPI.PeriodSchedule
        WHERE IsActive = 1
          AND (@PeriodScheduleID IS NULL OR PeriodScheduleID = @PeriodScheduleID)
        ORDER BY PeriodScheduleID;

    OPEN schedule_cursor;
    FETCH NEXT FROM schedule_cursor INTO
        @CurrentScheduleId, @StartDate, @EndDate, @FrequencyType, @FrequencyInterval, @SubmissionOpenDay, @SubmissionCloseDay, @GenerateMonthsAhead, @ScheduleName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @StepMonths = CASE
                              WHEN @FrequencyType = 'Monthly' THEN 1
                              WHEN @FrequencyType = 'EveryNMonths' THEN @FrequencyInterval
                              WHEN @FrequencyType = 'Quarterly' THEN 3
                              WHEN @FrequencyType = 'SemiAnnual' THEN 6
                              WHEN @FrequencyType = 'Annual' THEN 12
                              ELSE 1
                          END;

        IF @EndDate IS NOT NULL
            SET @GenerationEnd = DATEFROMPARTS(YEAR(@EndDate), MONTH(@EndDate), 1);
        ELSE
            SET @GenerationEnd = DATEFROMPARTS(
                YEAR(DATEADD(MONTH, @GenerateMonthsAhead - 1, CAST(SYSUTCDATETIME() AS DATE))),
                MONTH(DATEADD(MONTH, @GenerateMonthsAhead - 1, CAST(SYSUTCDATETIME() AS DATE))),
                1
            );

        ;WITH MonthSeries AS
        (
            SELECT DATEFROMPARTS(YEAR(@StartDate), MONTH(@StartDate), 1) AS MonthStart
            UNION ALL
            SELECT DATEADD(MONTH, @StepMonths, MonthStart)
            FROM MonthSeries
            WHERE DATEADD(MONTH, @StepMonths, MonthStart) <= @GenerationEnd
        )
        MERGE KPI.Period AS target
        USING
        (
            SELECT
                @CurrentScheduleId AS PeriodScheduleID,
                CONCAT(YEAR(MonthStart), '-', RIGHT('0' + CAST(MONTH(MonthStart) AS NVARCHAR(2)), 2)) AS PeriodLabel,
                CAST(YEAR(MonthStart) AS SMALLINT) AS PeriodYear,
                CAST(MONTH(MonthStart) AS TINYINT) AS PeriodMonth,
                DATEFROMPARTS(
                    YEAR(MonthStart),
                    MONTH(MonthStart),
                    CASE
                        WHEN @SubmissionOpenDay > DAY(EOMONTH(MonthStart)) THEN DAY(EOMONTH(MonthStart))
                        ELSE @SubmissionOpenDay
                    END
                ) AS SubmissionOpenDate,
                DATEFROMPARTS(
                    YEAR(MonthStart),
                    MONTH(MonthStart),
                    CASE
                        WHEN @SubmissionCloseDay > DAY(EOMONTH(MonthStart)) THEN DAY(EOMONTH(MonthStart))
                        ELSE @SubmissionCloseDay
                    END
                ) AS SubmissionCloseDate,
                CONCAT('Generated from schedule: ', @ScheduleName) AS Notes
            FROM MonthSeries
        ) AS src
        ON  target.PeriodScheduleID = src.PeriodScheduleID
        AND target.PeriodYear       = src.PeriodYear
        AND target.PeriodMonth      = src.PeriodMonth
        WHEN NOT MATCHED THEN
            INSERT (PeriodScheduleID, PeriodLabel, PeriodYear, PeriodMonth, SubmissionOpenDate, SubmissionCloseDate, AutoTransition, Notes)
            VALUES (src.PeriodScheduleID, src.PeriodLabel, src.PeriodYear, src.PeriodMonth, src.SubmissionOpenDate, src.SubmissionCloseDate, 1, src.Notes)
        WHEN MATCHED AND target.Status IN ('Draft', 'Open') THEN
            UPDATE SET
                target.PeriodLabel         = src.PeriodLabel,
                target.SubmissionOpenDate  = src.SubmissionOpenDate,
                target.SubmissionCloseDate = src.SubmissionCloseDate,
                target.Notes               = src.Notes,
                target.ModifiedOnUtc       = SYSUTCDATETIME(),
                target.ModifiedBy          = COALESCE(@ActorUPN, SESSION_USER);

        FETCH NEXT FROM schedule_cursor INTO
            @CurrentScheduleId, @StartDate, @EndDate, @FrequencyType, @FrequencyInterval, @SubmissionOpenDay, @SubmissionCloseDay, @GenerateMonthsAhead, @ScheduleName;
    END

    CLOSE schedule_cursor;
    DEALLOCATE schedule_cursor;
END;
GO

CREATE OR ALTER PROCEDURE App.usp_UpsertKpiAssignmentTemplate
    @KPICode            NVARCHAR(50),
    @PeriodScheduleID   INT,
    @AccountCode        NVARCHAR(50),
    @OrgUnitCode        NVARCHAR(50)    = NULL,
    @OrgUnitType        NVARCHAR(20)    = 'Site',
    @StartPeriodYear    SMALLINT        = NULL,
    @StartPeriodMonth   TINYINT         = NULL,
    @EndPeriodYear      SMALLINT        = NULL,
    @EndPeriodMonth     TINYINT         = NULL,
    @IsRequired         BIT             = 1,
    @TargetValue        DECIMAL(18,4)   = NULL,
    @ThresholdGreen     DECIMAL(18,4)   = NULL,
    @ThresholdAmber     DECIMAL(18,4)   = NULL,
    @ThresholdRed       DECIMAL(18,4)   = NULL,
    @ThresholdDirection NVARCHAR(10)    = NULL,
    @SubmitterGuidance    NVARCHAR(1000)  = NULL,
    @CustomKpiName        NVARCHAR(200)   = NULL,
    @CustomKpiDescription NVARCHAR(1000)  = NULL,
    @ActorUPN             NVARCHAR(320)   = NULL,
    @AssignmentTemplateID INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF (@StartPeriodYear IS NULL AND @StartPeriodMonth IS NOT NULL)
       OR (@StartPeriodYear IS NOT NULL AND @StartPeriodMonth IS NULL)
        THROW 50129, 'Start period year and month must both be provided or both be NULL.', 1;

    IF @StartPeriodMonth IS NOT NULL AND @StartPeriodMonth NOT BETWEEN 1 AND 12
        THROW 50130, 'StartPeriodMonth must be between 1 and 12.', 1;

    IF (@EndPeriodYear IS NULL AND @EndPeriodMonth IS NOT NULL)
       OR (@EndPeriodYear IS NOT NULL AND @EndPeriodMonth IS NULL)
        THROW 50131, 'End period year and month must both be provided or both be NULL.', 1;

    IF @EndPeriodMonth IS NOT NULL AND @EndPeriodMonth NOT BETWEEN 1 AND 12
        THROW 50132, 'EndPeriodMonth must be between 1 and 12.', 1;

    IF @StartPeriodYear IS NOT NULL
       AND @EndPeriodYear IS NOT NULL
       AND (@EndPeriodYear * 100 + @EndPeriodMonth) < (@StartPeriodYear * 100 + @StartPeriodMonth)
        THROW 50133, 'End period must be on or after the start period.', 1;

    DECLARE @KPIID INT = (SELECT KPIID FROM KPI.Definition WHERE KPICode = @KPICode AND IsActive = 1);
    IF @KPIID IS NULL
        THROW 50134, 'KPI not found or inactive for provided KPICode.', 1;

    IF NOT EXISTS (SELECT 1 FROM KPI.PeriodSchedule WHERE PeriodScheduleID = @PeriodScheduleID AND IsActive = 1)
        THROW 50137, 'Schedule not found or inactive.', 1;

    DECLARE @ScheduleStartDate DATE;
    DECLARE @ScheduleEndDate DATE;

    SELECT
        @ScheduleStartDate = StartDate,
        @ScheduleEndDate = EndDate
    FROM KPI.PeriodSchedule
    WHERE PeriodScheduleID = @PeriodScheduleID
      AND IsActive = 1;

    IF @StartPeriodYear IS NULL OR @StartPeriodMonth IS NULL
    BEGIN
        SET @StartPeriodYear = YEAR(@ScheduleStartDate);
        SET @StartPeriodMonth = MONTH(@ScheduleStartDate);
    END

    IF @EndPeriodYear IS NULL AND @EndPeriodMonth IS NULL AND @ScheduleEndDate IS NOT NULL
    BEGIN
        SET @EndPeriodYear = YEAR(@ScheduleEndDate);
        SET @EndPeriodMonth = MONTH(@ScheduleEndDate);
    END

    DECLARE @AccountId INT = (SELECT AccountId FROM Dim.Account WHERE AccountCode = @AccountCode AND IsActive = 1);
    IF @AccountId IS NULL
        THROW 50135, 'Account not found or inactive.', 1;

    DECLARE @OrgUnitId INT = NULL;
    IF @OrgUnitCode IS NOT NULL
    BEGIN
        SELECT @OrgUnitId = OrgUnitId
        FROM Dim.OrgUnit
        WHERE AccountId = @AccountId
          AND OrgUnitCode = @OrgUnitCode
          AND OrgUnitType = @OrgUnitType
          AND IsActive = 1;

        IF @OrgUnitId IS NULL
            THROW 50136, 'OrgUnit not found or inactive for provided AccountCode + OrgUnitCode.', 1;
    END

    SET @AssignmentTemplateID = (
        SELECT AssignmentTemplateID
        FROM KPI.AssignmentTemplate
        WHERE KPIID = @KPIID
          AND PeriodScheduleID = @PeriodScheduleID
          AND AccountId = @AccountId
          AND (
                (@OrgUnitId IS NULL AND OrgUnitId IS NULL)
                OR OrgUnitId = @OrgUnitId
              )
    );

    IF @AssignmentTemplateID IS NULL
    BEGIN
        INSERT INTO KPI.AssignmentTemplate
            (KPIID, PeriodScheduleID, AccountId, OrgUnitId, StartPeriodYear, StartPeriodMonth, EndPeriodYear, EndPeriodMonth,
             IsRequired, TargetValue, ThresholdGreen, ThresholdAmber, ThresholdRed, ThresholdDirection, SubmitterGuidance,
             CustomKpiName, CustomKpiDescription)
        VALUES
            (@KPIID, @PeriodScheduleID, @AccountId, @OrgUnitId, @StartPeriodYear, @StartPeriodMonth, @EndPeriodYear, @EndPeriodMonth,
             @IsRequired, @TargetValue, @ThresholdGreen, @ThresholdAmber, @ThresholdRed, @ThresholdDirection, @SubmitterGuidance,
             @CustomKpiName, @CustomKpiDescription);

        SET @AssignmentTemplateID = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE KPI.AssignmentTemplate
        SET PeriodScheduleID      = @PeriodScheduleID,
            StartPeriodYear       = @StartPeriodYear,
            StartPeriodMonth      = @StartPeriodMonth,
            EndPeriodYear         = @EndPeriodYear,
            EndPeriodMonth        = @EndPeriodMonth,
            IsRequired            = @IsRequired,
            TargetValue           = @TargetValue,
            ThresholdGreen        = @ThresholdGreen,
            ThresholdAmber        = @ThresholdAmber,
            ThresholdRed          = @ThresholdRed,
            ThresholdDirection    = @ThresholdDirection,
            SubmitterGuidance     = @SubmitterGuidance,
            CustomKpiName         = @CustomKpiName,
            CustomKpiDescription  = @CustomKpiDescription,
            IsActive              = 1,
            ModifiedOnUtc         = SYSUTCDATETIME(),
            ModifiedBy            = COALESCE(@ActorUPN, SESSION_USER)
        WHERE AssignmentTemplateID = @AssignmentTemplateID;
    END
END;
GO

CREATE OR ALTER PROCEDURE App.usp_MaterializeKpiAssignmentTemplates
    @AssignmentTemplateID   INT           = NULL,
    @PeriodScheduleIDFilter INT           = NULL,
    @ActorUPN               NVARCHAR(320) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @CurrentTemplateId INT,
        @TemplateKpiCode NVARCHAR(50),
        @TemplateScheduleId INT,
        @TemplateScheduleStartDate DATE,
        @TemplateScheduleEndDate DATE,
        @TemplateAccountCode NVARCHAR(50),
        @TemplateOrgUnitCode NVARCHAR(50),
        @TemplateOrgUnitType NVARCHAR(20),
        @TemplateStartYear SMALLINT,
        @TemplateStartMonth TINYINT,
        @TemplateEndYear SMALLINT,
        @TemplateEndMonth TINYINT,
        @TemplateIsRequired BIT,
        @TemplateTargetValue DECIMAL(18,4),
        @TemplateThresholdGreen DECIMAL(18,4),
        @TemplateThresholdAmber DECIMAL(18,4),
        @TemplateThresholdRed DECIMAL(18,4),
        @TemplateThresholdDirection NVARCHAR(10),
        @TemplateSubmitterGuidance NVARCHAR(1000),
        -- Used when expanding account-wide templates to per-site assignments
        @SiteOrgUnitCode NVARCHAR(50);

    DECLARE template_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT
            t.AssignmentTemplateID,
            d.KPICode,
            t.PeriodScheduleID,
            sched.StartDate,
            sched.EndDate,
            acct.AccountCode,
            ou.OrgUnitCode,
            COALESCE(ou.OrgUnitType, 'Site') AS OrgUnitType,
            t.StartPeriodYear,
            t.StartPeriodMonth,
            t.EndPeriodYear,
            t.EndPeriodMonth,
            t.IsRequired,
            t.TargetValue,
            t.ThresholdGreen,
            t.ThresholdAmber,
            t.ThresholdRed,
            t.ThresholdDirection,
            t.SubmitterGuidance
        FROM KPI.AssignmentTemplate AS t
        JOIN KPI.Definition         AS d     ON d.KPIID              = t.KPIID
        JOIN KPI.PeriodSchedule     AS sched ON sched.PeriodScheduleID = t.PeriodScheduleID
        JOIN Dim.Account            AS acct  ON acct.AccountId       = t.AccountId
        LEFT JOIN Dim.OrgUnit       AS ou    ON ou.OrgUnitId         = t.OrgUnitId
        WHERE t.IsActive = 1
          AND sched.IsActive = 1
          AND (@AssignmentTemplateID   IS NULL OR t.AssignmentTemplateID = @AssignmentTemplateID)
          AND (@PeriodScheduleIDFilter IS NULL OR t.PeriodScheduleID    = @PeriodScheduleIDFilter)
        ORDER BY t.AssignmentTemplateID;

    OPEN template_cursor;
    FETCH NEXT FROM template_cursor INTO
        @CurrentTemplateId, @TemplateKpiCode, @TemplateScheduleId, @TemplateScheduleStartDate, @TemplateScheduleEndDate,
        @TemplateAccountCode, @TemplateOrgUnitCode, @TemplateOrgUnitType,
        @TemplateStartYear, @TemplateStartMonth, @TemplateEndYear, @TemplateEndMonth, @TemplateIsRequired,
        @TemplateTargetValue, @TemplateThresholdGreen, @TemplateThresholdAmber, @TemplateThresholdRed,
        @TemplateThresholdDirection, @TemplateSubmitterGuidance;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @CurrentPeriodYear SMALLINT;
        DECLARE @CurrentPeriodMonth TINYINT;

        -- Periods already belong to the right schedule — no frequency modulo needed
        DECLARE period_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT PeriodYear, PeriodMonth
            FROM KPI.Period
            WHERE PeriodScheduleID = @TemplateScheduleId
              AND (PeriodYear * 100 + PeriodMonth) >= (
                    COALESCE(@TemplateStartYear, YEAR(@TemplateScheduleStartDate)) * 100
                    + COALESCE(@TemplateStartMonth, MONTH(@TemplateScheduleStartDate))
                  )
              AND (
                    @TemplateEndYear IS NULL
                    OR (PeriodYear * 100 + PeriodMonth) <= (@TemplateEndYear * 100 + @TemplateEndMonth)
                  )
            ORDER BY PeriodYear, PeriodMonth;

        OPEN period_cursor;
        FETCH NEXT FROM period_cursor INTO @CurrentPeriodYear, @CurrentPeriodMonth;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            DECLARE @GeneratedAssignmentId INT;

            IF @TemplateOrgUnitCode IS NULL
            BEGIN
                -- Account-wide template: expand to one per-site assignment for every active site
                DECLARE site_cursor CURSOR LOCAL FAST_FORWARD FOR
                    SELECT ou.OrgUnitCode
                    FROM Dim.OrgUnit AS ou
                    JOIN Dim.Account AS acct ON acct.AccountId = ou.AccountId
                    WHERE acct.AccountCode = @TemplateAccountCode
                      AND ou.OrgUnitType   = 'Site'
                      AND ou.IsActive      = 1;

                OPEN site_cursor;
                FETCH NEXT FROM site_cursor INTO @SiteOrgUnitCode;

                WHILE @@FETCH_STATUS = 0
                BEGIN
                    SET @GeneratedAssignmentId = NULL;
                    EXEC App.usp_AssignKpi
                        @KPICode              = @TemplateKpiCode,
                        @AccountCode          = @TemplateAccountCode,
                        @OrgUnitCode          = @SiteOrgUnitCode,
                        @OrgUnitType          = 'Site',
                        @PeriodScheduleID     = @TemplateScheduleId,
                        @PeriodYear           = @CurrentPeriodYear,
                        @PeriodMonth          = @CurrentPeriodMonth,
                        @AssignmentTemplateID = @CurrentTemplateId,
                        @IsRequired           = @TemplateIsRequired,
                        @TargetValue          = @TemplateTargetValue,
                        @ThresholdGreen       = @TemplateThresholdGreen,
                        @ThresholdAmber       = @TemplateThresholdAmber,
                        @ThresholdRed         = @TemplateThresholdRed,
                        @ThresholdDirection   = @TemplateThresholdDirection,
                        @SubmitterGuidance    = @TemplateSubmitterGuidance,
                        @ActorUPN             = @ActorUPN,
                        @AssignmentID         = @GeneratedAssignmentId OUTPUT;

                    FETCH NEXT FROM site_cursor INTO @SiteOrgUnitCode;
                END

                CLOSE site_cursor;
                DEALLOCATE site_cursor;
            END
            ELSE
            BEGIN
                -- Site-specific template: single assignment
                SET @GeneratedAssignmentId = NULL;
                EXEC App.usp_AssignKpi
                    @KPICode              = @TemplateKpiCode,
                    @AccountCode          = @TemplateAccountCode,
                    @OrgUnitCode          = @TemplateOrgUnitCode,
                    @OrgUnitType          = @TemplateOrgUnitType,
                    @PeriodScheduleID     = @TemplateScheduleId,
                    @PeriodYear           = @CurrentPeriodYear,
                    @PeriodMonth          = @CurrentPeriodMonth,
                    @AssignmentTemplateID = @CurrentTemplateId,
                    @IsRequired           = @TemplateIsRequired,
                    @TargetValue          = @TemplateTargetValue,
                    @ThresholdGreen       = @TemplateThresholdGreen,
                    @ThresholdAmber       = @TemplateThresholdAmber,
                    @ThresholdRed         = @TemplateThresholdRed,
                    @ThresholdDirection   = @TemplateThresholdDirection,
                    @SubmitterGuidance    = @TemplateSubmitterGuidance,
                    @ActorUPN             = @ActorUPN,
                    @AssignmentID         = @GeneratedAssignmentId OUTPUT;
            END

            FETCH NEXT FROM period_cursor INTO @CurrentPeriodYear, @CurrentPeriodMonth;
        END

        CLOSE period_cursor;
        DEALLOCATE period_cursor;

        FETCH NEXT FROM template_cursor INTO
            @CurrentTemplateId, @TemplateKpiCode, @TemplateScheduleId, @TemplateScheduleStartDate, @TemplateScheduleEndDate,
            @TemplateAccountCode, @TemplateOrgUnitCode, @TemplateOrgUnitType,
            @TemplateStartYear, @TemplateStartMonth, @TemplateEndYear, @TemplateEndMonth, @TemplateIsRequired,
            @TemplateTargetValue, @TemplateThresholdGreen, @TemplateThresholdAmber, @TemplateThresholdRed,
            @TemplateThresholdDirection, @TemplateSubmitterGuidance;
    END

    CLOSE template_cursor;
    DEALLOCATE template_cursor;
END;
GO

CREATE OR ALTER PROCEDURE App.usp_DeactivateKpiAssignment
    @AssignmentID   INT,
    @ActorUPN       NVARCHAR(320) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM KPI.Assignment WHERE AssignmentID = @AssignmentID)
        THROW 50114, 'Assignment not found.', 1;

    -- Cannot deactivate if submissions exist for this assignment
    IF EXISTS (
        SELECT 1 FROM KPI.Submission      -- forward ref: created in migration 007
        WHERE AssignmentID = @AssignmentID
    )
        THROW 50115, 'Cannot deactivate an assignment that has submissions.', 1;

    UPDATE KPI.Assignment
    SET IsActive      = 0,
        ModifiedOnUtc = SYSUTCDATETIME(),
        ModifiedBy    = COALESCE(@ActorUPN, SESSION_USER)
    WHERE AssignmentID = @AssignmentID;
END;
GO

CREATE OR ALTER PROCEDURE App.usp_SetEscalationContact
    @AccountCode        NVARCHAR(50),
    @SiteCode           NVARCHAR(50),
    @PeriodScheduleID   INT,
    @PeriodYear         SMALLINT,
    @PeriodMonth        TINYINT,
    @EscalationLevel    TINYINT,          -- 1, 2, or 3
    @PrincipalUPN       NVARCHAR(320),    -- UPN of the contact user
    @ReminderDelayDays  TINYINT           = 2,
    @ActorUPN           NVARCHAR(320)     = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @EscalationLevel NOT BETWEEN 1 AND 3
        THROW 50120, 'EscalationLevel must be 1, 2, or 3.', 1;

    DECLARE @AccountId INT = (SELECT AccountId FROM Dim.Account WHERE AccountCode = @AccountCode);
    IF @AccountId IS NULL
        THROW 50121, 'Account not found.', 1;

    DECLARE @OrgUnitId INT = (
        SELECT OrgUnitId FROM Dim.OrgUnit
        WHERE AccountId = @AccountId AND OrgUnitCode = @SiteCode AND OrgUnitType = 'Site'
    );
    IF @OrgUnitId IS NULL
        THROW 50122, 'Site not found for provided AccountCode + SiteCode.', 1;

    DECLARE @PeriodID INT = (
        SELECT PeriodID FROM KPI.Period
        WHERE PeriodScheduleID = @PeriodScheduleID
          AND PeriodYear       = @PeriodYear
          AND PeriodMonth      = @PeriodMonth
    );
    IF @PeriodID IS NULL
        THROW 50123, 'Period not found for this schedule/year/month.', 1;

    DECLARE @PrincipalId INT = (SELECT UserId FROM Sec.[User] WHERE UPN = @PrincipalUPN);
    IF @PrincipalId IS NULL
        THROW 50124, 'User not found for provided UPN.', 1;

    -- Deactivate any existing contact at this level for this site+period
    UPDATE KPI.EscalationContact
    SET IsActive      = 0,
        ModifiedOnUtc = SYSUTCDATETIME()
    WHERE OrgUnitId       = @OrgUnitId
      AND PeriodID        = @PeriodID
      AND EscalationLevel = @EscalationLevel
      AND IsActive        = 1;

    -- Insert new active contact
    INSERT INTO KPI.EscalationContact
        (OrgUnitId, PeriodID, EscalationLevel, PrincipalId, ReminderDelayDays)
    VALUES
        (@OrgUnitId, @PeriodID, @EscalationLevel, @PrincipalId, @ReminderDelayDays);
END;
GO

CREATE OR ALTER PROCEDURE App.usp_SubmitKpi
    @AssignmentExternalId   UNIQUEIDENTIFIER,
    @SubmitterUPN           NVARCHAR(320),
    @SubmissionValue        DECIMAL(18,4)   = NULL,
    @SubmissionText         NVARCHAR(1000)  = NULL,  -- also used for DropDown selections
    @SubmissionBoolean      BIT             = NULL,  -- used when DataType = 'Boolean'
    @SubmissionNotes        NVARCHAR(500)   = NULL,
    @SourceType             NVARCHAR(20)    = 'Manual',
    @LockOnSubmit           BIT             = 1,   -- set to 0 for draft saves
    @ChangeReason           NVARCHAR(500)   = NULL,
    @BypassLock             BIT             = 0,   -- set to 1 for KpiAdmin post-close edits
    @SubmissionID           INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRAN;

    -- Resolve assignment
    DECLARE @AssignmentID INT;
    DECLARE @PeriodID     INT;
    DECLARE @KPIID        INT;

    SELECT
        @AssignmentID = a.AssignmentID,
        @PeriodID     = a.PeriodID,
        @KPIID        = a.KPIID
    FROM KPI.Assignment AS a
    WHERE a.ExternalId = @AssignmentExternalId
      AND a.IsActive   = 1;

    IF @AssignmentID IS NULL
    BEGIN
        ROLLBACK;
        THROW 50201, 'Assignment not found or inactive.', 1;
    END

    -- Validate period is open and within submission window
    DECLARE @PeriodStatus NVARCHAR(20);
    DECLARE @CloseDate    DATE;

    SELECT
        @PeriodStatus = Status,
        @CloseDate    = SubmissionCloseDate
    FROM KPI.Period
    WHERE PeriodID = @PeriodID;

    IF @BypassLock = 0 AND @PeriodStatus <> 'Open'
    BEGIN
        ROLLBACK;
        THROW 50202, 'Submissions are not accepted: period is not Open.', 1;
    END

    IF @BypassLock = 0 AND CAST(SYSUTCDATETIME() AS DATE) > @CloseDate
    BEGIN
        ROLLBACK;
        THROW 50203, 'Submissions are not accepted: the submission window has closed.', 1;
    END

    -- Resolve submitter principal
    DECLARE @SubmitterPrincipalId INT = (
        SELECT UserId FROM Sec.[User] WHERE UPN = @SubmitterUPN
    );
    IF @SubmitterPrincipalId IS NULL
    BEGIN
        ROLLBACK;
        THROW 50204, 'Submitter user not found.', 1;
    END

    -- Get existing submission if any
    DECLARE @ExistingSubmissionID  INT;
    DECLARE @ExistingLockState     NVARCHAR(25);

    SELECT
        @ExistingSubmissionID = SubmissionID,
        @ExistingLockState    = LockState
    FROM KPI.Submission
    WHERE AssignmentID = @AssignmentID;

    IF @ExistingSubmissionID IS NOT NULL AND @ExistingLockState <> 'Unlocked' AND @BypassLock = 0
    BEGIN
        ROLLBACK;
        THROW 50205, 'This KPI submission is locked and cannot be modified.', 1;
    END

    -- KpiAdmin bypass: unlock the existing submission so the trigger allows value changes
    IF @BypassLock = 1 AND @ExistingSubmissionID IS NOT NULL AND @ExistingLockState <> 'Unlocked'
    BEGIN
        UPDATE KPI.Submission
        SET LockState           = 'Unlocked',
            LockedAt            = NULL,
            LockedByPrincipalId = NULL,
            ModifiedOnUtc       = SYSUTCDATETIME()
        WHERE SubmissionID = @ExistingSubmissionID;
    END

    DECLARE @NewLockState NVARCHAR(25) =
        CASE
            WHEN @SourceType = 'Automated' THEN 'LockedByAuto'
            WHEN @LockOnSubmit = 1         THEN 'Locked'
            ELSE 'Unlocked'
        END;

    DECLARE @LockedAt           DATETIME2 = CASE WHEN @NewLockState <> 'Unlocked' THEN SYSUTCDATETIME() ELSE NULL END;
    DECLARE @LockedByPrincipalId INT      = CASE WHEN @NewLockState <> 'Unlocked' THEN @SubmitterPrincipalId ELSE NULL END;

    IF @ExistingSubmissionID IS NULL
    BEGIN
        -- First submission for this assignment
        INSERT INTO KPI.Submission
            (AssignmentID, SubmittedByPrincipalId, SubmittedAt,
             SubmissionValue, SubmissionText, SubmissionBoolean, SubmissionNotes,
             SourceType, LockState, LockedAt, LockedByPrincipalId)
        VALUES
            (@AssignmentID, @SubmitterPrincipalId, SYSUTCDATETIME(),
             @SubmissionValue, @SubmissionText, @SubmissionBoolean, @SubmissionNotes,
             @SourceType, @NewLockState, @LockedAt, @LockedByPrincipalId);

        SET @SubmissionID = SCOPE_IDENTITY();

        -- Write audit entry
        INSERT INTO KPI.SubmissionAudit
            (SubmissionID, ChangedByPrincipalId, Action, NewValue, ChangeReason)
        VALUES
            (@SubmissionID, @SubmitterPrincipalId, 'Insert',
             (SELECT @SubmissionValue AS SubmissionValue, @NewLockState AS LockState FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
             @ChangeReason);
    END
    ELSE
    BEGIN
        -- Update existing unlocked submission (draft → final)
        DECLARE @OldValue NVARCHAR(MAX);
        SELECT @OldValue = (
            SELECT SubmissionValue, SubmissionText, SubmissionNotes, LockState
            FROM KPI.Submission WHERE SubmissionID = @ExistingSubmissionID
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        -- Direct UPDATE bypasses the trigger since LockState was 'Unlocked'
        UPDATE KPI.Submission
        SET SubmissionValue       = @SubmissionValue,
            SubmissionText        = @SubmissionText,
            SubmissionBoolean     = @SubmissionBoolean,
            SubmissionNotes       = @SubmissionNotes,
            SourceType            = @SourceType,
            LockState             = @NewLockState,
            LockedAt              = @LockedAt,
            LockedByPrincipalId   = @LockedByPrincipalId,
            ModifiedOnUtc         = SYSUTCDATETIME()
        WHERE SubmissionID = @ExistingSubmissionID;

        SET @SubmissionID = @ExistingSubmissionID;

        INSERT INTO KPI.SubmissionAudit
            (SubmissionID, ChangedByPrincipalId, Action, OldValue, NewValue, ChangeReason)
        VALUES
            (@SubmissionID, @SubmitterPrincipalId, 'Update',
             @OldValue,
             (SELECT @SubmissionValue AS SubmissionValue, @NewLockState AS LockState FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
             @ChangeReason);
    END

    -- Resolve reminder state for this site+period if submission is locked
    IF @NewLockState <> 'Unlocked'
    BEGIN
        DECLARE @SiteOrgUnitId INT = (
            SELECT OrgUnitId FROM KPI.Assignment WHERE AssignmentID = @AssignmentID
        );

        -- Check if ALL required assignments for this site+period are now submitted
        DECLARE @TotalRequired  INT;
        DECLARE @TotalSubmitted INT;

        SELECT @TotalRequired = COUNT(*)
        FROM KPI.Assignment
        WHERE OrgUnitId = @SiteOrgUnitId
          AND PeriodID  = @PeriodID
          AND IsRequired = 1
          AND IsActive   = 1;

        SELECT @TotalSubmitted = COUNT(*)
        FROM KPI.Assignment AS a
        JOIN KPI.Submission AS s ON s.AssignmentID = a.AssignmentID
        WHERE a.OrgUnitId = @SiteOrgUnitId
          AND a.PeriodID  = @PeriodID
          AND a.IsRequired = 1
          AND a.IsActive   = 1
          AND s.LockState <> 'Unlocked';

        IF @TotalRequired > 0 AND @TotalSubmitted >= @TotalRequired
        BEGIN
            UPDATE Workflow.ReminderState
            SET IsResolved    = 1,
                ResolvedAt    = SYSUTCDATETIME(),
                ModifiedOnUtc = SYSUTCDATETIME()
            WHERE OrgUnitId  = @SiteOrgUnitId
              AND PeriodID   = @PeriodID
              AND IsResolved = 0;
        END
    END

    COMMIT;
END;
GO

CREATE OR ALTER PROCEDURE App.usp_ClosePeriod
    @PeriodID   INT,
    @ActorUPN   NVARCHAR(320) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRAN;

    IF NOT EXISTS (SELECT 1 FROM KPI.Period WHERE PeriodID = @PeriodID)
    BEGIN
        ROLLBACK;
        THROW 50210, 'Period not found.', 1;
    END

    DECLARE @CurrentStatus NVARCHAR(20) = (
        SELECT Status FROM KPI.Period WHERE PeriodID = @PeriodID
    );

    IF @CurrentStatus <> 'Open'
    BEGIN
        ROLLBACK;
        THROW 50211, 'Only Open periods can be closed.', 1;
    END

    DECLARE @ActorPrincipalId INT = NULL;
    IF @ActorUPN IS NOT NULL
        SELECT @ActorPrincipalId = UserId FROM Sec.[User] WHERE UPN = @ActorUPN;

    -- Lock all Unlocked submissions for this period with LockedByPeriodClose
    UPDATE KPI.Submission
    SET LockState           = 'LockedByPeriodClose',
        LockedAt            = SYSUTCDATETIME(),
        LockedByPrincipalId = @ActorPrincipalId,
        ModifiedOnUtc       = SYSUTCDATETIME()
    WHERE AssignmentID IN (
        SELECT AssignmentID FROM KPI.Assignment WHERE PeriodID = @PeriodID
    )
      AND LockState = 'Unlocked';

    DECLARE @LockedCount INT = @@ROWCOUNT;

    -- Write audit for each force-locked submission
    INSERT INTO KPI.SubmissionAudit
        (SubmissionID, ChangedByPrincipalId, Action, OldValue, NewValue, ChangeReason)
    SELECT
        s.SubmissionID,
        @ActorPrincipalId,
        'PeriodClose',
        '{"LockState":"Unlocked"}',
        '{"LockState":"LockedByPeriodClose"}',
        CONCAT('Period closed by ', COALESCE(@ActorUPN, 'system'))
    FROM KPI.Submission AS s
    JOIN KPI.Assignment AS a ON a.AssignmentID = s.AssignmentID
    WHERE a.PeriodID    = @PeriodID
      AND s.LockState   = 'LockedByPeriodClose'
      AND s.LockedAt   >= DATEADD(SECOND, -5, SYSUTCDATETIME());  -- only rows just locked

    -- Transition period status
    UPDATE KPI.Period
    SET Status        = 'Closed',
        ModifiedOnUtc = SYSUTCDATETIME(),
        ModifiedBy    = COALESCE(@ActorUPN, SESSION_USER)
    WHERE PeriodID = @PeriodID;

    COMMIT;

    SELECT @LockedCount AS SubmissionsForceLockedOnClose;
END;
GO

CREATE OR ALTER PROCEDURE App.usp_InitialiseReminderState
    @PeriodID   INT,
    @ActorUPN   NVARCHAR(320) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM KPI.Period WHERE PeriodID = @PeriodID AND Status = 'Open')
        THROW 50220, 'Period not found or not Open.', 1;

    DECLARE @OpenDate DATE = (
        SELECT SubmissionOpenDate FROM KPI.Period WHERE PeriodID = @PeriodID
    );

    -- Insert a ReminderState row for each site with at least one required assignment
    -- Skip sites that already have a row (idempotent)
    INSERT INTO Workflow.ReminderState
        (OrgUnitId, PeriodID, CurrentLevel, NextReminderDueAt)
    SELECT DISTINCT
        a.OrgUnitId,
        a.PeriodID,
        1,                          -- start at level 1
        DATEADD(DAY, 2, @OpenDate)  -- default: first reminder 2 days after open
    FROM KPI.Assignment AS a
    WHERE a.PeriodID   = @PeriodID
      AND a.IsRequired = 1
      AND a.IsActive   = 1
      AND a.OrgUnitId  IS NOT NULL
      AND NOT EXISTS (
            SELECT 1 FROM Workflow.ReminderState AS rs
            WHERE rs.OrgUnitId = a.OrgUnitId
              AND rs.PeriodID  = a.PeriodID
          );

    DECLARE @Created INT = @@ROWCOUNT;
    SELECT @Created AS ReminderStateRowsCreated;
END;
GO

CREATE OR ALTER PROCEDURE App.usp_ProcessScheduledPeriods
    @ActorUPN   NVARCHAR(320) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Today DATE = CAST(SYSUTCDATETIME() AS DATE);
    DECLARE @PeriodsOpened INT = 0;
    DECLARE @PeriodsClosed INT = 0;

    -- 1. Open Draft periods whose submission window has started (AutoTransition = 1)
    DECLARE @PeriodIDToOpen INT;

    DECLARE open_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT PeriodID
        FROM KPI.Period
        WHERE Status        = 'Draft'
          AND AutoTransition = 1
          AND SubmissionOpenDate <= @Today
        ORDER BY PeriodScheduleID, PeriodYear, PeriodMonth;

    OPEN open_cursor;
    FETCH NEXT FROM open_cursor INTO @PeriodIDToOpen;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC App.usp_OpenPeriod @PeriodID = @PeriodIDToOpen, @ActorUPN = @ActorUPN;
        SET @PeriodsOpened = @PeriodsOpened + 1;
        FETCH NEXT FROM open_cursor INTO @PeriodIDToOpen;
    END

    CLOSE open_cursor;
    DEALLOCATE open_cursor;

    -- 2. Close Open periods whose submission window has expired (AutoTransition = 1)
    DECLARE @PeriodIDToClose INT;

    DECLARE close_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT PeriodID
        FROM KPI.Period
        WHERE Status         = 'Open'
          AND AutoTransition = 1
          AND SubmissionCloseDate < @Today
        ORDER BY PeriodScheduleID, PeriodYear, PeriodMonth;

    OPEN close_cursor;
    FETCH NEXT FROM close_cursor INTO @PeriodIDToClose;

    DECLARE @CloseResult TABLE (SubmissionsForceLockedOnClose INT);

    WHILE @@FETCH_STATUS = 0
    BEGIN
        DELETE FROM @CloseResult;
        INSERT INTO @CloseResult
        EXEC App.usp_ClosePeriod @PeriodID = @PeriodIDToClose, @ActorUPN = @ActorUPN;
        SET @PeriodsClosed = @PeriodsClosed + 1;
        FETCH NEXT FROM close_cursor INTO @PeriodIDToClose;
    END

    CLOSE close_cursor;
    DEALLOCATE close_cursor;

    -- 3. Roll the generation horizon for all active schedules
    EXEC App.usp_GenerateKpiPeriods @ActorUPN = @ActorUPN;

    -- 4. Return summary for Power Automate / caller
    SELECT @PeriodsOpened AS PeriodsOpened, @PeriodsClosed AS PeriodsClosed;
END;
GO

CREATE OR ALTER VIEW App.vAccountRolePolicies
AS
    SELECT
        AccountRolePolicyId,
        PolicyName,
        RoleCodeTemplate,
        RoleNameTemplate,
        ScopeType,
        OrgUnitType,
        OrgUnitCode,
        CAST(ExpandPerOrgUnit AS bit) AS ExpandPerOrgUnit,
        CAST(IsActive AS bit) AS IsActive
    FROM Sec.AccountRolePolicy;
GO

CREATE OR ALTER VIEW App.vPackageReports
AS
    SELECT
        brp.PackageId,
        br.BiReportId,
        br.ReportCode,
        br.ReportName,
        br.ReportUri,
        CAST(br.IsActive AS bit) AS IsActive,
        br.PackageCount,
        ISNULL(br.PackageList, '') AS PackageList
    FROM Dim.BiReportPackage AS brp
    JOIN App.vBiReports AS br
        ON br.BiReportId = brp.BiReportId;
GO

CREATE OR ALTER VIEW App.vSubmissionTokens
AS
    SELECT
        st.TokenId,
        st.SiteOrgUnitId,
        st.AccountId,
        st.PeriodId,
        site.OrgUnitCode AS SiteCode,
        site.OrgUnitName AS SiteName,
        acct.AccountCode,
        acct.AccountName,
        period.PeriodLabel,
        period.Status AS PeriodStatus,
        CAST(period.SubmissionCloseDate AS DATETIME2) AS PeriodCloseDate,
        st.ExpiresAtUtc,
        st.CreatedBy,
        st.CreatedAtUtc,
        st.RevokedAtUtc
    FROM KPI.SubmissionToken AS st
    JOIN App.vOrgUnits AS site
        ON site.OrgUnitId = st.SiteOrgUnitId
    JOIN App.vAccounts AS acct
        ON acct.AccountId = st.AccountId
    JOIN App.vKpiPeriods AS period
        ON period.PeriodId = st.PeriodId;
GO

CREATE OR ALTER VIEW App.vSubmissionTokenAssignments
AS
    SELECT
        st.TokenId,
        asgn.AssignmentID                                       AS AssignmentId,
        asgn.ExternalId,
        d.KPICode                                               AS KpiCode,
        d.KPIName                                               AS KpiName,
        COALESCE(t.CustomKpiName,        d.KPIName)             AS EffectiveKpiName,
        COALESCE(t.CustomKpiDescription, d.KPIDescription)      AS EffectiveKpiDescription,
        d.Category,
        d.DataType,
        CAST(d.AllowMultiValue AS bit)                          AS AllowMultiValue,
        CASE
            WHEN d.DataType = 'DropDown' THEN
                COALESCE(
                    CASE
                        WHEN asgn.AssignmentTemplateID IS NOT NULL
                         AND EXISTS
                            (
                                SELECT 1
                                FROM KPI.AssignmentTemplateDropDownOption AS x
                                WHERE x.AssignmentTemplateID = asgn.AssignmentTemplateID
                            )
                        THEN
                            (
                                SELECT STRING_AGG(opt.OptionValue, '||') WITHIN GROUP (ORDER BY opt.SortOrder)
                                FROM KPI.AssignmentTemplateDropDownOption AS opt
                                WHERE opt.AssignmentTemplateID = asgn.AssignmentTemplateID
                            )
                    END,
                    (
                        SELECT STRING_AGG(opt.OptionValue, '||') WITHIN GROUP (ORDER BY opt.SortOrder)
                        FROM KPI.DropDownOption AS opt
                        WHERE opt.KPIID = d.KPIID
                          AND opt.IsActive = 1
                    )
                )
            ELSE NULL
        END                                                     AS DropDownOptionsRaw,
        CAST(asgn.IsRequired AS bit)                            AS IsRequired,
        asgn.TargetValue,
        asgn.ThresholdGreen,
        asgn.ThresholdAmber,
        asgn.ThresholdRed,
        COALESCE(asgn.ThresholdDirection, d.ThresholdDirection) AS EffectiveThresholdDirection,
        asgn.SubmitterGuidance,
        sub.SubmissionID                                        AS SubmissionId,
        sub.SubmissionValue,
        sub.SubmissionText,
        sub.SubmissionBoolean,
        sub.SubmissionNotes,
        sub.LockState,
        CAST(CASE WHEN sub.SubmissionID IS NOT NULL THEN 1 ELSE 0 END AS bit) AS IsSubmitted
    FROM App.vSubmissionTokens AS st
    JOIN KPI.Assignment AS asgn
        ON asgn.PeriodID = st.PeriodId
       AND asgn.IsActive = 1
       AND (
            asgn.OrgUnitId = st.SiteOrgUnitId
            OR
            (
                asgn.OrgUnitId IS NULL
                AND asgn.AccountId = st.AccountId
                AND NOT EXISTS
                (
                    SELECT 1
                    FROM KPI.Assignment AS sa
                    WHERE sa.KPIID = asgn.KPIID
                      AND sa.OrgUnitId = st.SiteOrgUnitId
                      AND sa.PeriodID = st.PeriodId
                      AND sa.IsActive = 1
                )
            )
       )
    JOIN KPI.Definition AS d
        ON d.KPIID = asgn.KPIID
    LEFT JOIN KPI.AssignmentTemplate AS t
        ON t.AssignmentTemplateID = asgn.AssignmentTemplateID
    LEFT JOIN KPI.Submission AS sub
        ON sub.AssignmentID = asgn.AssignmentID;
GO

CREATE OR ALTER VIEW App.vSiteSubmissionDetails
AS
    SELECT
        asgn.OrgUnitId                                           AS SiteOrgUnitId,
        asgn.PeriodID                                            AS PeriodId,
        asgn.AssignmentID                                        AS AssignmentId,
        asgn.ExternalId,
        d.KPICode                                                AS KpiCode,
        d.KPIName                                                AS KpiName,
        COALESCE(t.CustomKpiName, d.KPIName)                     AS EffectiveKpiName,
        d.Category,
        d.DataType,
        CAST(asgn.IsRequired AS bit)                             AS IsRequired,
        asgn.TargetValue,
        asgn.ThresholdGreen,
        asgn.ThresholdAmber,
        asgn.ThresholdRed,
        COALESCE(asgn.ThresholdDirection, d.ThresholdDirection)  AS EffectiveThresholdDirection,
        sub.SubmissionID                                         AS SubmissionId,
        sub.SubmissionValue,
        sub.SubmissionText,
        sub.SubmissionBoolean,
        sub.SubmissionNotes,
        sub.LockState,
        u.UPN                                                    AS SubmittedByUpn,
        sub.SubmittedAt,
        CAST(CASE WHEN sub.SubmissionID IS NOT NULL THEN 1 ELSE 0 END AS bit) AS IsSubmitted,
        CASE
            WHEN d.DataType NOT IN ('Numeric','Percentage','Currency') THEN NULL
            WHEN sub.SubmissionValue IS NULL                           THEN NULL
            WHEN asgn.ThresholdGreen IS NULL                           THEN NULL
            WHEN COALESCE(asgn.ThresholdDirection, d.ThresholdDirection) = 'Higher'
            THEN CASE
                WHEN sub.SubmissionValue >= asgn.ThresholdGreen THEN 'Green'
                WHEN sub.SubmissionValue >= asgn.ThresholdAmber THEN 'Amber'
                ELSE 'Red'
            END
            WHEN COALESCE(asgn.ThresholdDirection, d.ThresholdDirection) = 'Lower'
            THEN CASE
                WHEN sub.SubmissionValue <= asgn.ThresholdGreen THEN 'Green'
                WHEN sub.SubmissionValue <= asgn.ThresholdAmber THEN 'Amber'
                ELSE 'Red'
            END
            ELSE NULL
        END                                                      AS RagStatus
    FROM KPI.Assignment AS asgn
    JOIN KPI.Definition AS d
        ON d.KPIID = asgn.KPIID
    LEFT JOIN KPI.AssignmentTemplate AS t
        ON t.AssignmentTemplateID = asgn.AssignmentTemplateID
    LEFT JOIN KPI.Submission AS sub
        ON sub.AssignmentID = asgn.AssignmentID
    LEFT JOIN Sec.[User] AS u
        ON u.UserId = sub.SubmittedByPrincipalId
    WHERE asgn.OrgUnitId IS NOT NULL
      AND asgn.IsActive = 1;
GO

CREATE OR ALTER VIEW App.vKpiSubmissionUnlockState
AS
    SELECT
        a.ExternalId AS AssignmentExternalId,
        sub.SubmissionID AS SubmissionId,
        sub.LockState,
        p.Status AS PeriodStatus
    FROM KPI.Assignment AS a
    JOIN KPI.Period AS p
        ON p.PeriodID = a.PeriodID
    JOIN KPI.Submission AS sub
        ON sub.AssignmentID = a.AssignmentID
    WHERE a.IsActive = 1;
GO

CREATE OR ALTER PROCEDURE App.usp_SetUserActive
    @UserId    INT,
    @IsActive  BIT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE Sec.Principal
    SET IsActive = @IsActive,
        ModifiedOnUtc = SYSUTCDATETIME()
    WHERE PrincipalId = @UserId;

    UPDATE Sec.[User]
    SET IsActive = @IsActive,
        ModifiedOnUtc = SYSUTCDATETIME()
    WHERE UserId = @UserId;
END;
GO

CREATE OR ALTER PROCEDURE App.usp_SetRoleActive
    @RoleId     INT,
    @IsActive   BIT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE Sec.Principal
    SET IsActive = @IsActive,
        ModifiedOnUtc = SYSUTCDATETIME()
    WHERE PrincipalId = @RoleId;
END;
GO

CREATE OR ALTER PROCEDURE App.usp_SetOrgUnitActive
    @OrgUnitId  INT,
    @IsActive   BIT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE Dim.OrgUnit
    SET IsActive = @IsActive,
        ModifiedOnUtc = SYSUTCDATETIME(),
        ModifiedBy = SESSION_USER
    WHERE OrgUnitId = @OrgUnitId;
END;
GO

CREATE OR ALTER PROCEDURE App.usp_SetKpiDefinitionActive
    @KPIID      INT,
    @IsActive   BIT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE KPI.Definition
    SET IsActive = @IsActive,
        ModifiedOnUtc = SYSUTCDATETIME(),
        ModifiedBy = SESSION_USER
    WHERE KPIID = @KPIID;
END;
GO

CREATE OR ALTER PROCEDURE App.usp_SetKpiPeriodScheduleActive
    @PeriodScheduleID INT,
    @IsActive         BIT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE KPI.PeriodSchedule
    SET IsActive = @IsActive,
        ModifiedOnUtc = SYSUTCDATETIME(),
        ModifiedBy = SESSION_USER
    WHERE PeriodScheduleID = @PeriodScheduleID;
END;
GO

CREATE OR ALTER PROCEDURE App.usp_SetKpiAssignmentTemplateActive
    @AssignmentTemplateID INT,
    @IsActive             BIT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE KPI.AssignmentTemplate
    SET IsActive = @IsActive,
        ModifiedOnUtc = SYSUTCDATETIME(),
        ModifiedBy = SESSION_USER
    WHERE AssignmentTemplateID = @AssignmentTemplateID;
END;
GO

CREATE OR ALTER PROCEDURE App.usp_SetKpiAssignmentActive
    @AssignmentID INT,
    @IsActive     BIT
AS
BEGIN
    SET NOCOUNT ON;

    IF @IsActive = 0
    BEGIN
        EXEC App.usp_DeactivateKpiAssignment
            @AssignmentID = @AssignmentID,
            @ActorUPN = NULL;
        RETURN;
    END

    UPDATE KPI.Assignment
    SET IsActive = 1,
        ModifiedOnUtc = SYSUTCDATETIME(),
        ModifiedBy = SESSION_USER
    WHERE AssignmentID = @AssignmentID;
END;
GO

CREATE OR ALTER PROCEDURE Sec.usp_SetDelegationActive
    @PrincipalDelegationId INT,
    @IsActive              BIT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE Sec.PrincipalDelegation
    SET IsActive = @IsActive,
        ModifiedOnUtc = SYSUTCDATETIME(),
        ModifiedBy = SESSION_USER
    WHERE PrincipalDelegationId = @PrincipalDelegationId;
END;
GO

CREATE OR ALTER PROCEDURE App.usp_CreateSubmissionToken
    @SiteOrgUnitId INT,
    @PeriodId      INT,
    @CreatedBy     NVARCHAR(128),
    @TokenId       UNIQUEIDENTIFIER OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @AccountId INT;
    DECLARE @SubmissionCloseDate DATE;
    DECLARE @ExpiresAtUtc DATETIME2;

    SELECT @AccountId = AccountId
    FROM App.vOrgUnits
    WHERE OrgUnitId = @SiteOrgUnitId
      AND OrgUnitType = 'Site'
      AND IsActive = 1;

    IF @AccountId IS NULL
        THROW 50210, 'Active site not found.', 1;

    SELECT @SubmissionCloseDate = CAST(SubmissionCloseDate AS DATE)
    FROM App.vKpiPeriods
    WHERE PeriodId = @PeriodId;

    IF @SubmissionCloseDate IS NULL
        THROW 50211, 'Period not found.', 1;

    SET @ExpiresAtUtc = DATEADD(SECOND, -1, DATEADD(DAY, 1, CAST(@SubmissionCloseDate AS DATETIME2)));
    SET @TokenId = NEWID();

    INSERT INTO KPI.SubmissionToken
        (TokenId, SiteOrgUnitId, AccountId, PeriodId, ExpiresAtUtc, CreatedBy)
    VALUES
        (@TokenId, @SiteOrgUnitId, @AccountId, @PeriodId, @ExpiresAtUtc, @CreatedBy);
END;
GO

CREATE OR ALTER PROCEDURE App.usp_RevokeSubmissionToken
    @TokenId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE KPI.SubmissionToken
    SET RevokedAtUtc = SYSUTCDATETIME()
    WHERE TokenId = @TokenId
      AND RevokedAtUtc IS NULL;

    IF @@ROWCOUNT = 0
        THROW 50212, 'Token not found or already revoked.', 1;
END;
GO

CREATE OR ALTER PROCEDURE App.usp_UnlockKpiSubmission
    @AssignmentExternalId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SubmissionId INT;
    DECLARE @LockState NVARCHAR(25);
    DECLARE @PeriodStatus NVARCHAR(20);

    SELECT
        @SubmissionId = SubmissionId,
        @LockState = LockState,
        @PeriodStatus = PeriodStatus
    FROM App.vKpiSubmissionUnlockState
    WHERE AssignmentExternalId = @AssignmentExternalId;

    IF @SubmissionId IS NULL
        THROW 50220, 'No submission found for this assignment.', 1;

    IF @LockState = 'Unlocked'
        RETURN;

    IF @LockState = 'LockedByPeriodClose'
        THROW 50221, 'This submission was locked when the period closed.', 1;

    IF @PeriodStatus <> 'Open'
        THROW 50222, 'Cannot unlock because the period is not Open.', 1;

    UPDATE KPI.Submission
    SET LockState = 'Unlocked',
        LockedAt = NULL,
        LockedByPrincipalId = NULL,
        ModifiedOnUtc = SYSUTCDATETIME()
    WHERE SubmissionID = @SubmissionId;
END;
GO

CREATE OR ALTER PROCEDURE App.usp_RefreshAccountRolePolicy
    @AccountRolePolicyId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @PolicyName NVARCHAR(200),
        @RoleCodeTemplate NVARCHAR(100),
        @RoleNameTemplate NVARCHAR(200),
        @ScopeType NVARCHAR(15),
        @OrgUnitType NVARCHAR(20),
        @OrgUnitCode NVARCHAR(50),
        @ExpandPerOrgUnit BIT,
        @IsActive BIT;

    SELECT
        @PolicyName = PolicyName,
        @RoleCodeTemplate = RoleCodeTemplate,
        @RoleNameTemplate = RoleNameTemplate,
        @ScopeType = ScopeType,
        @OrgUnitType = OrgUnitType,
        @OrgUnitCode = OrgUnitCode,
        @ExpandPerOrgUnit = ExpandPerOrgUnit,
        @IsActive = IsActive
    FROM Sec.AccountRolePolicy
    WHERE AccountRolePolicyId = @AccountRolePolicyId;

    IF @PolicyName IS NULL OR @IsActive = 0
        RETURN;

    DECLARE
        @AccountId INT,
        @AccountCode NVARCHAR(50),
        @AccountName NVARCHAR(200),
        @ResolvedRoleCode NVARCHAR(100),
        @ResolvedRoleName NVARCHAR(200),
        @ResolvedOrgUnitId INT,
        @ResolvedOrgUnitCode NVARCHAR(50),
        @ResolvedOrgUnitName NVARCHAR(200),
        @RoleId INT;

    DECLARE account_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT AccountId, AccountCode, AccountName
        FROM Dim.Account
        WHERE IsActive = 1
        ORDER BY AccountCode;

    OPEN account_cursor;
    FETCH NEXT FROM account_cursor INTO @AccountId, @AccountCode, @AccountName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @Expanded TABLE
        (
            OrgUnitId   INT NULL,
            OrgUnitCode NVARCHAR(50) NULL,
            OrgUnitName NVARCHAR(200) NULL
        );

        IF @ScopeType = 'ORGUNIT'
        BEGIN
            INSERT INTO @Expanded (OrgUnitId, OrgUnitCode, OrgUnitName)
            SELECT
                ou.OrgUnitId,
                ou.OrgUnitCode,
                ou.OrgUnitName
            FROM Dim.OrgUnit AS ou
            WHERE ou.AccountId = @AccountId
              AND ou.OrgUnitType = @OrgUnitType
              AND (@OrgUnitCode IS NULL OR ou.OrgUnitCode = @OrgUnitCode)
            ORDER BY ou.OrgUnitId;

            IF NOT EXISTS (SELECT 1 FROM @Expanded)
            BEGIN
                FETCH NEXT FROM account_cursor INTO @AccountId, @AccountCode, @AccountName;
                CONTINUE;
            END
        END
        ELSE
        BEGIN
            INSERT INTO @Expanded (OrgUnitId, OrgUnitCode, OrgUnitName)
            VALUES (NULL, NULL, NULL);
        END

        DECLARE expanded_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT OrgUnitId, OrgUnitCode, OrgUnitName
            FROM @Expanded;

        OPEN expanded_cursor;
        FETCH NEXT FROM expanded_cursor INTO @ResolvedOrgUnitId, @ResolvedOrgUnitCode, @ResolvedOrgUnitName;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @ResolvedRoleCode =
                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                    @RoleCodeTemplate,
                    '{AccountCode}', @AccountCode),
                    '{ACCOUNTCODE}', @AccountCode),
                    '{AccountName}', @AccountName),
                    '{ACCOUNTNAME}', @AccountName),
                    '{OrgUnitCode}', COALESCE(@ResolvedOrgUnitCode, '')),
                    '{ORGUNITCODE}', COALESCE(@ResolvedOrgUnitCode, '')),
                    '{OrgUnitName}', COALESCE(@ResolvedOrgUnitName, '')),
                    '{ORGUNITNAME}', COALESCE(@ResolvedOrgUnitName, ''));

            SET @ResolvedRoleName =
                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                    @RoleNameTemplate,
                    '{AccountCode}', @AccountCode),
                    '{ACCOUNTCODE}', @AccountCode),
                    '{AccountName}', @AccountName),
                    '{ACCOUNTNAME}', @AccountName),
                    '{OrgUnitCode}', COALESCE(@ResolvedOrgUnitCode, '')),
                    '{ORGUNITCODE}', COALESCE(@ResolvedOrgUnitCode, '')),
                    '{OrgUnitName}', COALESCE(@ResolvedOrgUnitName, '')),
                    '{ORGUNITNAME}', COALESCE(@ResolvedOrgUnitName, ''));

            EXEC App.UpsertRole
                @RoleCode = @ResolvedRoleCode,
                @RoleName = @ResolvedRoleName,
                @Description = NULL,
                @RoleId = @RoleId OUTPUT;

            INSERT INTO Sec.PrincipalAccessGrant (PrincipalId, AccessType, AccountId, ScopeType, OrgUnitId)
            SELECT
                @RoleId,
                'ACCOUNT',
                @AccountId,
                CASE WHEN @ScopeType = 'ORGUNIT' THEN 'ORGUNIT' ELSE 'NONE' END,
                @ResolvedOrgUnitId
            WHERE NOT EXISTS
            (
                SELECT 1
                FROM Sec.PrincipalAccessGrant AS existing
                WHERE existing.PrincipalId = @RoleId
                  AND existing.AccessType = 'ACCOUNT'
                  AND existing.AccountId = @AccountId
                  AND existing.ScopeType = CASE WHEN @ScopeType = 'ORGUNIT' THEN 'ORGUNIT' ELSE 'NONE' END
                  AND ISNULL(existing.OrgUnitId, -1) = ISNULL(@ResolvedOrgUnitId, -1)
            );

            FETCH NEXT FROM expanded_cursor INTO @ResolvedOrgUnitId, @ResolvedOrgUnitCode, @ResolvedOrgUnitName;
        END

        CLOSE expanded_cursor;
        DEALLOCATE expanded_cursor;

        FETCH NEXT FROM account_cursor INTO @AccountId, @AccountCode, @AccountName;
    END

    CLOSE account_cursor;
    DEALLOCATE account_cursor;
END;
GO

CREATE OR ALTER PROCEDURE App.usp_DeactivateMaterializedRolesForPolicy
    @AccountRolePolicyId INT
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH Expanded AS
    (
        SELECT DISTINCT
            CASE
                WHEN pol.ScopeType = 'ORGUNIT' AND pol.ExpandPerOrgUnit = 1
                    THEN REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                        pol.RoleCodeTemplate,
                        '{AccountCode}', a.AccountCode),
                        '{ACCOUNTCODE}', a.AccountCode),
                        '{AccountName}', a.AccountName),
                        '{ACCOUNTNAME}', a.AccountName),
                        '{OrgUnitCode}', ou.OrgUnitCode),
                        '{ORGUNITCODE}', ou.OrgUnitCode),
                        '{OrgUnitName}', ou.OrgUnitName),
                        '{ORGUNITNAME}', ou.OrgUnitName)
                ELSE REPLACE(REPLACE(REPLACE(REPLACE(
                        pol.RoleCodeTemplate,
                        '{AccountCode}', a.AccountCode),
                        '{ACCOUNTCODE}', a.AccountCode),
                        '{AccountName}', a.AccountName),
                        '{ACCOUNTNAME}', a.AccountName)
            END AS RoleCode
        FROM Sec.AccountRolePolicy AS pol
        CROSS JOIN Dim.Account AS a
        LEFT JOIN Dim.OrgUnit AS ou
            ON pol.ScopeType = 'ORGUNIT'
           AND pol.ExpandPerOrgUnit = 1
           AND ou.AccountId = a.AccountId
           AND ou.OrgUnitType = pol.OrgUnitType
           AND (pol.OrgUnitCode IS NULL OR ou.OrgUnitCode = pol.OrgUnitCode)
        WHERE pol.AccountRolePolicyId = @AccountRolePolicyId
    )
    UPDATE pr
    SET pr.IsActive = 0,
        pr.ModifiedOnUtc = SYSUTCDATETIME(),
        pr.ModifiedBy = 'policy_disable'
    FROM Sec.Principal AS pr
    JOIN Sec.Role AS r
        ON r.RoleId = pr.PrincipalId
    JOIN Expanded AS e
        ON e.RoleCode = r.RoleCode;
END;
GO

CREATE OR ALTER PROCEDURE App.usp_UpsertAccountRolePolicy
    @AccountRolePolicyId INT = NULL,
    @PolicyName          NVARCHAR(200),
    @RoleCodeTemplate    NVARCHAR(100),
    @RoleNameTemplate    NVARCHAR(200),
    @ScopeType           NVARCHAR(15),
    @OrgUnitType         NVARCHAR(20) = NULL,
    @OrgUnitCode         NVARCHAR(50) = NULL,
    @ExpandPerOrgUnit    BIT = 0,
    @ApplyNow            BIT = 0,
    @ResultAccountRolePolicyId INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF @AccountRolePolicyId IS NULL
    BEGIN
        INSERT INTO Sec.AccountRolePolicy
            (PolicyName, RoleCodeTemplate, RoleNameTemplate, ScopeType, OrgUnitType, OrgUnitCode, ExpandPerOrgUnit, IsActive)
        VALUES
            (@PolicyName, UPPER(LTRIM(RTRIM(@RoleCodeTemplate))), @RoleNameTemplate, @ScopeType, @OrgUnitType, @OrgUnitCode, @ExpandPerOrgUnit, 1);

        SET @ResultAccountRolePolicyId = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE Sec.AccountRolePolicy
        SET PolicyName = @PolicyName,
            RoleCodeTemplate = UPPER(LTRIM(RTRIM(@RoleCodeTemplate))),
            RoleNameTemplate = @RoleNameTemplate,
            ScopeType = @ScopeType,
            OrgUnitType = @OrgUnitType,
            OrgUnitCode = @OrgUnitCode,
            ExpandPerOrgUnit = @ExpandPerOrgUnit,
            ModifiedOnUtc = SYSUTCDATETIME()
        WHERE AccountRolePolicyId = @AccountRolePolicyId;

        SET @ResultAccountRolePolicyId = @AccountRolePolicyId;
    END

    IF @ApplyNow = 1
        EXEC App.usp_RefreshAccountRolePolicy @AccountRolePolicyId = @ResultAccountRolePolicyId;
END;
GO

CREATE OR ALTER PROCEDURE App.usp_SetAccountRolePolicyActive
    @AccountRolePolicyId INT,
    @IsActive            BIT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE Sec.AccountRolePolicy
    SET IsActive = @IsActive,
        ModifiedOnUtc = SYSUTCDATETIME()
    WHERE AccountRolePolicyId = @AccountRolePolicyId;

    IF @IsActive = 1
        EXEC App.usp_RefreshAccountRolePolicy @AccountRolePolicyId = @AccountRolePolicyId;
    ELSE
        EXEC App.usp_DeactivateMaterializedRolesForPolicy @AccountRolePolicyId = @AccountRolePolicyId;
END;
GO

-- Reporting views ------------------------------------------------------------
CREATE OR ALTER VIEW Reporting.vw_PBICustomerSecurity
AS
    -- DISTINCT because a user may have multiple site-level grants in one account
    SELECT DISTINCT
        ads.UserUPN         AS UPN,
        ads.AccountId,
        ads.AccountCode,
        ads.AccountName
    FROM Sec.vAuthorizedSitesDynamic AS ads;
GO

CREATE OR ALTER VIEW Reporting.vw_PBIAccount
AS
    SELECT
        a.AccountId,
        a.AccountCode,
        a.AccountName,
        a.IsActive,
        a.CreatedOnUtc
    FROM Dim.Account AS a
    WHERE a.IsActive = 1;
GO

CREATE OR ALTER VIEW Reporting.vw_PBIOrgUnit
AS
    SELECT
        -- Site (primary key for this dimension)
        site.OrgUnitId          AS SiteId,
        site.OrgUnitCode        AS SiteCode,
        site.OrgUnitName        AS SiteName,
        site.CountryCode        AS SiteCountryISOCode,
        site.Path               AS SitePath,
        site.IsActive           AS SiteIsActive,
        -- Country (explicit country link, not necessarily direct parent)
        cty.OrgUnitId           AS CountryId,
        cty.OrgUnitCode         AS CountryCode,
        cty.OrgUnitName         AS CountryName,
        -- Shared geography
        reg.OrgUnitId           AS RegionId,
        reg.OrgUnitCode         AS RegionCode,
        reg.OrgUnitName         AS RegionName,
        sreg.OrgUnitId          AS SubRegionId,
        sreg.OrgUnitCode        AS SubRegionCode,
        sreg.OrgUnitName        AS SubRegionName,
        clus.OrgUnitId          AS ClusterId,
        clus.OrgUnitCode        AS ClusterCode,
        clus.OrgUnitName        AS ClusterName,
        -- Account
        acct.AccountId,
        acct.AccountCode,
        acct.AccountName
    FROM Dim.OrgUnit    AS site
    JOIN Dim.Account    AS acct ON acct.AccountId   = site.AccountId
    LEFT JOIN Dim.OrgUnit AS cty  ON cty.OrgUnitId  = site.CountryOrgUnitId
    LEFT JOIN Dim.OrgUnit AS clus ON clus.OrgUnitId = cty.ParentOrgUnitId
        AND clus.OrgUnitType = 'Cluster'
    LEFT JOIN Dim.OrgUnit AS sreg ON sreg.OrgUnitId = CASE
        WHEN clus.OrgUnitId IS NOT NULL THEN clus.ParentOrgUnitId
        WHEN cty.ParentOrgUnitId IS NOT NULL AND EXISTS (SELECT 1 FROM Dim.OrgUnit x WHERE x.OrgUnitId = cty.ParentOrgUnitId AND x.OrgUnitType = 'SubRegion') THEN cty.ParentOrgUnitId
        ELSE NULL
    END
    LEFT JOIN Dim.OrgUnit AS reg  ON reg.OrgUnitId = CASE
        WHEN sreg.OrgUnitId IS NOT NULL THEN sreg.ParentOrgUnitId
        WHEN clus.OrgUnitId IS NOT NULL AND EXISTS (SELECT 1 FROM Dim.OrgUnit x WHERE x.OrgUnitId = clus.ParentOrgUnitId AND x.OrgUnitType = 'Region') THEN clus.ParentOrgUnitId
        WHEN cty.ParentOrgUnitId IS NOT NULL AND EXISTS (SELECT 1 FROM Dim.OrgUnit x WHERE x.OrgUnitId = cty.ParentOrgUnitId AND x.OrgUnitType = 'Region') THEN cty.ParentOrgUnitId
        ELSE NULL
    END
    WHERE site.OrgUnitType = 'Site'
      AND site.IsActive    = 1
      AND acct.IsActive    = 1;
GO

CREATE OR ALTER VIEW Reporting.vw_PBIPeriod
AS
    SELECT
        per.PeriodID,
        per.ExternalId                  AS PeriodKey,
        per.PeriodLabel,
        per.PeriodYear,
        per.PeriodMonth,
        per.SubmissionOpenDate,
        per.SubmissionCloseDate,
        per.Status,
        per.AutoTransition,
        -- Schedule context
        ps.PeriodScheduleID,
        ps.ScheduleName,
        ps.FrequencyType,
        -- Convenience flags
        CAST(
            CASE WHEN per.Status = 'Open'
                  AND CAST(SYSUTCDATETIME() AS DATE) BETWEEN per.SubmissionOpenDate
                                                         AND per.SubmissionCloseDate
                 THEN 1 ELSE 0
            END AS BIT
        )                               AS IsCurrentlyOpen,
        CASE WHEN per.Status = 'Open'
             THEN DATEDIFF(DAY, CAST(SYSUTCDATETIME() AS DATE), per.SubmissionCloseDate)
             ELSE NULL
        END                             AS DaysRemainingToClose,
        -- Calendar sort key (YYYYMM integer)
        per.PeriodYear * 100 + per.PeriodMonth AS PeriodSortKey
    FROM KPI.Period          AS per
    JOIN KPI.PeriodSchedule  AS ps ON ps.PeriodScheduleID = per.PeriodScheduleID;
GO

CREATE OR ALTER VIEW Reporting.vw_PBIKPIDefinition
AS
    SELECT
        d.KPIID,
        d.ExternalId            AS KPIDefinitionKey,
        d.KPICode,
        d.KPIName,
        d.KPIDescription,
        d.Category              AS KPICategory,
        d.Unit                  AS KPIUnit,
        d.DataType,
        d.CollectionType,
        d.ThresholdDirection    AS DefaultThresholdDirection,
        d.IsActive
    FROM KPI.Definition AS d
    WHERE d.IsActive = 1;
GO

CREATE OR ALTER VIEW Reporting.vw_PBIAssignment
AS
    SELECT
        asgn.AssignmentID,
        asgn.ExternalId                                         AS AssignmentKey,
        -- KPI (effective name resolves template override → library default)
        d.ExternalId                                            AS KPIDefinitionKey,
        d.KPICode,
        COALESCE(tmpl.CustomKpiName, d.KPIName)                 AS KPIName,
        d.KPIName                                               AS LibraryKPIName,
        d.Category                                              AS KPICategory,
        d.Unit                                                  AS KPIUnit,
        d.DataType,
        d.CollectionType,
        -- Period
        per.ExternalId                                          AS PeriodKey,
        per.PeriodLabel,
        per.PeriodYear,
        per.PeriodMonth,
        per.Status                                              AS PeriodStatus,
        per.PeriodScheduleID,
        ps.ScheduleName,
        -- Account and Site
        asgn.AccountId,
        acct.AccountCode,
        acct.AccountName,
        asgn.OrgUnitId                                          AS SiteId,
        ou.OrgUnitCode                                          AS SiteCode,
        ou.OrgUnitName                                          AS SiteName,
        CAST(CASE WHEN asgn.OrgUnitId IS NULL THEN 1 ELSE 0 END AS BIT) AS IsAccountWide,
        -- Assignment configuration
        asgn.IsRequired,
        asgn.TargetValue,
        asgn.ThresholdGreen,
        asgn.ThresholdAmber,
        asgn.ThresholdRed,
        COALESCE(asgn.ThresholdDirection, d.ThresholdDirection) AS EffectiveThresholdDirection,
        asgn.SubmitterGuidance
    FROM KPI.Assignment              AS asgn
    JOIN KPI.Definition              AS d    ON d.KPIID              = asgn.KPIID
    JOIN KPI.Period                  AS per  ON per.PeriodID         = asgn.PeriodID
    JOIN KPI.PeriodSchedule          AS ps   ON ps.PeriodScheduleID  = per.PeriodScheduleID
    JOIN Dim.Account                 AS acct ON acct.AccountId       = asgn.AccountId
    LEFT JOIN Dim.OrgUnit            AS ou   ON ou.OrgUnitId         = asgn.OrgUnitId
    LEFT JOIN KPI.AssignmentTemplate AS tmpl ON tmpl.AssignmentTemplateID = asgn.AssignmentTemplateID
    WHERE asgn.IsActive = 1;
GO

CREATE OR ALTER VIEW Reporting.vw_PBIKPIFact
AS
    SELECT
        -- Keys
        s.ExternalId                                            AS SubmissionKey,
        asgn.ExternalId                                         AS AssignmentKey,
        d.ExternalId                                            AS KPIDefinitionKey,
        per.ExternalId                                          AS PeriodKey,
        -- Period (denormalised for convenience in Power BI)
        per.PeriodLabel,
        per.PeriodYear,
        per.PeriodMonth,
        per.PeriodYear * 100 + per.PeriodMonth                  AS PeriodSortKey,
        per.Status                                              AS PeriodStatus,
        -- KPI (denormalised; effective name resolves template override → library default)
        d.KPICode,
        COALESCE(tmpl.CustomKpiName, d.KPIName)                 AS KPIName,
        d.Category                                              AS KPICategory,
        d.Unit                                                  AS KPIUnit,
        d.DataType,
        d.CollectionType,
        -- Schedule context
        per.PeriodScheduleID,
        ps.ScheduleName,
        -- Assignment context
        asgn.AccountId,
        acct.AccountCode,
        acct.AccountName,
        asgn.OrgUnitId                                          AS SiteId,
        ou.OrgUnitCode                                          AS SiteCode,
        ou.OrgUnitName                                          AS SiteName,
        CAST(CASE WHEN asgn.OrgUnitId IS NULL THEN 1 ELSE 0 END AS BIT) AS IsAccountWide,
        asgn.IsRequired,
        -- Thresholds
        asgn.TargetValue,
        asgn.ThresholdGreen,
        asgn.ThresholdAmber,
        asgn.ThresholdRed,
        COALESCE(asgn.ThresholdDirection, d.ThresholdDirection) AS EffectiveThresholdDirection,
        -- Submission values
        s.SubmissionValue,
        s.SubmissionText,
        s.SubmissionNotes,
        s.SourceType,
        s.LockState,
        s.SubmittedAt,
        s.IsValid,
        s.ValidationNotes,
        s.CreatedOnUtc                                          AS SubmissionCreatedAt,
        -- RAG status
        CASE
            WHEN s.SubmissionValue IS NULL
                THEN 'NoData'
            WHEN asgn.ThresholdGreen IS NULL
                THEN 'NoThreshold'
            WHEN COALESCE(asgn.ThresholdDirection, d.ThresholdDirection) = 'Higher'
                THEN CASE
                    WHEN s.SubmissionValue >= asgn.ThresholdGreen                                      THEN 'Green'
                    WHEN asgn.ThresholdAmber IS NOT NULL AND s.SubmissionValue >= asgn.ThresholdAmber  THEN 'Amber'
                    ELSE 'Red'
                END
            WHEN COALESCE(asgn.ThresholdDirection, d.ThresholdDirection) = 'Lower'
                THEN CASE
                    WHEN s.SubmissionValue <= asgn.ThresholdGreen                                      THEN 'Green'
                    WHEN asgn.ThresholdAmber IS NOT NULL AND s.SubmissionValue <= asgn.ThresholdAmber  THEN 'Amber'
                    ELSE 'Red'
                END
            ELSE 'NoThreshold'
        END AS RAGStatus,
        -- RAG sort order: 1=Red (worst) → 3=Green (best), 4=NoData, 5=NoThreshold
        CASE
            WHEN s.SubmissionValue IS NULL
                THEN 4
            WHEN asgn.ThresholdGreen IS NULL
                THEN 5
            WHEN COALESCE(asgn.ThresholdDirection, d.ThresholdDirection) = 'Higher'
                THEN CASE
                    WHEN s.SubmissionValue >= asgn.ThresholdGreen                                      THEN 3
                    WHEN asgn.ThresholdAmber IS NOT NULL AND s.SubmissionValue >= asgn.ThresholdAmber  THEN 2
                    ELSE 1
                END
            WHEN COALESCE(asgn.ThresholdDirection, d.ThresholdDirection) = 'Lower'
                THEN CASE
                    WHEN s.SubmissionValue <= asgn.ThresholdGreen                                      THEN 3
                    WHEN asgn.ThresholdAmber IS NOT NULL AND s.SubmissionValue <= asgn.ThresholdAmber  THEN 2
                    ELSE 1
                END
            ELSE 5
        END AS RAGSortOrder
    FROM KPI.Submission              AS s
    JOIN KPI.Assignment              AS asgn ON asgn.AssignmentID      = s.AssignmentID
                                            AND asgn.IsActive          = 1
    JOIN KPI.Definition              AS d    ON d.KPIID                = asgn.KPIID
    JOIN KPI.Period                  AS per  ON per.PeriodID           = asgn.PeriodID
    JOIN KPI.PeriodSchedule          AS ps   ON ps.PeriodScheduleID    = per.PeriodScheduleID
    JOIN Dim.Account                 AS acct ON acct.AccountId         = asgn.AccountId
    LEFT JOIN Dim.OrgUnit            AS ou   ON ou.OrgUnitId           = asgn.OrgUnitId
    LEFT JOIN KPI.AssignmentTemplate AS tmpl ON tmpl.AssignmentTemplateID = asgn.AssignmentTemplateID;
GO

CREATE OR ALTER VIEW Reporting.vw_PBIAssignmentStatus
AS
    SELECT
        -- Assignment keys
        asgn.ExternalId                                         AS AssignmentKey,
        d.ExternalId                                            AS KPIDefinitionKey,
        per.ExternalId                                          AS PeriodKey,
        -- Period
        per.PeriodLabel,
        per.PeriodYear,
        per.PeriodMonth,
        per.PeriodYear * 100 + per.PeriodMonth                  AS PeriodSortKey,
        per.Status                                              AS PeriodStatus,
        -- KPI (effective name resolves template override → library default)
        d.KPICode,
        COALESCE(tmpl.CustomKpiName, d.KPIName)                 AS KPIName,
        d.Category                                              AS KPICategory,
        d.Unit                                                  AS KPIUnit,
        d.DataType,
        d.CollectionType,
        -- Schedule context
        per.PeriodScheduleID,
        ps.ScheduleName,
        -- Assignment context
        asgn.AccountId,
        acct.AccountCode,
        acct.AccountName,
        asgn.OrgUnitId                                          AS SiteId,
        ou.OrgUnitCode                                          AS SiteCode,
        ou.OrgUnitName                                          AS SiteName,
        CAST(CASE WHEN asgn.OrgUnitId IS NULL THEN 1 ELSE 0 END AS BIT) AS IsAccountWide,
        asgn.IsRequired,
        asgn.TargetValue,
        asgn.ThresholdGreen,
        asgn.ThresholdAmber,
        asgn.ThresholdRed,
        COALESCE(asgn.ThresholdDirection, d.ThresholdDirection) AS EffectiveThresholdDirection,
        -- Submission (NULL columns = not yet submitted)
        s.ExternalId                                            AS SubmissionKey,
        s.SubmissionValue,
        s.SubmissionText,
        s.SourceType,
        s.LockState,
        s.SubmittedAt,
        s.IsValid,
        -- Derived status flags
        CAST(CASE WHEN s.SubmissionID IS NOT NULL THEN 1 ELSE 0 END AS BIT)             AS IsSubmitted,
        CAST(CASE WHEN s.LockState NOT IN ('Unlocked') AND s.SubmissionID IS NOT NULL
                  THEN 1 ELSE 0 END AS BIT)                                             AS IsLocked,
        -- RAG status (same logic as vw_PBIKPIFact; NULL value → NoData)
        CASE
            WHEN s.SubmissionValue IS NULL
                THEN 'NoData'
            WHEN asgn.ThresholdGreen IS NULL
                THEN 'NoThreshold'
            WHEN COALESCE(asgn.ThresholdDirection, d.ThresholdDirection) = 'Higher'
                THEN CASE
                    WHEN s.SubmissionValue >= asgn.ThresholdGreen                                      THEN 'Green'
                    WHEN asgn.ThresholdAmber IS NOT NULL AND s.SubmissionValue >= asgn.ThresholdAmber  THEN 'Amber'
                    ELSE 'Red'
                END
            WHEN COALESCE(asgn.ThresholdDirection, d.ThresholdDirection) = 'Lower'
                THEN CASE
                    WHEN s.SubmissionValue <= asgn.ThresholdGreen                                      THEN 'Green'
                    WHEN asgn.ThresholdAmber IS NOT NULL AND s.SubmissionValue <= asgn.ThresholdAmber  THEN 'Amber'
                    ELSE 'Red'
                END
            ELSE 'NoThreshold'
        END AS RAGStatus,
        CASE
            WHEN s.SubmissionValue IS NULL
                THEN 4
            WHEN asgn.ThresholdGreen IS NULL
                THEN 5
            WHEN COALESCE(asgn.ThresholdDirection, d.ThresholdDirection) = 'Higher'
                THEN CASE
                    WHEN s.SubmissionValue >= asgn.ThresholdGreen                                      THEN 3
                    WHEN asgn.ThresholdAmber IS NOT NULL AND s.SubmissionValue >= asgn.ThresholdAmber  THEN 2
                    ELSE 1
                END
            WHEN COALESCE(asgn.ThresholdDirection, d.ThresholdDirection) = 'Lower'
                THEN CASE
                    WHEN s.SubmissionValue <= asgn.ThresholdGreen                                      THEN 3
                    WHEN asgn.ThresholdAmber IS NOT NULL AND s.SubmissionValue <= asgn.ThresholdAmber  THEN 2
                    ELSE 1
                END
            ELSE 5
        END AS RAGSortOrder
    FROM KPI.Assignment              AS asgn
    LEFT JOIN KPI.Submission         AS s    ON s.AssignmentID           = asgn.AssignmentID
    JOIN KPI.Definition              AS d    ON d.KPIID                  = asgn.KPIID
    JOIN KPI.Period                  AS per  ON per.PeriodID             = asgn.PeriodID
    JOIN KPI.PeriodSchedule          AS ps   ON ps.PeriodScheduleID      = per.PeriodScheduleID
    JOIN Dim.Account                 AS acct ON acct.AccountId           = asgn.AccountId
    LEFT JOIN Dim.OrgUnit            AS ou   ON ou.OrgUnitId             = asgn.OrgUnitId
    LEFT JOIN KPI.AssignmentTemplate AS tmpl ON tmpl.AssignmentTemplateID = asgn.AssignmentTemplateID
    WHERE asgn.IsActive = 1;
GO

CREATE OR ALTER VIEW Reporting.vw_AccountKPICompletion
AS
    SELECT
        acct.AccountId,
        acct.AccountCode,
        acct.AccountName,
        per.PeriodID,
        per.ExternalId                  AS PeriodKey,
        per.PeriodLabel,
        per.PeriodYear,
        per.PeriodMonth,
        per.PeriodYear * 100 + per.PeriodMonth AS PeriodSortKey,
        per.Status                      AS PeriodStatus,
        per.SubmissionCloseDate,
        COUNT(asgn.AssignmentID)        AS TotalRequired,
        COUNT(s.SubmissionID)           AS TotalSubmitted,
        SUM(CASE WHEN s.LockState IS NOT NULL AND s.LockState <> 'Unlocked'
                 THEN 1 ELSE 0 END)     AS TotalLocked,
        COUNT(asgn.AssignmentID)
            - COUNT(s.SubmissionID)     AS TotalMissing,
        CAST(
            CASE WHEN COUNT(asgn.AssignmentID) = 0 THEN 100.0
                 ELSE 100.0 * COUNT(s.SubmissionID)
                           / NULLIF(COUNT(asgn.AssignmentID), 0)
            END AS DECIMAL(5,1)
        )                               AS CompletionPct
    FROM KPI.Assignment     AS asgn
    JOIN KPI.Period          AS per  ON per.PeriodID   = asgn.PeriodID
    JOIN Dim.Account         AS acct ON acct.AccountId = asgn.AccountId
    LEFT JOIN KPI.Submission AS s    ON s.AssignmentID = asgn.AssignmentID
    WHERE asgn.IsActive  = 1
      AND asgn.IsRequired = 1
    GROUP BY
        acct.AccountId,
        acct.AccountCode,
        acct.AccountName,
        per.PeriodID,
        per.ExternalId,
        per.PeriodLabel,
        per.PeriodYear,
        per.PeriodMonth,
        per.Status,
        per.SubmissionCloseDate;
GO

CREATE OR ALTER VIEW Reporting.vw_PBIReminderState
AS
    SELECT
        rs.ReminderStateID,
        -- Site
        ou.OrgUnitId                AS SiteId,
        ou.OrgUnitCode              AS SiteCode,
        ou.OrgUnitName              AS SiteName,
        ou.AccountId,
        acct.AccountCode,
        acct.AccountName,
        -- Period
        per.PeriodID,
        per.ExternalId              AS PeriodKey,
        per.PeriodLabel,
        per.PeriodYear,
        per.PeriodMonth,
        -- Reminder state
        rs.CurrentLevel,
        rs.LastReminderSentAt,
        rs.NextReminderDueAt,
        rs.IsResolved,
        rs.ResolvedAt,
        -- Computed
        DATEDIFF(
            DAY,
            CAST(SYSUTCDATETIME() AS DATE),
            rs.NextReminderDueAt
        )                           AS DaysUntilNextReminder,
        CAST(
            CASE WHEN rs.IsResolved = 0
                  AND rs.NextReminderDueAt <= CAST(SYSUTCDATETIME() AS DATE)
                 THEN 1 ELSE 0 END
            AS BIT
        )                           AS IsOverdue
    FROM Workflow.ReminderState     AS rs
    JOIN Dim.OrgUnit                AS ou   ON ou.OrgUnitId  = rs.OrgUnitId
    JOIN Dim.Account                AS acct ON acct.AccountId = ou.AccountId
    JOIN KPI.Period                 AS per  ON per.PeriodID  = rs.PeriodID;
GO

PRINT 'Create.sql completed';
GO
