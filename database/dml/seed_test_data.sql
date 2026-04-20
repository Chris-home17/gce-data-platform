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

-- Seed branding for one account (DHL) -------------------------------------------
UPDATE Dim.Account
SET PrimaryColor   = '#D40511',
    PrimaryColor2  = '#B8040E',
    SecondaryColor = '#FFCC00',
    AccentColor    = '#D40511'
WHERE AccountCode = 'DHL';

-- Seed shared geography repository -----------------------------------------------
DECLARE @SharedGeoSeed TABLE
(
    RowId           INT IDENTITY(1,1) PRIMARY KEY,
    GeoUnitType     NVARCHAR(20),
    GeoUnitCode     NVARCHAR(50),
    GeoUnitName     NVARCHAR(200),
    CountryCode     NVARCHAR(10) NULL
);

INSERT INTO @SharedGeoSeed
    (GeoUnitType, GeoUnitCode, GeoUnitName, CountryCode)
VALUES
    ('Region',    'AMER',    'Americas',                             NULL),
    ('Region',    'EMEA',    'Europe, Middle East & Africa',         NULL),
    ('Region',    'APAC',    'Asia Pacific',                         NULL),
    ('Region',    'LATAM',   'Latin America',                        NULL),
    ('SubRegion', 'NORA',    'North America',                        NULL),
    ('SubRegion', 'WEU',     'Western Europe',                       NULL),
    ('SubRegion', 'MEA',     'Middle East & Africa',                 NULL),
    ('SubRegion', 'ANZSEA',  'Australia and Southeast Asia',         NULL),
    ('SubRegion', 'NOLA',    'Northern Latin America',               NULL),
    ('SubRegion', 'SOLA',    'Southern Latin America',               NULL),
    ('Cluster',   'BENELUX', 'Benelux',                              NULL),
    ('Cluster',   'DACH',    'DACH',                                 NULL),
    ('Cluster',   'GCC',     'Gulf Cooperation Council',             NULL),
    ('Cluster',   'SEA',     'Southeast Asia',                       NULL),
    ('Country',   'US',      'United States',                        'US'),
    ('Country',   'CA',      'Canada',                               'CA'),
    ('Country',   'BE',      'Belgium',                              'BE'),
    ('Country',   'DE',      'Germany',                              'DE'),
    ('Country',   'SG',      'Singapore',                            'SG'),
    ('Country',   'AU',      'Australia',                            'AU'),
    ('Country',   'BR',      'Brazil',                               'BR'),
    ('Country',   'MX',      'Mexico',                               'MX'),
    ('Country',   'AE',      'United Arab Emirates',                 'AE'),
    ('Country',   'ZA',      'South Africa',                         'ZA');

DECLARE @SharedGeoRowId INT;
DECLARE @GeoUnitType NVARCHAR(20);
DECLARE @GeoUnitCode NVARCHAR(50);
DECLARE @GeoUnitName NVARCHAR(200);
DECLARE @SharedCountryCode NVARCHAR(10);
DECLARE @SharedGeoUnitId INT;

WHILE EXISTS (SELECT 1 FROM @SharedGeoSeed)
BEGIN
    SELECT TOP (1)
        @SharedGeoRowId = RowId,
        @GeoUnitType = GeoUnitType,
        @GeoUnitCode = GeoUnitCode,
        @GeoUnitName = GeoUnitName,
        @SharedCountryCode = CountryCode
    FROM @SharedGeoSeed
    ORDER BY RowId;

    EXEC App.UpsertSharedGeoUnit
        @GeoUnitType = @GeoUnitType,
        @GeoUnitCode = @GeoUnitCode,
        @GeoUnitName = @GeoUnitName,
        @CountryCode = @SharedCountryCode,
        @SharedGeoUnitId = @SharedGeoUnitId OUTPUT;

    DELETE FROM @SharedGeoSeed WHERE RowId = @SharedGeoRowId;
END;

DECLARE @SiteSuffix TABLE (Suffix NVARCHAR(2), SiteLabel NVARCHAR(50));
INSERT INTO @SiteSuffix (Suffix, SiteLabel)
VALUES ('01', 'Site 01'), ('02', 'Site 02');

DECLARE @SeedSites TABLE
(
    RowId INT IDENTITY(1,1) PRIMARY KEY,
    AccountCode NVARCHAR(50),
    RegionCode NVARCHAR(50),
    SubRegionCode NVARCHAR(50) NULL,
    ClusterCode NVARCHAR(50) NULL,
    CountryCode NVARCHAR(10),
    SiteCode NVARCHAR(50),
    SiteName NVARCHAR(200)
);

DECLARE @CountrySeed TABLE
(
    AccountCode NVARCHAR(50),
    RegionCode NVARCHAR(50),
    SubRegionCode NVARCHAR(50) NULL,
    ClusterCode NVARCHAR(50) NULL,
    CountryCode NVARCHAR(10),
    CountryName NVARCHAR(200),
    PRIMARY KEY (AccountCode, CountryCode)
);

INSERT INTO @CountrySeed (AccountCode, RegionCode, SubRegionCode, ClusterCode, CountryCode, CountryName)
VALUES
    ('DHL',   'AMER',  'NORA',   NULL,      'US', 'United States'),
    ('DHL',   'AMER',  NULL,     NULL,      'CA', 'Canada'),
    ('DHL',   'EMEA',  'WEU',    'BENELUX', 'BE', 'Belgium'),
    ('DHL',   'EMEA',  'WEU',    'DACH',    'DE', 'Germany'),
    ('DHL',   'APAC',  'ANZSEA', 'SEA',     'SG', 'Singapore'),
    ('DHL',   'APAC',  NULL,     NULL,      'AU', 'Australia'),
    ('UPS',   'EMEA',  'WEU',    NULL,      'BE', 'Belgium'),
    ('UPS',   'LATAM', 'NOLA',   NULL,      'MX', 'Mexico'),
    ('UPS',   'LATAM', NULL,     NULL,      'BR', 'Brazil'),
    ('UPS',   'APAC',  NULL,     'SEA',     'SG', 'Singapore'),
    ('UPS',   'APAC',  'ANZSEA', NULL,      'AU', 'Australia'),
    ('FEDEX', 'EMEA',  'WEU',    'BENELUX', 'BE', 'Belgium'),
    ('FEDEX', 'APAC',  NULL,     NULL,      'AU', 'Australia'),
    ('FEDEX', 'APAC',  'ANZSEA', 'SEA',     'SG', 'Singapore'),
    ('FEDEX', 'EMEA',  NULL,     NULL,      'DE', 'Germany'),
    ('AMZN',  'EMEA',  NULL,     NULL,      'BE', 'Belgium'),
    ('AMZN',  'APAC',  NULL,     NULL,      'SG', 'Singapore'),
    ('AMZN',  'APAC',  'ANZSEA', NULL,      'AU', 'Australia'),
    ('AMZN',  'EMEA',  'MEA',    NULL,      'ZA', 'South Africa'),
    ('AMZN',  'AMER',  'NORA',   NULL,      'US', 'United States'),
    ('ACME',  'EMEA',  NULL,     NULL,      'BE', 'Belgium'),
    ('ACME',  'EMEA',  'MEA',    'GCC',     'AE', 'United Arab Emirates'),
    ('ACME',  'LATAM', 'NOLA',   NULL,      'MX', 'Mexico'),
    ('ACME',  'APAC',  'ANZSEA', 'SEA',     'SG', 'Singapore'),
    ('ACME',  'APAC',  NULL,     NULL,      'AU', 'Australia');

INSERT INTO @SeedSites (AccountCode, RegionCode, SubRegionCode, ClusterCode, CountryCode, SiteCode, SiteName)
SELECT
    c.AccountCode,
    c.RegionCode,
    c.SubRegionCode,
    c.ClusterCode,
    c.CountryCode,
    CONCAT(c.CountryCode, '-', s.Suffix) AS SiteCode,
    CONCAT(c.AccountCode, ' ', c.CountryName, ' ', s.SiteLabel) AS SiteName
FROM @CountrySeed AS c
CROSS JOIN @SiteSuffix AS s;

