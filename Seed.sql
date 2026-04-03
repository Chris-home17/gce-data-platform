/*
    Seed.sql
    Populates sample data for centralized RBAC model. Safe to re-run.
*/
SET NOCOUNT ON;
GO

-- Seed accounts -------------------------------------------------------------------
DECLARE @AccountSeed TABLE
(
    AccountCode NVARCHAR(50) PRIMARY KEY,
    AccountName NVARCHAR(200)
);

INSERT INTO @AccountSeed (AccountCode, AccountName)
VALUES
    ('DHL',   'DHL Global Logistics'),
    ('UPS',   'UPS Worldwide'),
    ('FEDEX', 'FedEx Corporation'),
    ('AMZN',  'Amazon Global Operations'),
    ('ACME',  'ACME Industrial');

DECLARE @AccountProcess TABLE (AccountCode NVARCHAR(50) PRIMARY KEY, AccountName NVARCHAR(200));
INSERT INTO @AccountProcess SELECT AccountCode, AccountName FROM @AccountSeed;

DECLARE @AccountCode NVARCHAR(50);
DECLARE @AccountName NVARCHAR(200);
DECLARE @AccountId INT;

WHILE EXISTS (SELECT 1 FROM @AccountProcess)
BEGIN
    SELECT TOP (1)
        @AccountCode = AccountCode,
        @AccountName = AccountName
    FROM @AccountProcess
    ORDER BY AccountCode;

    EXEC App.UpsertAccount
        @AccountCode = @AccountCode,
        @AccountName = @AccountName,
        @IsActive = 1,
        @ApplyPolicies = 0,
        @AccountId = @AccountId OUTPUT;

    DELETE FROM @AccountProcess WHERE AccountCode = @AccountCode;
END;

-- Seed hierarchical org units -----------------------------------------------------
DECLARE @Divisions TABLE (DivisionCode NVARCHAR(50) PRIMARY KEY, DivisionName NVARCHAR(200));
INSERT INTO @Divisions (DivisionCode, DivisionName)
VALUES
    ('NA',    'North America'),
    ('EU',    'Europe'),
    ('APAC',  'Asia Pacific'),
    ('LATAM', 'Latin America'),
    ('MEA',   'Middle East & Africa');

DECLARE @Countries TABLE (
    DivisionCode NVARCHAR(50),
    CountryCode  NVARCHAR(10),
    CountryName  NVARCHAR(200),
    PRIMARY KEY (DivisionCode, CountryCode)
);
INSERT INTO @Countries (DivisionCode, CountryCode, CountryName)
VALUES
    ('NA',    'US', 'United States'),
    ('NA',    'CA', 'Canada'),
    ('EU',    'BE', 'Belgium'),
    ('EU',    'DE', 'Germany'),
    ('APAC',  'SG', 'Singapore'),
    ('APAC',  'AU', 'Australia'),
    ('LATAM', 'BR', 'Brazil'),
    ('LATAM', 'MX', 'Mexico'),
    ('MEA',   'AE', 'United Arab Emirates'),
    ('MEA',   'ZA', 'South Africa');

DECLARE @SiteSuffix TABLE (Suffix NVARCHAR(2), SiteLabel NVARCHAR(50));
INSERT INTO @SiteSuffix (Suffix, SiteLabel)
VALUES ('01', 'Site 01'), ('02', 'Site 02');

DECLARE @SeedSites TABLE
(
    RowId INT IDENTITY(1,1) PRIMARY KEY,
    AccountCode NVARCHAR(50),
    DivisionCode NVARCHAR(50),
    DivisionName NVARCHAR(200),
    CountryCode NVARCHAR(10),
    CountryName NVARCHAR(200),
    SiteCode NVARCHAR(50),
    SiteName NVARCHAR(200)
);