DECLARE @RegionCode NVARCHAR(50);
DECLARE @SubRegionCode NVARCHAR(50);
DECLARE @ClusterCode NVARCHAR(50);
DECLARE @CountryCode NVARCHAR(10);
DECLARE @SiteCode NVARCHAR(50);
DECLARE @SiteName NVARCHAR(200);
DECLARE @SiteOrgUnitId INT;
DECLARE @SiteRowId INT;

WHILE EXISTS (SELECT 1 FROM @SeedSites)
BEGIN
    SELECT TOP (1)
        @SiteRowId = RowId,
        @AccountCode = AccountCode,
        @RegionCode = RegionCode,
        @SubRegionCode = SubRegionCode,
        @ClusterCode = ClusterCode,
        @CountryCode = CountryCode,
        @SiteCode = SiteCode,
        @SiteName = SiteName
    FROM @SeedSites
    ORDER BY RowId;

    EXEC App.CreateOrEnsureSitePath
        @AccountCode = @AccountCode,
        @RegionCode = @RegionCode,
        @SubRegionCode = @SubRegionCode,
        @ClusterCode = @ClusterCode,
        @CountryCode = @CountryCode,
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
    ('FIN_DHL_EU',          'DHL Europe Finance',         'Finance package scoped to DHL EMEA region.'),
    ('FIN_UPS_LATAM',       'UPS LATAM Finance',          'Finance package scoped to UPS LATAM region.'),
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
DECLARE @UserSeed TABLE
(
    Id INT IDENTITY(1,1) PRIMARY KEY,
    UPN NVARCHAR(320),
    DisplayName NVARCHAR(200),
    EntraObjectId NVARCHAR(128),
    UserType NVARCHAR(20),
    IsActive BIT,
    InvitedBy NVARCHAR(128),
    InviteDaysAgo INT NULL,
    LastLoginDaysAgo INT NULL
);

INSERT INTO @UserSeed
    (UPN, DisplayName, EntraObjectId, UserType, IsActive, InvitedBy, InviteDaysAgo, LastLoginDaysAgo)
VALUES
    ('dev@gce-platform.local',     'Dev User',        '00000000-0000-0000-0000-000000000001', 'Internal', 1, NULL,                              NULL,  0),
    ('allison.tate@fabrikam.com',  'Allison Tate',   '11111111-1111-1111-1111-111111111101', 'Internal', 1, NULL,                              NULL,  1),
    ('hassan.khan@fabrikam.com',   'Hassan Khan',    '11111111-1111-1111-1111-111111111102', 'Internal', 1, NULL,                              NULL,  2),
    ('bruno.martens@fabrikam.com', 'Bruno Martens',  '11111111-1111-1111-1111-111111111103', 'Internal', 1, NULL,                              NULL,  3),
    ('carla.gomez@fabrikam.com',   'Carla Gomez',    '22222222-2222-2222-2222-222222222201', 'External', 1, 'allison.tate@fabrikam.com',      45,   4),
    ('felix.mercier@fabrikam.com', 'Felix Mercier',  '22222222-2222-2222-2222-222222222202', 'External', 1, 'allison.tate@fabrikam.com',      40,   2),
    ('ines.silva@fabrikam.com',    'Ines Silva',     '22222222-2222-2222-2222-222222222203', 'External', 1, 'allison.tate@fabrikam.com',      38,   5),
    ('marco.rios@fabrikam.com',    'Marco Rios',     '22222222-2222-2222-2222-222222222204', 'External', 1, 'allison.tate@fabrikam.com',      35,   1),
    ('li.na@fabrikam.com',         'Li Na',          '22222222-2222-2222-2222-222222222205', 'External', 1, 'allison.tate@fabrikam.com',      32,   6),
    ('priya.bose@fabrikam.com',    'Priya Bose',     '22222222-2222-2222-2222-222222222206', 'External', 1, 'allison.tate@fabrikam.com',      30,   3),
    ('john.doe@fabrikam.com',      'John Doe',       '22222222-2222-2222-2222-222222222207', 'External', 0, 'allison.tate@fabrikam.com',      28,   NULL),
    ('karla.nygaard@fabrikam.com', 'Karla Nygaard',  '22222222-2222-2222-2222-222222222208', 'External', 1, 'allison.tate@fabrikam.com',      25,   7),
    ('nina.stevens@fabrikam.com',  'Nina Stevens',   '11111111-1111-1111-1111-111111111104', 'Internal', 1, NULL,                              NULL,  1),
    ('oliver.brink@fabrikam.com',  'Oliver Brink',   '22222222-2222-2222-2222-222222222209', 'External', 1, 'allison.tate@fabrikam.com',      21,   8),
    ('quinn.hughes@fabrikam.com',  'Quinn Hughes',   '22222222-2222-2222-2222-222222222210', 'External', 1, 'allison.tate@fabrikam.com',      18,   9),
    ('ravi.patel@fabrikam.com',    'Ravi Patel',     '22222222-2222-2222-2222-222222222211', 'External', 1, 'allison.tate@fabrikam.com',      16,   2),
    ('sofia.fernandez@fabrikam.com','Sofia Fernandez','22222222-2222-2222-2222-222222222212', 'External', 1, 'allison.tate@fabrikam.com',      14,   4),
    ('tomoko.sato@fabrikam.com',   'Tomoko Sato',    '22222222-2222-2222-2222-222222222213', 'External', 1, 'allison.tate@fabrikam.com',      12,   5),
    ('uma.bala@fabrikam.com',      'Uma Bala',       '22222222-2222-2222-2222-222222222214', 'External', 1, 'allison.tate@fabrikam.com',      10,   6),
    ('victor.lee@fabrikam.com',    'Victor Lee',     '22222222-2222-2222-2222-222222222215', 'External', 1, 'allison.tate@fabrikam.com',      8,    1);

DECLARE @UserProcess TABLE
(
    Id INT PRIMARY KEY,
    UPN NVARCHAR(320),
    DisplayName NVARCHAR(200),
    EntraObjectId NVARCHAR(128),
    UserType NVARCHAR(20),
    IsActive BIT,
    InvitedBy NVARCHAR(128)
);

INSERT INTO @UserProcess (Id, UPN, DisplayName, EntraObjectId, UserType, IsActive, InvitedBy)
SELECT Id, UPN, DisplayName, EntraObjectId, UserType, IsActive, InvitedBy
FROM @UserSeed;

DECLARE @SeedRowId INT;
DECLARE @UserUPN NVARCHAR(320);
DECLARE @UserDisplayName NVARCHAR(200);
DECLARE @UserEntraObjectId NVARCHAR(128);
DECLARE @UserType NVARCHAR(20);
DECLARE @UserIsActive BIT;
DECLARE @UserInvitedBy NVARCHAR(128);
DECLARE @UserId INT;

WHILE EXISTS (SELECT 1 FROM @UserProcess)
BEGIN
    SELECT TOP (1)
        @SeedRowId = Id,
        @UserUPN = UPN,
        @UserDisplayName = DisplayName,
        @UserEntraObjectId = EntraObjectId,
        @UserType = UserType,
        @UserIsActive = IsActive,
        @UserInvitedBy = InvitedBy
    FROM @UserProcess
    ORDER BY Id;

    EXEC App.UpsertUser
        @UPN = @UserUPN,
        @DisplayName = @UserDisplayName,
        @EntraObjectId = @UserEntraObjectId,
        @UserType = @UserType,
        @IsActive = @UserIsActive,
        @InvitedBy = @UserInvitedBy,
        @UserId = @UserId OUTPUT;

    DELETE FROM @UserProcess WHERE Id = @SeedRowId;
END;

UPDATE u
SET u.DisplayName   = us.DisplayName,
    u.EntraObjectId = us.EntraObjectId,
    u.UserType      = us.UserType,
    u.IsActive      = us.IsActive,
    u.InvitedBy     = us.InvitedBy,
    u.InvitedAt     = CASE
                        WHEN us.InviteDaysAgo IS NOT NULL THEN DATEADD(DAY, -us.InviteDaysAgo, @Now)
                        ELSE NULL
                      END,
    u.LastLoginAt   = CASE
                        WHEN us.LastLoginDaysAgo IS NOT NULL THEN DATEADD(DAY, -us.LastLoginDaysAgo, @Now)
                        ELSE NULL
                      END,
    u.ModifiedOnUtc = @Now,
    u.ModifiedBy    = 'seed_test_data'
FROM Sec.[User] AS u
JOIN @UserSeed AS us
    ON us.UPN = u.UPN;

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

-- Seed reusable account role policies --------------------------------------------
IF NOT EXISTS (
    SELECT 1
    FROM Sec.AccountRolePolicy
    WHERE RoleCodeTemplate = '{AccountCode}_OPS_LEAD'
      AND ScopeType = 'NONE'
)
BEGIN
    INSERT INTO Sec.AccountRolePolicy
        (PolicyName, RoleCodeTemplate, RoleNameTemplate, ScopeType, OrgUnitType, OrgUnitCode)
    VALUES
        ('Per-account Operations Lead Role',
         '{AccountCode}_OPS_LEAD',
         '{AccountName} Operations Lead',
         'NONE',
         NULL,
         NULL);
END;

IF NOT EXISTS (
    SELECT 1
    FROM Sec.AccountRolePolicy
    WHERE RoleCodeTemplate = '{AccountCode}_EU_MANAGER'
      AND ScopeType = 'ORGUNIT'
      AND OrgUnitType = 'Region'
      AND OrgUnitCode = 'EMEA'
)
BEGIN
    INSERT INTO Sec.AccountRolePolicy
        (PolicyName, RoleCodeTemplate, RoleNameTemplate, ScopeType, OrgUnitType, OrgUnitCode)
    VALUES
        ('Per-account EMEA Region Manager Role',
         '{AccountCode}_EU_MANAGER',
         '{AccountName} EMEA Region Manager',
         'ORGUNIT',
         'Region',
         'EMEA');
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

EXEC Sec.GrantPathPrefix @PrincipalType = 'Role', @PrincipalIdentifier = 'FIN_DHL_EU', @AccountCode = 'DHL', @OrgUnitType = 'Region', @OrgUnitCode = 'EMEA';
EXEC Sec.GrantPathPrefix @PrincipalType = 'Role', @PrincipalIdentifier = 'FIN_UPS_LATAM', @AccountCode = 'UPS', @OrgUnitType = 'Region', @OrgUnitCode = 'LATAM';
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
    @OrgUnitType            = 'Region',
    @OrgUnitCode            = 'EMEA';

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

EXEC Sec.GrantPathPrefix @PrincipalType = 'User', @PrincipalIdentifier = 'li.na@fabrikam.com', @AccountCode = 'FEDEX', @OrgUnitType = 'Region', @OrgUnitCode = 'APAC';
EXEC Sec.GrantPathPrefix @PrincipalType = 'User', @PrincipalIdentifier = 'ines.silva@fabrikam.com', @AccountCode = 'UPS', @OrgUnitType = 'Country', @OrgUnitCode = 'BR';
EXEC Sec.GrantPathPrefix @PrincipalType = 'User', @PrincipalIdentifier = 'quinn.hughes@fabrikam.com', @AccountCode = 'FEDEX', @OrgUnitType = 'Region', @OrgUnitCode = 'EMEA';
EXEC Sec.GrantPathPrefix @PrincipalType = 'User', @PrincipalIdentifier = 'priya.bose@fabrikam.com', @AccountCode = 'AMZN', @OrgUnitType = 'Country', @OrgUnitCode = 'SG';
EXEC Sec.GrantPathPrefix @PrincipalType = 'User', @PrincipalIdentifier = 'john.doe@fabrikam.com', @AccountCode = 'DHL', @OrgUnitType = 'Site', @OrgUnitCode = 'US-01';
EXEC Sec.GrantPathPrefix @PrincipalType = 'User', @PrincipalIdentifier = 'karla.nygaard@fabrikam.com', @AccountCode = 'DHL', @OrgUnitType = 'Site', @OrgUnitCode = 'US-02';
EXEC Sec.GrantPathPrefix @PrincipalType = 'User', @PrincipalIdentifier = 'oliver.brink@fabrikam.com', @AccountCode = 'ACME', @OrgUnitType = 'Site', @OrgUnitCode = 'BE-01';
EXEC Sec.GrantPathPrefix @PrincipalType = 'User', @PrincipalIdentifier = 'sofia.fernandez@fabrikam.com', @AccountCode = 'UPS', @OrgUnitType = 'Site', @OrgUnitCode = 'MX-02';
EXEC Sec.GrantPathPrefix @PrincipalType = 'User', @PrincipalIdentifier = 'tomoko.sato@fabrikam.com', @AccountCode = 'FEDEX', @OrgUnitType = 'Country', @OrgUnitCode = 'AU';

EXEC Sec.GrantCountryAllAccounts @PrincipalType = 'User', @PrincipalIdentifier = 'felix.mercier@fabrikam.com', @CountryCode = 'BE';
EXEC Sec.GrantCountryAllAccounts @PrincipalType = 'User', @PrincipalIdentifier = 'ravi.patel@fabrikam.com', @CountryCode = 'SG';
EXEC Sec.GrantCountryAllAccounts @PrincipalType = 'User', @PrincipalIdentifier = 'tomoko.sato@fabrikam.com', @CountryCode = 'AU';

-- Seed non-KPI grant lifecycle metadata introduced by migration 003. Keep the
-- sample deterministic while avoiding KPI grants and KPI-specific seed data.
DECLARE @SeedGrantActorId INT = (
    SELECT UserId
    FROM Sec.[User]
    WHERE UPN = 'allison.tate@fabrikam.com'
);

UPDATE ppg
SET ppg.GrantedByPrincipalId = @SeedGrantActorId,
    ppg.ExpiresAt = CASE
                        WHEN u.UPN = 'victor.lee@fabrikam.com' AND pkg.PackageCode = 'GUARD'
                            THEN DATEADD(DAY, 90, @Now)
                        ELSE NULL
                    END,
    ppg.RevokedAt = CASE
                        WHEN u.UPN = 'allison.tate@fabrikam.com' AND ppg.GrantScope = 'ALL_PACKAGES'
                            THEN DATEADD(DAY, -5, @Now)
                        ELSE NULL
                    END,
    ppg.RevokedByPrincipalId = CASE
                                   WHEN u.UPN = 'allison.tate@fabrikam.com' AND ppg.GrantScope = 'ALL_PACKAGES'
                                       THEN @SeedGrantActorId
                                   ELSE NULL
                               END,
    ppg.ModifiedBy = 'seed_test_data'
FROM Sec.PrincipalPackageGrant AS ppg
JOIN Sec.[User] AS u
    ON u.UserId = ppg.PrincipalId
LEFT JOIN Dim.Package AS pkg
    ON pkg.PackageId = ppg.PackageId
WHERE (pkg.PackageCode IN ('GUARD', 'FIN', 'SOC') OR pkg.PackageCode IS NULL)
  AND u.UPN IN ('allison.tate@fabrikam.com', 'victor.lee@fabrikam.com');

;WITH FelixRevokedGrant AS
(
    SELECT TOP (1) pag.PrincipalAccessGrantId
    FROM Sec.PrincipalAccessGrant AS pag
    JOIN Sec.[User] AS u
        ON u.UserId = pag.PrincipalId
    JOIN Dim.OrgUnit AS ou
        ON ou.OrgUnitId = pag.OrgUnitId
    WHERE u.UPN = 'felix.mercier@fabrikam.com'
      AND pag.AccessType = 'ALL'
      AND pag.ScopeType = 'ORGUNIT'
      AND ou.OrgUnitType = 'Country'
      AND ou.OrgUnitCode = 'BE'
    ORDER BY pag.PrincipalAccessGrantId
)
UPDATE pag
SET pag.GrantedByPrincipalId = @SeedGrantActorId,
    pag.ExpiresAt = CASE
                        WHEN u.UPN = 'victor.lee@fabrikam.com' AND a.AccountCode = 'ACME' AND pag.ScopeType = 'NONE'
                            THEN DATEADD(DAY, 45, @Now)
                        ELSE NULL
                    END,
    pag.RevokedAt = CASE
                        WHEN frg.PrincipalAccessGrantId IS NOT NULL
                            THEN DATEADD(DAY, -3, @Now)
                        ELSE NULL
                    END,
    pag.RevokedByPrincipalId = CASE
                                   WHEN frg.PrincipalAccessGrantId IS NOT NULL
                                       THEN @SeedGrantActorId
                                   ELSE NULL
                               END,
    pag.ModifiedBy = 'seed_test_data'