INSERT INTO @SeedSites (AccountCode, DivisionCode, DivisionName, CountryCode, CountryName, SiteCode, SiteName)
SELECT
    a.AccountCode,
    d.DivisionCode,
    d.DivisionName,
    c.CountryCode,
    c.CountryName,
    CONCAT(c.CountryCode, '-', s.Suffix) AS SiteCode,
    CONCAT(a.AccountCode, ' ', c.CountryName, ' ', s.SiteLabel) AS SiteName
FROM @AccountSeed AS a
CROSS JOIN @Divisions AS d
JOIN @Countries AS c
    ON c.DivisionCode = d.DivisionCode
CROSS JOIN @SiteSuffix AS s;

DECLARE @DivisionCode NVARCHAR(50);
DECLARE @DivisionName NVARCHAR(200);
DECLARE @CountryCode NVARCHAR(10);
DECLARE @CountryName NVARCHAR(200);
DECLARE @SiteCode NVARCHAR(50);
DECLARE @SiteName NVARCHAR(200);
DECLARE @SiteOrgUnitId INT;
DECLARE @SiteRowId INT;

WHILE EXISTS (SELECT 1 FROM @SeedSites)
BEGIN
    SELECT TOP (1)
        @SiteRowId = RowId,
        @AccountCode = AccountCode,
        @DivisionCode = DivisionCode,
        @DivisionName = DivisionName,
        @CountryCode = CountryCode,
        @CountryName = CountryName,
        @SiteCode = SiteCode,
        @SiteName = SiteName
    FROM @SeedSites
    ORDER BY RowId;

    EXEC App.CreateOrEnsureSitePath
        @AccountCode = @AccountCode,
        @DivisionCode = @DivisionCode,
        @DivisionName = @DivisionName,
        @CountryCode = @CountryCode,
        @CountryName = @CountryName,
        @SiteCode = @SiteCode,
        @SiteName = @SiteName,
        @SiteOrgUnitId = @SiteOrgUnitId OUTPUT;

    DELETE FROM @SeedSites WHERE RowId = @SiteRowId;
END;

-- Seed packages -------------------------------------------------------------------
DECLARE @Now DATETIME2 = SYSUTCDATETIME();

IF EXISTS (SELECT 1 FROM Dim.Package WHERE PackageCode = 'GUARD')
    UPDATE Dim.Package SET PackageName = 'Guarding Suite', PackageGroup = 'Operations', IsActive = 1, ModifiedOnUtc = @Now WHERE PackageCode = 'GUARD';
ELSE
    INSERT INTO Dim.Package (PackageCode, PackageName, PackageGroup) VALUES ('GUARD', 'Guarding Suite', 'Operations');

IF EXISTS (SELECT 1 FROM Dim.Package WHERE PackageCode = 'FIN')
    UPDATE Dim.Package SET PackageName = 'Financial Insights', PackageGroup = 'Finance', IsActive = 1, ModifiedOnUtc = @Now WHERE PackageCode = 'FIN';
ELSE
    INSERT INTO Dim.Package (PackageCode, PackageName, PackageGroup) VALUES ('FIN', 'Financial Insights', 'Finance');

IF EXISTS (SELECT 1 FROM Dim.Package WHERE PackageCode = 'KPI')
    UPDATE Dim.Package SET PackageName = 'Executive KPIs', PackageGroup = 'Executive', IsActive = 1, ModifiedOnUtc = @Now WHERE PackageCode = 'KPI';
ELSE
    INSERT INTO Dim.Package (PackageCode, PackageName, PackageGroup) VALUES ('KPI', 'Executive KPIs', 'Executive');

IF EXISTS (SELECT 1 FROM Dim.Package WHERE PackageCode = 'SOC')
    UPDATE Dim.Package SET PackageName = 'Security Operations Center', PackageGroup = 'Security', IsActive = 1, ModifiedOnUtc = @Now WHERE PackageCode = 'SOC';
ELSE
    INSERT INTO Dim.Package (PackageCode, PackageName, PackageGroup) VALUES ('SOC', 'Security Operations Center', 'Security');