FROM Sec.PrincipalAccessGrant AS pag
JOIN Sec.[User] AS u
    ON u.UserId = pag.PrincipalId
LEFT JOIN Dim.Account AS a
    ON a.AccountId = pag.AccountId
LEFT JOIN FelixRevokedGrant AS frg
    ON frg.PrincipalAccessGrantId = pag.PrincipalAccessGrantId
WHERE u.UPN IN ('felix.mercier@fabrikam.com', 'victor.lee@fabrikam.com');

-- Seed KPI roles, reference data, periods, assignments, and reminder state -------
DECLARE @KpiAdminRoleId INT;
DECLARE @KpiReviewerRoleId INT;

EXEC App.UpsertRole
    @RoleCode = 'KPI-ADMIN',
    @RoleName = 'KPI Platform Administrators',
    @Description = 'Manage KPI definitions, periods, and assignments. View all submission data.',
    @RoleId = @KpiAdminRoleId OUTPUT;

EXEC App.UpsertRole
    @RoleCode = 'KPI-REVIEWER',
    @RoleName = 'KPI Data Reviewers',
    @Description = 'Read-only access to KPI submission data across all accounts.',
    @RoleId = @KpiReviewerRoleId OUTPUT;

DECLARE @kid INT;

EXEC App.usp_UpsertKpiDefinition @KPICode = 'S-001', @KPIName = 'Lost Time Injury Rate', @KPIDescription = N'Number of lost-time injuries per 100 full-time equivalent employees per year. Calculated monthly on an annualised basis.', @Category = 'Safety', @Unit = 'per 100 FTE', @DataType = 'Numeric', @CollectionType = 'Manual', @ThresholdDirection = 'Lower', @KPIID = @kid OUTPUT;
EXEC App.usp_UpsertKpiDefinition @KPICode = 'S-002', @KPIName = 'Near Miss Reports', @KPIDescription = N'Total number of near-miss incidents formally reported in the period. Higher reporting indicates a healthy safety culture.', @Category = 'Safety', @Unit = 'count', @DataType = 'Numeric', @CollectionType = 'Manual', @ThresholdDirection = 'Higher', @KPIID = @kid OUTPUT;
EXEC App.usp_UpsertKpiDefinition @KPICode = 'S-003', @KPIName = 'Safety Training Completion Rate', @KPIDescription = N'Percentage of required safety training modules completed by eligible staff in the period.', @Category = 'Safety', @Unit = '%', @DataType = 'Percentage', @CollectionType = 'Manual', @ThresholdDirection = 'Higher', @KPIID = @kid OUTPUT;
EXEC App.usp_UpsertKpiDefinition @KPICode = 'S-004', @KPIName = 'Vehicle Incident Rate', @KPIDescription = N'Number of vehicle-related incidents (collisions, near misses) per 1,000 vehicle movements.', @Category = 'Safety', @Unit = 'per 1,000 movements', @DataType = 'Numeric', @CollectionType = 'Manual', @ThresholdDirection = 'Lower', @KPIID = @kid OUTPUT;

EXEC App.usp_UpsertKpiDefinition @KPICode = 'Q-001', @KPIName = 'On-Time Delivery Rate', @KPIDescription = N'Percentage of shipments delivered on or before the committed delivery date.', @Category = 'Quality', @Unit = '%', @DataType = 'Percentage', @CollectionType = 'Manual', @ThresholdDirection = 'Higher', @KPIID = @kid OUTPUT;
EXEC App.usp_UpsertKpiDefinition @KPICode = 'Q-002', @KPIName = 'Customer Complaint Rate', @KPIDescription = N'Number of formal customer complaints per 10,000 shipments processed.', @Category = 'Quality', @Unit = 'per 10,000 shipments', @DataType = 'Numeric', @CollectionType = 'Manual', @ThresholdDirection = 'Lower', @KPIID = @kid OUTPUT;
EXEC App.usp_UpsertKpiDefinition @KPICode = 'Q-003', @KPIName = 'First-Time Quality Rate', @KPIDescription = N'Percentage of operations completed correctly on the first attempt, without rework or correction.', @Category = 'Quality', @Unit = '%', @DataType = 'Percentage', @CollectionType = 'Manual', @ThresholdDirection = 'Higher', @KPIID = @kid OUTPUT;
EXEC App.usp_UpsertKpiDefinition @KPICode = 'Q-004', @KPIName = 'Damage / Loss Rate', @KPIDescription = N'Percentage of shipments with reported damage or loss claims.', @Category = 'Quality', @Unit = '%', @DataType = 'Percentage', @CollectionType = 'Manual', @ThresholdDirection = 'Lower', @KPIID = @kid OUTPUT;

EXEC App.usp_UpsertKpiDefinition @KPICode = 'P-001', @KPIName = 'Shipments Per FTE Per Day', @KPIDescription = N'Average number of shipments processed per full-time equivalent employee per working day.', @Category = 'Productivity', @Unit = 'shipments/FTE/day', @DataType = 'Numeric', @CollectionType = 'Manual', @ThresholdDirection = 'Higher', @KPIID = @kid OUTPUT;
EXEC App.usp_UpsertKpiDefinition @KPICode = 'P-002', @KPIName = 'Warehouse Space Utilisation', @KPIDescription = N'Percentage of allocated warehouse space in active use.', @Category = 'Productivity', @Unit = '%', @DataType = 'Percentage', @CollectionType = 'Manual', @ThresholdDirection = 'Higher', @KPIID = @kid OUTPUT;
EXEC App.usp_UpsertKpiDefinition @KPICode = 'P-003', @KPIName = 'Vehicle Fleet Utilisation', @KPIDescription = N'Percentage of available vehicle capacity actively deployed on deliveries.', @Category = 'Productivity', @Unit = '%', @DataType = 'Percentage', @CollectionType = 'Manual', @ThresholdDirection = 'Higher', @KPIID = @kid OUTPUT;
EXEC App.usp_UpsertKpiDefinition @KPICode = 'P-004', @KPIName = 'Order Pick Accuracy', @KPIDescription = N'Percentage of order picking operations completed without error (wrong item, wrong quantity, wrong address).', @Category = 'Productivity', @Unit = '%', @DataType = 'Percentage', @CollectionType = 'Manual', @ThresholdDirection = 'Higher', @KPIID = @kid OUTPUT;

EXEC App.usp_UpsertKpiDefinition @KPICode = 'F-001', @KPIName = 'Cost Per Shipment', @KPIDescription = N'Total operational cost divided by total shipments processed. Expressed in local reporting currency.', @Category = 'Finance', @Unit = 'EUR', @DataType = 'Currency', @CollectionType = 'Manual', @ThresholdDirection = 'Lower', @KPIID = @kid OUTPUT;
EXEC App.usp_UpsertKpiDefinition @KPICode = 'F-002', @KPIName = 'Revenue Per Site', @KPIDescription = N'Total revenue attributable to the site in the reporting period.', @Category = 'Finance', @Unit = 'EUR', @DataType = 'Currency', @CollectionType = 'Manual', @ThresholdDirection = 'Higher', @KPIID = @kid OUTPUT;
EXEC App.usp_UpsertKpiDefinition @KPICode = 'F-003', @KPIName = 'Operating Margin', @KPIDescription = N'Operating profit as a percentage of revenue for the period.', @Category = 'Finance', @Unit = '%', @DataType = 'Percentage', @CollectionType = 'Manual', @ThresholdDirection = 'Higher', @KPIID = @kid OUTPUT;
EXEC App.usp_UpsertKpiDefinition @KPICode = 'F-004', @KPIName = 'Overtime Cost Ratio', @KPIDescription = N'Overtime labour cost as a percentage of total labour cost in the period.', @Category = 'Finance', @Unit = '%', @DataType = 'Percentage', @CollectionType = 'Manual', @ThresholdDirection = 'Lower', @KPIID = @kid OUTPUT;