-- Seed BI reports -----------------------------------------------------------------
DECLARE @ReportSeed TABLE
(
    ReportCode NVARCHAR(100) PRIMARY KEY,
    ReportName NVARCHAR(200),
    ReportUri  NVARCHAR(500)
);

INSERT INTO @ReportSeed (ReportCode, ReportName, ReportUri)
VALUES
    ('FIN-PNL',  'Global Profit & Loss',           'powerbi://contoso/reports/FIN-PNL'),
    ('FIN-SALES','Revenue Performance Dashboard',  'powerbi://contoso/reports/FIN-SALES'),
    ('SOC-INC',  'Incident Response Overview',     'powerbi://contoso/reports/SOC-INC'),
    ('KPI-EXEC', 'Executive KPI Scorecard',        'powerbi://contoso/reports/KPI-EXEC'),
    ('GUARD-COM','Guarding Compliance Tracker',    'powerbi://contoso/reports/GUARD-COM');

DECLARE @ReportCode NVARCHAR(100);
DECLARE @ReportName NVARCHAR(200);
DECLARE @ReportUri NVARCHAR(500);
DECLARE @BiReportId INT;

DECLARE @ReportProcess TABLE (ReportCode NVARCHAR(100) PRIMARY KEY, ReportName NVARCHAR(200), ReportUri NVARCHAR(500));
INSERT INTO @ReportProcess SELECT ReportCode, ReportName, ReportUri FROM @ReportSeed;

WHILE EXISTS (SELECT 1 FROM @ReportProcess)
BEGIN
    SELECT TOP (1)
        @ReportCode = ReportCode,
        @ReportName = ReportName,
        @ReportUri = ReportUri
    FROM @ReportProcess
    ORDER BY ReportCode;

    SELECT @BiReportId = BiReportId FROM Dim.BiReport WHERE ReportCode = @ReportCode;

    IF @BiReportId IS NULL
    BEGIN
        INSERT INTO Dim.BiReport (ReportCode, ReportName, ReportUri)
        VALUES (@ReportCode, @ReportName, @ReportUri);
        SET @BiReportId = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE Dim.BiReport
        SET ReportName = @ReportName,
            ReportUri = @ReportUri,
            ModifiedOnUtc = @Now,
            IsActive = 1
        WHERE BiReportId = @BiReportId;
    END

    DELETE FROM @ReportProcess WHERE ReportCode = @ReportCode;
END;

-- Map reports to packages ---------------------------------------------------------
DECLARE @ReportPackage TABLE (ReportCode NVARCHAR(100), PackageCode NVARCHAR(50));
INSERT INTO @ReportPackage (ReportCode, PackageCode)
VALUES
    ('FIN-PNL',  'FIN'),
    ('FIN-SALES','FIN'),
    ('KPI-EXEC', 'KPI'),
    ('KPI-EXEC', 'FIN'),
    ('SOC-INC',  'SOC'),
    ('GUARD-COM','GUARD');

DECLARE @MapReportCode NVARCHAR(100);
DECLARE @MapPackageCode NVARCHAR(50);
DECLARE @MapReportId INT;
DECLARE @MapPackageId INT;

DECLARE @MapCursor TABLE (Id INT IDENTITY(1,1) PRIMARY KEY, ReportCode NVARCHAR(100), PackageCode NVARCHAR(50));
INSERT INTO @MapCursor (ReportCode, PackageCode) SELECT ReportCode, PackageCode FROM @ReportPackage;

DECLARE @MapId INT;

WHILE EXISTS (SELECT 1 FROM @MapCursor)
BEGIN
    SELECT TOP (1)
        @MapId = Id,
        @MapReportCode = ReportCode,
        @MapPackageCode = PackageCode
    FROM @MapCursor
    ORDER BY Id;

    SELECT @MapReportId = BiReportId FROM Dim.BiReport WHERE ReportCode = @MapReportCode;
    SELECT @MapPackageId = PackageId FROM Dim.Package WHERE PackageCode = @MapPackageCode;

    IF @MapReportId IS NOT NULL AND @MapPackageId IS NOT NULL
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM Dim.BiReportPackage WHERE BiReportId = @MapReportId AND PackageId = @MapPackageId
        )
        BEGIN
            INSERT INTO Dim.BiReportPackage (BiReportId, PackageId)
            VALUES (@MapReportId, @MapPackageId);
        END
    END

    DELETE FROM @MapCursor WHERE Id = @MapId;
END;

-- Seed roles ----------------------------------------------------------------------
DECLARE @RoleSeed TABLE (RoleCode NVARCHAR(100) PRIMARY KEY, RoleName NVARCHAR(200), RoleDescription NVARCHAR(400));
INSERT INTO @RoleSeed (RoleCode, RoleName, RoleDescription)
VALUES
    ('GLOBAL_EXECUTIVE',    'Global Executives',          'Full visibility to all packages and accounts.'),
    ('SOC_GLOBAL',          'SOC Global Administrators',  'SOC package access across every account.'),
    ('FIN_DHL_EU',          'DHL Europe Finance',         'Finance package scoped to DHL Europe division.'),
    ('FIN_UPS_LATAM',       'UPS LATAM Finance',          'Finance package scoped to UPS LATAM division.'),
    ('COUNTRY_MANAGER_BE',  'Belgium Country Managers',   'Country-level coverage for Belgium across accounts.');

DECLARE @RoleCode NVARCHAR(100);
DECLARE @RoleName NVARCHAR(200);
DECLARE @RoleDescription NVARCHAR(400);
DECLARE @RoleId INT;

DECLARE @RoleProcess TABLE (RoleCode NVARCHAR(100) PRIMARY KEY, RoleName NVARCHAR(200), RoleDescription NVARCHAR(400));
INSERT INTO @RoleProcess SELECT RoleCode, RoleName, RoleDescription FROM @RoleSeed;

WHILE EXISTS (SELECT 1 FROM @RoleProcess)
BEGIN
    SELECT TOP (1)
        @RoleCode = RoleCode,
        @RoleName = RoleName,
        @RoleDescription = RoleDescription
    FROM @RoleProcess
    ORDER BY RoleCode;

    EXEC App.UpsertRole
        @RoleCode = @RoleCode,
        @RoleName = @RoleName,
        @Description = @RoleDescription,
        @RoleId = @RoleId OUTPUT;

    DELETE FROM @RoleProcess WHERE RoleCode = @RoleCode;
END;

-- Seed users ----------------------------------------------------------------------
DECLARE @UserSeed TABLE (Id INT IDENTITY(1,1) PRIMARY KEY, UPN NVARCHAR(320), DisplayName NVARCHAR(200));
INSERT INTO @UserSeed (UPN, DisplayName)
VALUES
    ('allison.tate@fabrikam.com',  'Allison Tate'),
    ('hassan.khan@fabrikam.com',   'Hassan Khan'),
    ('bruno.martens@fabrikam.com', 'Bruno Martens'),
    ('carla.gomez@fabrikam.com',   'Carla Gomez'),
    ('felix.mercier@fabrikam.com', 'Felix Mercier'),
    ('ines.silva@fabrikam.com',    'Ines Silva'),
    ('marco.rios@fabrikam.com',    'Marco Rios'),
    ('li.na@fabrikam.com',         'Li Na'),
    ('priya.bose@fabrikam.com',    'Priya Bose'),
    ('john.doe@fabrikam.com',      'John Doe'),
    ('karla.nygaard@fabrikam.com', 'Karla Nygaard'),
    ('nina.stevens@fabrikam.com',  'Nina Stevens'),
    ('oliver.brink@fabrikam.com',  'Oliver Brink'),
    ('quinn.hughes@fabrikam.com',  'Quinn Hughes'),
    ('ravi.patel@fabrikam.com',    'Ravi Patel'),
    ('sofia.fernandez@fabrikam.com','Sofia Fernandez'),
    ('tomoko.sato@fabrikam.com',   'Tomoko Sato'),
    ('uma.bala@fabrikam.com',      'Uma Bala'),
    ('victor.lee@fabrikam.com',    'Victor Lee');