EXEC App.usp_UpsertKpiDefinition @KPICode = 'H-001', @KPIName = 'Staff Turnover Rate', @KPIDescription = N'Percentage of headcount that left the organisation (voluntary and involuntary) during the period, annualised.', @Category = 'HR/People', @Unit = '%', @DataType = 'Percentage', @CollectionType = 'Manual', @ThresholdDirection = 'Lower', @KPIID = @kid OUTPUT;
EXEC App.usp_UpsertKpiDefinition @KPICode = 'H-002', @KPIName = 'Absenteeism Rate', @KPIDescription = N'Percentage of scheduled working hours lost to unplanned absence (sickness, unauthorised leave).', @Category = 'HR/People', @Unit = '%', @DataType = 'Percentage', @CollectionType = 'Manual', @ThresholdDirection = 'Lower', @KPIID = @kid OUTPUT;
EXEC App.usp_UpsertKpiDefinition @KPICode = 'H-003', @KPIName = 'Training Hours Per Employee', @KPIDescription = N'Average number of formal training hours completed per employee in the period.', @Category = 'HR/People', @Unit = 'hours', @DataType = 'Numeric', @CollectionType = 'Manual', @ThresholdDirection = 'Higher', @KPIID = @kid OUTPUT;

EXEC App.usp_UpsertKpiDefinition @KPICode = 'C-001', @KPIName = 'Regulatory Audit Pass Rate', @KPIDescription = N'Percentage of internal and external regulatory audits passed without major findings.', @Category = 'Compliance', @Unit = '%', @DataType = 'Percentage', @CollectionType = 'Manual', @ThresholdDirection = 'Higher', @KPIID = @kid OUTPUT;
EXEC App.usp_UpsertKpiDefinition @KPICode = 'C-002', @KPIName = 'Security Incidents Reported', @KPIDescription = N'Number of security-related incidents (theft, unauthorised access, data breach) formally reported in the period.', @Category = 'Compliance', @Unit = 'count', @DataType = 'Numeric', @CollectionType = 'Manual', @ThresholdDirection = 'Lower', @KPIID = @kid OUTPUT;
EXEC App.usp_UpsertKpiDefinition @KPICode = 'C-003', @KPIName = 'Certification Compliance Rate', @KPIDescription = N'Percentage of required operational certifications (ISO, TAPA, GDP) that are current and valid.', @Category = 'Compliance', @Unit = '%', @DataType = 'Percentage', @CollectionType = 'Manual', @ThresholdDirection = 'Higher', @KPIID = @kid OUTPUT;

DECLARE @QtrPeriod0101 INT;       -- Jan 2026 on quarterly schedule
DECLARE @MthPeriod0202 INT;       -- Feb 2026 on monthly schedule
DECLARE @BiMthPeriod0202 INT;     -- Feb 2026 on bi-monthly schedule
DECLARE @MthPeriod0203 INT;       -- Mar 2026 on monthly schedule
DECLARE @MthPeriod0204 INT;       -- Apr 2026 on monthly schedule (current)
DECLARE @MthPeriod0205 INT;
DECLARE @MthPeriod0206 INT;
DECLARE @MonthlyScheduleId INT;
DECLARE @QuarterlyScheduleId INT;
DECLARE @BiMonthlyScheduleId INT;
DECLARE @KpiAssignmentTemplateId INT;
DECLARE @ClosePeriodResult TABLE (SubmissionsForceLockedOnClose INT);

EXEC App.usp_UpsertKpiPeriodSchedule
    @ScheduleName = N'Monthly Operations Reporting',
    @FrequencyType = 'Monthly',
    @FrequencyInterval = NULL,
    @StartDate = '2026-02-01',
    @EndDate = '2026-06-30',
    @SubmissionOpenDay = 1,
    @SubmissionCloseDay = 25,
    @GenerateMonthsAhead = 6,
    @Notes = N'Primary monthly cadence for operational KPIs.',
    @PeriodScheduleID = @MonthlyScheduleId OUTPUT;

EXEC App.usp_UpsertKpiPeriodSchedule
    @ScheduleName = N'Quarterly Executive Review',
    @FrequencyType = 'Quarterly',
    @FrequencyInterval = NULL,
    @StartDate = '2026-01-01',
    @EndDate = '2026-12-31',
    @SubmissionOpenDay = 1,
    @SubmissionCloseDay = 20,
    @GenerateMonthsAhead = 12,
    @Notes = N'Quarterly cadence for finance and executive scorecard KPIs.',
    @PeriodScheduleID = @QuarterlyScheduleId OUTPUT;

EXEC App.usp_UpsertKpiPeriodSchedule
    @ScheduleName = N'Bi-Monthly Compliance Cycle',
    @FrequencyType = 'EveryNMonths',
    @FrequencyInterval = 2,
    @StartDate = '2026-02-01',
    @EndDate = '2026-12-31',
    @SubmissionOpenDay = 5,
    @SubmissionCloseDay = 26,
    @GenerateMonthsAhead = 8,
    @Notes = N'Every-two-month cadence for compliance KPIs and certifications.',
    @PeriodScheduleID = @BiMonthlyScheduleId OUTPUT;

EXEC App.usp_GenerateKpiPeriods @PeriodScheduleID = @MonthlyScheduleId;
EXEC App.usp_GenerateKpiPeriods @PeriodScheduleID = @QuarterlyScheduleId;
EXEC App.usp_GenerateKpiPeriods @PeriodScheduleID = @BiMonthlyScheduleId;

-- Resolve period IDs — must scope by schedule since the same year/month can
-- exist independently in multiple schedules
SELECT @QtrPeriod0101   = PeriodID FROM KPI.Period WHERE PeriodScheduleID = @QuarterlyScheduleId  AND PeriodYear = 2026 AND PeriodMonth = 1;
SELECT @MthPeriod0202   = PeriodID FROM KPI.Period WHERE PeriodScheduleID = @MonthlyScheduleId    AND PeriodYear = 2026 AND PeriodMonth = 2;
SELECT @BiMthPeriod0202 = PeriodID FROM KPI.Period WHERE PeriodScheduleID = @BiMonthlyScheduleId  AND PeriodYear = 2026 AND PeriodMonth = 2;
SELECT @MthPeriod0203   = PeriodID FROM KPI.Period WHERE PeriodScheduleID = @MonthlyScheduleId    AND PeriodYear = 2026 AND PeriodMonth = 3;
SELECT @MthPeriod0204   = PeriodID FROM KPI.Period WHERE PeriodScheduleID = @MonthlyScheduleId    AND PeriodYear = 2026 AND PeriodMonth = 4;
SELECT @MthPeriod0205   = PeriodID FROM KPI.Period WHERE PeriodScheduleID = @MonthlyScheduleId    AND PeriodYear = 2026 AND PeriodMonth = 5;
SELECT @MthPeriod0206   = PeriodID FROM KPI.Period WHERE PeriodScheduleID = @MonthlyScheduleId    AND PeriodYear = 2026 AND PeriodMonth = 6;

-- Open periods (usp_OpenPeriod auto-materializes templates and initialises reminder state)
IF EXISTS (SELECT 1 FROM KPI.Period WHERE PeriodID = @QtrPeriod0101 AND Status = 'Draft')
    EXEC App.usp_OpenPeriod @PeriodID = @QtrPeriod0101;
IF EXISTS (SELECT 1 FROM KPI.Period WHERE PeriodID = @MthPeriod0202 AND Status = 'Draft')
    EXEC App.usp_OpenPeriod @PeriodID = @MthPeriod0202;
IF EXISTS (SELECT 1 FROM KPI.Period WHERE PeriodID = @BiMthPeriod0202 AND Status = 'Draft')
    EXEC App.usp_OpenPeriod @PeriodID = @BiMthPeriod0202;
IF EXISTS (SELECT 1 FROM KPI.Period WHERE PeriodID = @MthPeriod0203 AND Status = 'Draft')
    EXEC App.usp_OpenPeriod @PeriodID = @MthPeriod0203;
IF EXISTS (SELECT 1 FROM KPI.Period WHERE PeriodID = @MthPeriod0204 AND Status = 'Draft')
    EXEC App.usp_OpenPeriod @PeriodID = @MthPeriod0204;

-- Keep seeded submission periods writable regardless of when the seed runs.
-- The submit proc validates against the period's submission close date, so
-- historical sample periods need a temporary window around the current run.
UPDATE KPI.Period
SET SubmissionOpenDate  = DATEADD(DAY, -30, CAST(@Now AS DATE)),
    SubmissionCloseDate = DATEADD(DAY, 30,  CAST(@Now AS DATE)),
    ModifiedOnUtc       = @Now,
    ModifiedBy          = 'seed_test_data'
WHERE Status = 'Open'
  AND PeriodID IN (@QtrPeriod0101, @MthPeriod0202, @BiMthPeriod0202, @MthPeriod0203, @MthPeriod0204);

-- DHL uses their own terminology: library calls this "Lost Time Injury Rate" but
-- DHL refers to it as "Injury Frequency Rate" in their internal scorecards.
-- CustomKpiName / CustomKpiDescription override the library name on reports and forms.
EXEC App.usp_UpsertKpiAssignmentTemplate
    @KPICode = 'S-001',
    @PeriodScheduleID = @MonthlyScheduleId,
    @AccountCode = 'DHL',
    @OrgUnitCode = NULL,
    @IsRequired = 1,
    @TargetValue = 0.3,
    @ThresholdGreen = 0.5,
    @ThresholdAmber = 1.0,
    @ThresholdRed = NULL,
    @ThresholdDirection = NULL,
    @SubmitterGuidance = N'Enter the annualised LTIR for the month. Formula: (lost-time injuries × 200,000) / total hours worked.',
    @CustomKpiName = N'Injury Frequency Rate',
    @CustomKpiDescription = N'DHL internal name for Lost Time Injury Rate. Reports the annualised IFR per 100 FTE.',
    @AssignmentTemplateID = @KpiAssignmentTemplateId OUTPUT;

EXEC App.usp_UpsertKpiAssignmentTemplate
    @KPICode = 'Q-001',
    @PeriodScheduleID = @MonthlyScheduleId,
    @AccountCode = 'DHL',
    @OrgUnitCode = NULL,
    @IsRequired = 1,
    @TargetValue = 98.5,
    @ThresholdGreen = 98.0,
    @ThresholdAmber = 95.0,
    @ThresholdRed = NULL,
    @ThresholdDirection = NULL,
    @SubmitterGuidance = N'Enter the percentage of shipments delivered on or before committed date. Include all delivery modes.',
    @AssignmentTemplateID = @KpiAssignmentTemplateId OUTPUT;

EXEC App.usp_UpsertKpiAssignmentTemplate
    @KPICode = 'P-001',
    @PeriodScheduleID = @MonthlyScheduleId,
    @AccountCode = 'UPS',
    @OrgUnitCode = NULL,
    @IsRequired = 1,
    @TargetValue = 52.0,
    @ThresholdGreen = 50.0,
    @ThresholdAmber = 40.0,
    @ThresholdRed = NULL,
    @ThresholdDirection = NULL,
    @SubmitterGuidance = N'Total shipments processed ÷ (FTE headcount × working days in period).',
    @AssignmentTemplateID = @KpiAssignmentTemplateId OUTPUT;

EXEC App.usp_UpsertKpiAssignmentTemplate
    @KPICode = 'Q-001',
    @PeriodScheduleID = @MonthlyScheduleId,
    @AccountCode = 'UPS',
    @OrgUnitCode = 'MX-02',
    @OrgUnitType = 'Site',
    @IsRequired = 1,
    @TargetValue = 98.5,
    @ThresholdGreen = 98.0,
    @ThresholdAmber = 95.0,
    @ThresholdRed = NULL,
    @ThresholdDirection = NULL,
    @SubmitterGuidance = N'Enter the percentage of shipments delivered on or before committed date. Include all delivery modes.',
    @AssignmentTemplateID = @KpiAssignmentTemplateId OUTPUT;

EXEC App.usp_UpsertKpiAssignmentTemplate
    @KPICode = 'H-001',
    @PeriodScheduleID = @MonthlyScheduleId,
    @AccountCode = 'AMZN',
    @OrgUnitCode = NULL,
    @IsRequired = 1,
    @TargetValue = 4.0,
    @ThresholdGreen = 5.0,
    @ThresholdAmber = 10.0,
    @ThresholdRed = NULL,
    @ThresholdDirection = NULL,
    @SubmitterGuidance = N'(Leavers in period ÷ average headcount) × (12 ÷ months in period) × 100. Include voluntary and involuntary departures.',
    @AssignmentTemplateID = @KpiAssignmentTemplateId OUTPUT;

EXEC App.usp_UpsertKpiAssignmentTemplate
    @KPICode = 'F-001',
    @PeriodScheduleID = @QuarterlyScheduleId,
    @AccountCode = 'FEDEX',
    @OrgUnitCode = NULL,
    @IsRequired = 1,
    @TargetValue = 3.20,
    @ThresholdGreen = 3.50,
    @ThresholdAmber = 4.50,
    @ThresholdRed = NULL,
    @ThresholdDirection = NULL,
    @SubmitterGuidance = N'Total operational cost (EUR) ÷ total shipments. Exclude capital items. Convert non-EUR costs at period average rate.',
    @AssignmentTemplateID = @KpiAssignmentTemplateId OUTPUT;

EXEC App.usp_UpsertKpiAssignmentTemplate
    @KPICode = 'F-001',
    @PeriodScheduleID = @QuarterlyScheduleId,
    @AccountCode = 'ACME',
    @OrgUnitCode = NULL,
    @IsRequired = 1,
    @TargetValue = 3.20,
    @ThresholdGreen = 3.50,
    @ThresholdAmber = 4.50,
    @ThresholdRed = NULL,
    @ThresholdDirection = NULL,
    @SubmitterGuidance = N'Total operational cost (EUR) ÷ total shipments. Exclude capital items. Convert non-EUR costs at period average rate.',
    @AssignmentTemplateID = @KpiAssignmentTemplateId OUTPUT;

EXEC App.usp_UpsertKpiAssignmentTemplate
    @KPICode = 'F-004',
    @PeriodScheduleID = @QuarterlyScheduleId,
    @AccountCode = 'DHL',
    @OrgUnitCode = NULL,
    @IsRequired = 1,
    @TargetValue = 3.5,
    @ThresholdGreen = 4.0,
    @ThresholdAmber = 6.0,
    @ThresholdRed = NULL,
    @ThresholdDirection = NULL,
    @SubmitterGuidance = N'Overtime labour cost as a percentage of total labour cost in the quarter.',
    @AssignmentTemplateID = @KpiAssignmentTemplateId OUTPUT;

EXEC App.usp_UpsertKpiAssignmentTemplate
    @KPICode = 'C-001',
    @PeriodScheduleID = @BiMonthlyScheduleId,
    @AccountCode = 'FEDEX',
    @OrgUnitCode = NULL,
    @IsRequired = 1,
    @TargetValue = 95.0,
    @ThresholdGreen = 95.0,
    @ThresholdAmber = 90.0,
    @ThresholdRed = NULL,
    @ThresholdDirection = 'Higher',
    @SubmitterGuidance = N'Percentage of audits passed without major findings during the cycle.',
    @AssignmentTemplateID = @KpiAssignmentTemplateId OUTPUT;

EXEC App.usp_UpsertKpiAssignmentTemplate
    @KPICode = 'C-002',
    @PeriodScheduleID = @BiMonthlyScheduleId,
    @AccountCode = 'ACME',
    @OrgUnitCode = NULL,
    @IsRequired = 1,
    @TargetValue = 2.0,
    @ThresholdGreen = 2.0,
    @ThresholdAmber = 4.0,
    @ThresholdRed = NULL,
    @ThresholdDirection = 'Lower',
    @SubmitterGuidance = N'Count all reportable security incidents in the cycle.',
    @AssignmentTemplateID = @KpiAssignmentTemplateId OUTPUT;

EXEC App.usp_UpsertKpiAssignmentTemplate
    @KPICode = 'C-003',
    @PeriodScheduleID = @BiMonthlyScheduleId,
    @AccountCode = 'UPS',
    @OrgUnitCode = 'MX-02',
    @OrgUnitType = 'Site',
    @IsRequired = 1,
    @TargetValue = 99.0,
    @ThresholdGreen = 99.0,
    @ThresholdAmber = 95.0,
    @ThresholdRed = NULL,
    @ThresholdDirection = 'Higher',
    @SubmitterGuidance = N'Percentage of required certifications that remain current and valid.',
    @AssignmentTemplateID = @KpiAssignmentTemplateId OUTPUT;