DECLARE @SeedRowId INT;
DECLARE @UserUPN NVARCHAR(320);
DECLARE @UserDisplayName NVARCHAR(200);
DECLARE @UserId INT;

WHILE EXISTS (SELECT 1 FROM @UserSeed)
BEGIN
    SELECT TOP (1)
        @SeedRowId = Id,
        @UserUPN = UPN,
        @UserDisplayName = DisplayName
    FROM @UserSeed
    ORDER BY Id;

    EXEC App.UpsertUser
        @UPN = @UserUPN,
        @DisplayName = @UserDisplayName,
        @UserId = @UserId OUTPUT;

    DELETE FROM @UserSeed WHERE Id = @SeedRowId;
END;

-- Role memberships ----------------------------------------------------------------
DECLARE @RoleMemberSeed TABLE (RoleCode NVARCHAR(100), MemberUPN NVARCHAR(320));
INSERT INTO @RoleMemberSeed (RoleCode, MemberUPN)
VALUES
    ('GLOBAL_EXECUTIVE',   'allison.tate@fabrikam.com'),
    ('GLOBAL_EXECUTIVE',   'nina.stevens@fabrikam.com'),
    ('SOC_GLOBAL',         'hassan.khan@fabrikam.com'),
    ('FIN_DHL_EU',         'bruno.martens@fabrikam.com'),
    ('FIN_UPS_LATAM',      'carla.gomez@fabrikam.com'),
    ('COUNTRY_MANAGER_BE', 'felix.mercier@fabrikam.com');

DECLARE @RoleMemberRowId INT;
DECLARE @RoleMemberRoleCode NVARCHAR(100);
DECLARE @RoleMemberUPN NVARCHAR(320);

DECLARE @RoleMemberCursor TABLE (Id INT IDENTITY(1,1) PRIMARY KEY, RoleCode NVARCHAR(100), MemberUPN NVARCHAR(320));
INSERT INTO @RoleMemberCursor (RoleCode, MemberUPN)
SELECT RoleCode, MemberUPN FROM @RoleMemberSeed;

DECLARE @MemberRoleId INT;
DECLARE @MemberPrincipalId INT;

WHILE EXISTS (SELECT 1 FROM @RoleMemberCursor)
BEGIN
    SELECT TOP (1)
        @RoleMemberRowId = Id,
        @RoleMemberRoleCode = RoleCode,
        @RoleMemberUPN = MemberUPN
    FROM @RoleMemberCursor
    ORDER BY Id;

    SELECT @MemberRoleId = RoleId FROM Sec.Role WHERE RoleCode = @RoleMemberRoleCode;
    SELECT @MemberPrincipalId = UserId FROM Sec.[User] WHERE UPN = @RoleMemberUPN;

    IF @MemberRoleId IS NOT NULL AND @MemberPrincipalId IS NOT NULL
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM Sec.RoleMembership WHERE RoleId = @MemberRoleId AND MemberPrincipalId = @MemberPrincipalId
        )
        BEGIN
            INSERT INTO Sec.RoleMembership (RoleId, MemberPrincipalId)
            VALUES (@MemberRoleId, @MemberPrincipalId);
        END
    END

    DELETE FROM @RoleMemberCursor WHERE Id = @RoleMemberRowId;
END;

-- Seed reusable access and package policies --------------------------------------
DECLARE @PolicyPrincipalId INT;

SELECT @PolicyPrincipalId = RoleId FROM Sec.Role WHERE RoleCode = 'SOC_GLOBAL';
IF @PolicyPrincipalId IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Sec.AccountAccessPolicy WHERE PolicyName = 'SOC Global Full Account')
        INSERT INTO Sec.AccountAccessPolicy (PolicyName, PrincipalId, ScopeType)
        VALUES ('SOC Global Full Account', @PolicyPrincipalId, 'NONE');

    IF NOT EXISTS (SELECT 1 FROM Sec.AccountPackagePolicy WHERE PolicyName = 'SOC Global SOC Package')
        INSERT INTO Sec.AccountPackagePolicy (PolicyName, PrincipalId, GrantScope, PackageCode)
        VALUES ('SOC Global SOC Package', @PolicyPrincipalId, 'PACKAGE', 'SOC');
END;

SELECT @PolicyPrincipalId = RoleId FROM Sec.Role WHERE RoleCode = 'GLOBAL_EXECUTIVE';
IF @PolicyPrincipalId IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Sec.AccountPackagePolicy WHERE PolicyName = 'Global Executives All Packages')
        INSERT INTO Sec.AccountPackagePolicy (PolicyName, PrincipalId, GrantScope)
        VALUES ('Global Executives All Packages', @PolicyPrincipalId, 'ALL_PACKAGES');
END;

SELECT @PolicyPrincipalId = RoleId FROM Sec.Role WHERE RoleCode = 'COUNTRY_MANAGER_BE';
IF @PolicyPrincipalId IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Sec.AccountAccessPolicy WHERE PolicyName = 'BE Country Managers Country Scope')
        INSERT INTO Sec.AccountAccessPolicy (PolicyName, PrincipalId, ScopeType, OrgUnitType, OrgUnitCode)
        VALUES ('BE Country Managers Country Scope', @PolicyPrincipalId, 'ORGUNIT', 'Country', 'BE');

    IF NOT EXISTS (SELECT 1 FROM Sec.AccountPackagePolicy WHERE PolicyName = 'BE Country Managers KPI Package')
        INSERT INTO Sec.AccountPackagePolicy (PolicyName, PrincipalId, GrantScope, PackageCode)
        VALUES ('BE Country Managers KPI Package', @PolicyPrincipalId, 'PACKAGE', 'KPI');
END;

-- Grants applied to roles ---------------------------------------------------------
EXEC Sec.GrantGlobalAllPackages @PrincipalType = 'Role', @PrincipalIdentifier = 'GLOBAL_EXECUTIVE';
EXEC Sec.GrantAllAccounts @PrincipalType = 'Role', @PrincipalIdentifier = 'GLOBAL_EXECUTIVE';

DECLARE @AccountCursor TABLE (Id INT IDENTITY(1,1) PRIMARY KEY, AccountCode NVARCHAR(50));
INSERT INTO @AccountCursor (AccountCode)
SELECT AccountCode FROM Dim.Account;

DECLARE @AccountRowId INT;

WHILE EXISTS (SELECT 1 FROM @AccountCursor)
BEGIN
    SELECT TOP (1) @AccountRowId = Id, @AccountCode = AccountCode FROM @AccountCursor ORDER BY Id;

    EXEC App.ApplyAccountPolicies
        @AccountCode   = @AccountCode,
        @ApplyAccess   = 1,
        @ApplyPackages = 1;

    DELETE FROM @AccountCursor WHERE Id = @AccountRowId;
END;

EXEC Sec.GrantGlobal @PrincipalType = 'Role', @PrincipalIdentifier = 'SOC_GLOBAL', @PackageCode = 'SOC';
EXEC Sec.GrantGlobal @PrincipalType = 'Role', @PrincipalIdentifier = 'FIN_DHL_EU', @PackageCode = 'FIN';
EXEC Sec.GrantGlobal @PrincipalType = 'Role', @PrincipalIdentifier = 'FIN_UPS_LATAM', @PackageCode = 'FIN';
EXEC Sec.GrantGlobal @PrincipalType = 'Role', @PrincipalIdentifier = 'COUNTRY_MANAGER_BE', @PackageCode = 'KPI';