-- Group-scoped templates: DHL site MX-01 has both "Technology" and "Operational" KPI owners.
-- Two templates for the same KPI+site+schedule are allowed because they differ by AssignmentGroupName.
-- Technology group owns on-time delivery and quality metrics.
EXEC App.usp_UpsertKpiAssignmentTemplate
    @KPICode = 'Q-001',
    @PeriodScheduleID = @MonthlyScheduleId,
    @AccountCode = 'DHL',
    @OrgUnitCode = 'MX-01',
    @OrgUnitType = 'Site',
    @IsRequired = 1,
    @TargetValue = 99.0,
    @ThresholdGreen = 98.0,
    @ThresholdAmber = 95.0,
    @ThresholdDirection = 'Higher',
    @AssignmentGroupName = N'Technology',
    @AssignmentTemplateID = @KpiAssignmentTemplateId OUTPUT;

-- Operational group owns safety metrics for the same site.
EXEC App.usp_UpsertKpiAssignmentTemplate
    @KPICode = 'S-002',
    @PeriodScheduleID = @MonthlyScheduleId,
    @AccountCode = 'DHL',
    @OrgUnitCode = 'MX-01',
    @OrgUnitType = 'Site',
    @IsRequired = 1,
    @ThresholdDirection = 'Higher',
    @AssignmentGroupName = N'Operational',
    @AssignmentTemplateID = @KpiAssignmentTemplateId OUTPUT;

-- Note: usp_MaterializeKpiAssignmentTemplates is called automatically inside
-- usp_OpenPeriod for each schedule. No standalone call needed.

DECLARE @SeedSubmission TABLE
(
    Id INT IDENTITY(1,1) PRIMARY KEY,
    PeriodYear SMALLINT,
    PeriodMonth TINYINT,
    AccountCode NVARCHAR(50),
    KPICode NVARCHAR(50),
    SiteCode NVARCHAR(50) NULL,
    SubmitterUPN NVARCHAR(320),
    SubmissionValue DECIMAL(18,4) NULL,
    SubmissionText NVARCHAR(1000) NULL,
    SubmissionNotes NVARCHAR(500) NULL,
    LockOnSubmit BIT
);

INSERT INTO @SeedSubmission
    (PeriodYear, PeriodMonth, AccountCode, KPICode, SiteCode, SubmitterUPN, SubmissionValue, SubmissionText, SubmissionNotes, LockOnSubmit)
VALUES
    (2026, 1, 'FEDEX', 'F-001', NULL,    'victor.lee@fabrikam.com', 3.5100, NULL, N'Q1 finance review completed for FedEx.', 1),
    (2026, 1, 'ACME',  'F-001', NULL,    'oliver.brink@fabrikam.com', 4.0100, NULL, N'ACME quarterly finance pack submitted.', 1),
    (2026, 1, 'DHL',   'F-004', NULL,    'allison.tate@fabrikam.com', 3.8200, NULL, N'DHL quarterly overtime ratio submitted.', 1),
    (2026, 2, 'DHL',   'S-001', NULL,    'allison.tate@fabrikam.com', 0.2600, NULL, N'DHL February safety submission completed on time.', 1),
    (2026, 2, 'DHL',   'Q-001', NULL,    'allison.tate@fabrikam.com', 98.2000, NULL, N'DHL February delivery performance submitted.', 1),
    (2026, 2, 'UPS',   'P-001', NULL,    'carla.gomez@fabrikam.com', 51.6000, NULL, N'UPS February productivity submitted.', 1),
    (2026, 2, 'FEDEX', 'C-001', NULL,    'victor.lee@fabrikam.com', 96.0000, NULL, N'FedEx compliance audit cycle submitted.', 1),
    (2026, 3, 'DHL',   'S-001', NULL,    'allison.tate@fabrikam.com', 0.2200, NULL, N'DHL March safety figure submitted.', 1),
    (2026, 3, 'AMZN',  'H-001', NULL,    'priya.bose@fabrikam.com', 5.1000, NULL, N'Amazon March attrition reported.', 1),
    (2026, 4, 'DHL',   'S-001', NULL,    'allison.tate@fabrikam.com', 0.2100, NULL, N'DHL April safety submission saved but still under review.', 0),
    (2026, 4, 'DHL',   'Q-001', NULL,    'allison.tate@fabrikam.com', 98.9000, NULL, N'Delivery performance remained above target.', 1),
    (2026, 4, 'UPS',   'Q-001', 'MX-02', 'sofia.fernandez@fabrikam.com', 96.4000, NULL, N'Mexico site submitted with one late carrier exception.', 1),
    (2026, 4, 'FEDEX', 'F-001', NULL,    'victor.lee@fabrikam.com', 3.4700, NULL, N'FedEx Q2 finance review drafted for sign-off.', 0),
    (2026, 4, 'AMZN',  'H-001', NULL,    'priya.bose@fabrikam.com', 4.8000, NULL, N'April attrition slightly elevated after seasonal ramp-down.', 0),
    (2026, 4, 'FEDEX', 'C-001', NULL,    'victor.lee@fabrikam.com', 97.2000, NULL, N'FedEx April compliance cycle submitted.', 0);

DECLARE @SeedSubmissionId INT;
DECLARE @SeedPeriodYear SMALLINT;
DECLARE @SeedPeriodMonth TINYINT;
DECLARE @SeedSubmissionAccountCode NVARCHAR(50);
DECLARE @SeedSubmissionKpiCode NVARCHAR(50);
DECLARE @SeedSubmissionSiteCode NVARCHAR(50);
DECLARE @SeedSubmissionUPN NVARCHAR(320);
DECLARE @SeedSubmissionValue DECIMAL(18,4);
DECLARE @SeedSubmissionText NVARCHAR(1000);
DECLARE @SeedSubmissionNotes NVARCHAR(500);
DECLARE @SeedSubmissionLockOnSubmit BIT;
DECLARE @SeedAssignmentExternalId UNIQUEIDENTIFIER;
DECLARE @SeedSubmissionResultId INT;
DECLARE @HasSubmission BIT;

WHILE EXISTS (SELECT 1 FROM @SeedSubmission)
BEGIN
    SELECT TOP (1)
        @SeedSubmissionId = Id,
        @SeedPeriodYear = PeriodYear,
        @SeedPeriodMonth = PeriodMonth,
        @SeedSubmissionAccountCode = AccountCode,
        @SeedSubmissionKpiCode = KPICode,
        @SeedSubmissionSiteCode = SiteCode,
        @SeedSubmissionUPN = SubmitterUPN,
        @SeedSubmissionValue = SubmissionValue,
        @SeedSubmissionText = SubmissionText,
        @SeedSubmissionNotes = SubmissionNotes,
        @SeedSubmissionLockOnSubmit = LockOnSubmit
    FROM @SeedSubmission
    ORDER BY Id;

    SET @SeedAssignmentExternalId = NULL;
    SET @HasSubmission = 0;

    SELECT @SeedAssignmentExternalId = a.ExternalId
    FROM App.vKpiAssignments AS a
    WHERE a.AccountCode = @SeedSubmissionAccountCode
      AND a.KPICode = @SeedSubmissionKpiCode
      AND a.PeriodYear = @SeedPeriodYear
      AND a.PeriodMonth = @SeedPeriodMonth
      AND (
            (@SeedSubmissionSiteCode IS NULL AND a.SiteCode IS NULL)
            OR a.SiteCode = @SeedSubmissionSiteCode
          );

    IF @SeedAssignmentExternalId IS NOT NULL
    BEGIN
        IF EXISTS (
            SELECT 1
            FROM KPI.Submission AS s
            JOIN KPI.Assignment AS ka
                ON ka.AssignmentID = s.AssignmentID
            WHERE ka.ExternalId = @SeedAssignmentExternalId
        )
        BEGIN
            SET @HasSubmission = 1;
        END

        IF @HasSubmission = 0
        BEGIN
            EXEC App.usp_SubmitKpi
                @AssignmentExternalId = @SeedAssignmentExternalId,
                @SubmitterUPN = @SeedSubmissionUPN,
                @SubmissionValue = @SeedSubmissionValue,
                @SubmissionText = @SeedSubmissionText,
                @SubmissionNotes = @SeedSubmissionNotes,
                @SourceType = 'Manual',
                @LockOnSubmit = @SeedSubmissionLockOnSubmit,
                @SubmissionID = @SeedSubmissionResultId OUTPUT;
        END
    END

    DELETE FROM @SeedSubmission WHERE Id = @SeedSubmissionId;
END;