EXEC Sec.GrantPathPrefix @PrincipalType = 'Role', @PrincipalIdentifier = 'FIN_DHL_EU', @AccountCode = 'DHL', @OrgUnitType = 'Division', @OrgUnitCode = 'EU';
EXEC Sec.GrantPathPrefix @PrincipalType = 'Role', @PrincipalIdentifier = 'FIN_UPS_LATAM', @AccountCode = 'UPS', @OrgUnitType = 'Division', @OrgUnitCode = 'LATAM';
EXEC Sec.GrantCountryAllAccounts @PrincipalType = 'Role', @PrincipalIdentifier = 'COUNTRY_MANAGER_BE', @CountryCode = 'BE';

EXEC Sec.GrantDelegation
    @DelegatorPrincipalType = 'Role',
    @DelegatorIdentifier    = 'SOC_GLOBAL',
    @DelegatePrincipalType  = 'User',
    @DelegateIdentifier     = 'hassan.khan@fabrikam.com',
    @AccessType             = 'ACCOUNT',
    @AccountCode            = 'DHL',
    @ScopeType              = 'NONE';

EXEC Sec.GrantDelegation
    @DelegatorPrincipalType = 'Role',
    @DelegatorIdentifier    = 'FIN_DHL_EU',
    @DelegatePrincipalType  = 'User',
    @DelegateIdentifier     = 'bruno.martens@fabrikam.com',
    @AccessType             = 'ACCOUNT',
    @AccountCode            = 'DHL',
    @ScopeType              = 'ORGUNIT',
    @OrgUnitType            = 'Division',
    @OrgUnitCode            = 'EU';

-- Direct grants applied to users --------------------------------------------------
EXEC Sec.GrantGlobalAllPackages @PrincipalType = 'User', @PrincipalIdentifier = 'allison.tate@fabrikam.com';
EXEC Sec.GrantGlobal @PrincipalType = 'User', @PrincipalIdentifier = 'nina.stevens@fabrikam.com', @PackageCode = 'KPI';
EXEC Sec.GrantGlobal @PrincipalType = 'User', @PrincipalIdentifier = 'victor.lee@fabrikam.com', @PackageCode = 'GUARD';
EXEC Sec.GrantGlobal @PrincipalType = 'User', @PrincipalIdentifier = 'li.na@fabrikam.com', @PackageCode = 'KPI';
EXEC Sec.GrantGlobal @PrincipalType = 'User', @PrincipalIdentifier = 'marco.rios@fabrikam.com', @PackageCode = 'FIN';
EXEC Sec.GrantGlobal @PrincipalType = 'User', @PrincipalIdentifier = 'priya.bose@fabrikam.com', @PackageCode = 'SOC';
EXEC Sec.GrantGlobal @PrincipalType = 'User', @PrincipalIdentifier = 'john.doe@fabrikam.com', @PackageCode = 'SOC';
EXEC Sec.GrantGlobal @PrincipalType = 'User', @PrincipalIdentifier = 'karla.nygaard@fabrikam.com', @PackageCode = 'GUARD';
EXEC Sec.GrantGlobal @PrincipalType = 'User', @PrincipalIdentifier = 'ines.silva@fabrikam.com', @PackageCode = 'FIN';
EXEC Sec.GrantGlobal @PrincipalType = 'User', @PrincipalIdentifier = 'sofia.fernandez@fabrikam.com', @PackageCode = 'SOC';
EXEC Sec.GrantGlobal @PrincipalType = 'User', @PrincipalIdentifier = 'tomoko.sato@fabrikam.com', @PackageCode = 'KPI';
EXEC Sec.GrantGlobal @PrincipalType = 'User', @PrincipalIdentifier = 'uma.bala@fabrikam.com', @PackageCode = 'GUARD';
EXEC Sec.GrantGlobal @PrincipalType = 'User', @PrincipalIdentifier = 'quinn.hughes@fabrikam.com', @PackageCode = 'GUARD';
EXEC Sec.GrantGlobal @PrincipalType = 'User', @PrincipalIdentifier = 'ravi.patel@fabrikam.com', @PackageCode = 'KPI';
EXEC Sec.GrantGlobal @PrincipalType = 'User', @PrincipalIdentifier = 'oliver.brink@fabrikam.com', @PackageCode = 'GUARD';

EXEC Sec.GrantFullAccount @PrincipalType = 'User', @PrincipalIdentifier = 'marco.rios@fabrikam.com', @AccountCode = 'FEDEX';
EXEC Sec.GrantFullAccount @PrincipalType = 'User', @PrincipalIdentifier = 'victor.lee@fabrikam.com', @AccountCode = 'ACME';
EXEC Sec.GrantFullAccount @PrincipalType = 'User', @PrincipalIdentifier = 'uma.bala@fabrikam.com', @AccountCode = 'DHL';

EXEC Sec.GrantPathPrefix @PrincipalType = 'User', @PrincipalIdentifier = 'li.na@fabrikam.com', @AccountCode = 'FEDEX', @OrgUnitType = 'Division', @OrgUnitCode = 'APAC';
EXEC Sec.GrantPathPrefix @PrincipalType = 'User', @PrincipalIdentifier = 'ines.silva@fabrikam.com', @AccountCode = 'UPS', @OrgUnitType = 'Country', @OrgUnitCode = 'BR';
EXEC Sec.GrantPathPrefix @PrincipalType = 'User', @PrincipalIdentifier = 'quinn.hughes@fabrikam.com', @AccountCode = 'FEDEX', @OrgUnitType = 'Division', @OrgUnitCode = 'EU';
EXEC Sec.GrantPathPrefix @PrincipalType = 'User', @PrincipalIdentifier = 'priya.bose@fabrikam.com', @AccountCode = 'AMZN', @OrgUnitType = 'Country', @OrgUnitCode = 'SG';
EXEC Sec.GrantPathPrefix @PrincipalType = 'User', @PrincipalIdentifier = 'john.doe@fabrikam.com', @AccountCode = 'DHL', @OrgUnitType = 'Site', @OrgUnitCode = 'US-01';
EXEC Sec.GrantPathPrefix @PrincipalType = 'User', @PrincipalIdentifier = 'karla.nygaard@fabrikam.com', @AccountCode = 'DHL', @OrgUnitType = 'Site', @OrgUnitCode = 'US-02';
EXEC Sec.GrantPathPrefix @PrincipalType = 'User', @PrincipalIdentifier = 'oliver.brink@fabrikam.com', @AccountCode = 'ACME', @OrgUnitType = 'Site', @OrgUnitCode = 'BE-01';
EXEC Sec.GrantPathPrefix @PrincipalType = 'User', @PrincipalIdentifier = 'sofia.fernandez@fabrikam.com', @AccountCode = 'UPS', @OrgUnitType = 'Site', @OrgUnitCode = 'MX-02';
EXEC Sec.GrantPathPrefix @PrincipalType = 'User', @PrincipalIdentifier = 'tomoko.sato@fabrikam.com', @AccountCode = 'FEDEX', @OrgUnitType = 'Country', @OrgUnitCode = 'AU';

EXEC Sec.GrantCountryAllAccounts @PrincipalType = 'User', @PrincipalIdentifier = 'felix.mercier@fabrikam.com', @CountryCode = 'BE';
EXEC Sec.GrantCountryAllAccounts @PrincipalType = 'User', @PrincipalIdentifier = 'ravi.patel@fabrikam.com', @CountryCode = 'SG';
EXEC Sec.GrantCountryAllAccounts @PrincipalType = 'User', @PrincipalIdentifier = 'tomoko.sato@fabrikam.com', @CountryCode = 'AU';

PRINT 'Seed.sql completed';