-- Close historical periods so the current period (Apr) remains the only Open one.
-- usp_InitialiseReminderState was already called automatically inside usp_OpenPeriod
-- for each period; no standalone call needed here.
IF EXISTS (SELECT 1 FROM KPI.Period WHERE PeriodID = @QtrPeriod0101 AND Status = 'Open')
BEGIN
    DELETE FROM @ClosePeriodResult;
    INSERT INTO @ClosePeriodResult (SubmissionsForceLockedOnClose)
    EXEC App.usp_ClosePeriod @PeriodID = @QtrPeriod0101;
END

IF EXISTS (SELECT 1 FROM KPI.Period WHERE PeriodID = @MthPeriod0202 AND Status = 'Open')
BEGIN
    DELETE FROM @ClosePeriodResult;
    INSERT INTO @ClosePeriodResult (SubmissionsForceLockedOnClose)
    EXEC App.usp_ClosePeriod @PeriodID = @MthPeriod0202;
END

IF EXISTS (SELECT 1 FROM KPI.Period WHERE PeriodID = @BiMthPeriod0202 AND Status = 'Open')
BEGIN
    DELETE FROM @ClosePeriodResult;
    INSERT INTO @ClosePeriodResult (SubmissionsForceLockedOnClose)
    EXEC App.usp_ClosePeriod @PeriodID = @BiMthPeriod0202;
END

IF EXISTS (SELECT 1 FROM KPI.Period WHERE PeriodID = @MthPeriod0203 AND Status = 'Open')
BEGIN
    DELETE FROM @ClosePeriodResult;
    INSERT INTO @ClosePeriodResult (SubmissionsForceLockedOnClose)
    EXEC App.usp_ClosePeriod @PeriodID = @MthPeriod0203;
END

-- ── Tags & KPI Packages ────────────────────────────────────────────────────

PRINT 'Seeding Tags and KPI Packages...';
DECLARE @tagId1 INT, @tagId2 INT, @tagId3 INT;
DECLARE @pkgId1 INT;
DECLARE @kpiIdSafety1 INT, @kpiIdSafety2 INT, @kpiIdQuality1 INT;

-- Insert sample tags if not already present
IF NOT EXISTS (SELECT 1 FROM Dim.Tag WHERE TagCode = 'SAFETY')
BEGIN
    INSERT INTO Dim.Tag (TagCode, TagName, TagDescription, IsActive)
    VALUES ('SAFETY', 'Safety', 'KPIs related to health and safety performance', 1);
END
SELECT @tagId1 = TagId FROM Dim.Tag WHERE TagCode = 'SAFETY';

IF NOT EXISTS (SELECT 1 FROM Dim.Tag WHERE TagCode = 'QUALITY')
BEGIN
    INSERT INTO Dim.Tag (TagCode, TagName, TagDescription, IsActive)
    VALUES ('QUALITY', 'Quality', 'KPIs tracking quality and accuracy metrics', 1);
END
SELECT @tagId2 = TagId FROM Dim.Tag WHERE TagCode = 'QUALITY';

IF NOT EXISTS (SELECT 1 FROM Dim.Tag WHERE TagCode = 'CORE')
BEGIN
    INSERT INTO Dim.Tag (TagCode, TagName, TagDescription, IsActive)
    VALUES ('CORE', 'Core', 'Mandatory core KPIs required at all sites', 1);
END
SELECT @tagId3 = TagId FROM Dim.Tag WHERE TagCode = 'CORE';

-- Tag some KPIs (Safety category)
SELECT @kpiIdSafety1 = KPIID FROM KPI.Definition WHERE KPICode = 'S-001';
SELECT @kpiIdSafety2 = KPIID FROM KPI.Definition WHERE KPICode = 'S-003';
SELECT @kpiIdQuality1 = KPIID FROM KPI.Definition WHERE KPICode = 'Q-001';

IF @tagId1 IS NOT NULL AND @kpiIdSafety1 IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM KPI.KpiTag WHERE KpiId = @kpiIdSafety1 AND TagId = @tagId1)
    INSERT INTO KPI.KpiTag (KpiId, TagId) VALUES (@kpiIdSafety1, @tagId1);

IF @tagId1 IS NOT NULL AND @kpiIdSafety2 IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM KPI.KpiTag WHERE KpiId = @kpiIdSafety2 AND TagId = @tagId1)
    INSERT INTO KPI.KpiTag (KpiId, TagId) VALUES (@kpiIdSafety2, @tagId1);

IF @tagId3 IS NOT NULL AND @kpiIdSafety1 IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM KPI.KpiTag WHERE KpiId = @kpiIdSafety1 AND TagId = @tagId3)
    INSERT INTO KPI.KpiTag (KpiId, TagId) VALUES (@kpiIdSafety1, @tagId3);

IF @tagId2 IS NOT NULL AND @kpiIdQuality1 IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM KPI.KpiTag WHERE KpiId = @kpiIdQuality1 AND TagId = @tagId2)
    INSERT INTO KPI.KpiTag (KpiId, TagId) VALUES (@kpiIdQuality1, @tagId2);

-- Create sample KPI packages (no TagId column — tags via KPI.KpiPackageTag)
DECLARE @pkgId2 INT;

IF NOT EXISTS (SELECT 1 FROM KPI.KpiPackage WHERE PackageCode = 'SAFETY-CORE')
BEGIN
    INSERT INTO KPI.KpiPackage (PackageCode, PackageName, IsActive)
    VALUES ('SAFETY-CORE', 'Core Safety KPIs', 1);
END
SELECT @pkgId1 = KpiPackageId FROM KPI.KpiPackage WHERE PackageCode = 'SAFETY-CORE';

-- Tag SAFETY-CORE with the Safety tag (multi-tag junction)
IF @pkgId1 IS NOT NULL AND @tagId1 IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM KPI.KpiPackageTag WHERE KpiPackageId = @pkgId1 AND TagId = @tagId1)
    INSERT INTO KPI.KpiPackageTag (KpiPackageId, TagId) VALUES (@pkgId1, @tagId1);

-- Add KPIs to SAFETY-CORE
IF @pkgId1 IS NOT NULL AND @kpiIdSafety1 IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM KPI.KpiPackageItem WHERE KpiPackageId = @pkgId1 AND KpiId = @kpiIdSafety1)
    INSERT INTO KPI.KpiPackageItem (KpiPackageId, KpiId) VALUES (@pkgId1, @kpiIdSafety1);

IF @pkgId1 IS NOT NULL AND @kpiIdSafety2 IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM KPI.KpiPackageItem WHERE KpiPackageId = @pkgId1 AND KpiId = @kpiIdSafety2)
    INSERT INTO KPI.KpiPackageItem (KpiPackageId, KpiId) VALUES (@pkgId1, @kpiIdSafety2);

-- A second package with two tags (exercises multi-tag feature)
IF NOT EXISTS (SELECT 1 FROM KPI.KpiPackage WHERE PackageCode = 'QUALITY-CORE')
BEGIN
    INSERT INTO KPI.KpiPackage (PackageCode, PackageName, IsActive)
    VALUES ('QUALITY-CORE', 'Core Quality KPIs', 1);
END
SELECT @pkgId2 = KpiPackageId FROM KPI.KpiPackage WHERE PackageCode = 'QUALITY-CORE';

IF @pkgId2 IS NOT NULL AND @tagId2 IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM KPI.KpiPackageTag WHERE KpiPackageId = @pkgId2 AND TagId = @tagId2)
    INSERT INTO KPI.KpiPackageTag (KpiPackageId, TagId) VALUES (@pkgId2, @tagId2);

IF @pkgId2 IS NOT NULL AND @tagId3 IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM KPI.KpiPackageTag WHERE KpiPackageId = @pkgId2 AND TagId = @tagId3)
    INSERT INTO KPI.KpiPackageTag (KpiPackageId, TagId) VALUES (@pkgId2, @tagId3);

IF @pkgId2 IS NOT NULL AND @kpiIdQuality1 IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM KPI.KpiPackageItem WHERE KpiPackageId = @pkgId2 AND KpiId = @kpiIdQuality1)
    INSERT INTO KPI.KpiPackageItem (KpiPackageId, KpiId) VALUES (@pkgId2, @kpiIdQuality1);

PRINT 'Tags and KPI Packages seeded.';

PRINT 'Seed.sql completed';
