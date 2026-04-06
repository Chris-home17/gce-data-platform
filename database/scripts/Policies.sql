-- Seed reusable account role policies for full hierarchy --------------------------
-- Safe to re-run

-- 1. Global Account Director
IF NOT EXISTS (
    SELECT 1
    FROM Sec.AccountRolePolicy
    WHERE RoleCodeTemplate = '{AccountCode}_GAD'
      AND ScopeType = 'NONE'
      AND ExpandPerOrgUnit = 0
)
BEGIN
    INSERT INTO Sec.AccountRolePolicy
        (PolicyName, RoleCodeTemplate, RoleNameTemplate, ScopeType, OrgUnitType, OrgUnitCode, ExpandPerOrgUnit)
    VALUES
        ('Per-account Global Account Director',
         '{AccountCode}_GAD',
         '{AccountName} - Global Account Director',
         'NONE',
         NULL,
         NULL,
         0);
END;
GO

-- 2. Regional Account Director
IF NOT EXISTS (
    SELECT 1
    FROM Sec.AccountRolePolicy
    WHERE RoleCodeTemplate = '{AccountCode}_REG_{OrgUnitCode}'
      AND ScopeType = 'ORGUNIT'
      AND OrgUnitType = 'Region'
      AND OrgUnitCode IS NULL
      AND ExpandPerOrgUnit = 1
)
BEGIN
    INSERT INTO Sec.AccountRolePolicy
        (PolicyName, RoleCodeTemplate, RoleNameTemplate, ScopeType, OrgUnitType, OrgUnitCode, ExpandPerOrgUnit)
    VALUES
        ('Per-account Regional Account Director',
         '{AccountCode}_REG_{OrgUnitCode}',
         '{AccountName} - Regional Account Director - {OrgUnitName}',
         'ORGUNIT',
         'Region',
         NULL,
         1);
END;
GO

-- 3. SubRegional Account Director
IF NOT EXISTS (
    SELECT 1
    FROM Sec.AccountRolePolicy
    WHERE RoleCodeTemplate = '{AccountCode}_SREG_{OrgUnitCode}'
      AND ScopeType = 'ORGUNIT'
      AND OrgUnitType = 'SubRegion'
      AND OrgUnitCode IS NULL
      AND ExpandPerOrgUnit = 1
)
BEGIN
    INSERT INTO Sec.AccountRolePolicy
        (PolicyName, RoleCodeTemplate, RoleNameTemplate, ScopeType, OrgUnitType, OrgUnitCode, ExpandPerOrgUnit)
    VALUES
        ('Per-account SubRegional Account Director',
         '{AccountCode}_SREG_{OrgUnitCode}',
         '{AccountName} - SubRegional Account Director - {OrgUnitName}',
         'ORGUNIT',
         'SubRegion',
         NULL,
         1);
END;
GO

-- 4. Cluster Account Director
IF NOT EXISTS (
    SELECT 1
    FROM Sec.AccountRolePolicy
    WHERE RoleCodeTemplate = '{AccountCode}_CLUSTER_{OrgUnitCode}'
      AND ScopeType = 'ORGUNIT'
      AND OrgUnitType = 'Cluster'
      AND OrgUnitCode IS NULL
      AND ExpandPerOrgUnit = 1
)
BEGIN
    INSERT INTO Sec.AccountRolePolicy
        (PolicyName, RoleCodeTemplate, RoleNameTemplate, ScopeType, OrgUnitType, OrgUnitCode, ExpandPerOrgUnit)
    VALUES
        ('Per-account Cluster Account Director',
         '{AccountCode}_CLUSTER_{OrgUnitCode}',
         '{AccountName} - Cluster Account Director - {OrgUnitName}',
         'ORGUNIT',
         'Cluster',
         NULL,
         1);
END;
GO

-- 5. Country Account Director
IF NOT EXISTS (
    SELECT 1
    FROM Sec.AccountRolePolicy
    WHERE RoleCodeTemplate = '{AccountCode}_COUNTRY_{OrgUnitCode}'
      AND ScopeType = 'ORGUNIT'
      AND OrgUnitType = 'Country'
      AND OrgUnitCode IS NULL
      AND ExpandPerOrgUnit = 1
)
BEGIN
    INSERT INTO Sec.AccountRolePolicy
        (PolicyName, RoleCodeTemplate, RoleNameTemplate, ScopeType, OrgUnitType, OrgUnitCode, ExpandPerOrgUnit)
    VALUES
        ('Per-account Country Account Director',
         '{AccountCode}_COUNTRY_{OrgUnitCode}',
         '{AccountName} - Country Account Director - {OrgUnitName}',
         'ORGUNIT',
         'Country',
         NULL,
         1);
END;
GO

-- 6. Area Manager
IF NOT EXISTS (
    SELECT 1
    FROM Sec.AccountRolePolicy
    WHERE RoleCodeTemplate = '{AccountCode}_AREA_{OrgUnitCode}'
      AND ScopeType = 'ORGUNIT'
      AND OrgUnitType = 'Area'
      AND OrgUnitCode IS NULL
      AND ExpandPerOrgUnit = 1
)
BEGIN
    INSERT INTO Sec.AccountRolePolicy
        (PolicyName, RoleCodeTemplate, RoleNameTemplate, ScopeType, OrgUnitType, OrgUnitCode, ExpandPerOrgUnit)
    VALUES
        ('Per-account Area Manager',
         '{AccountCode}_AREA_{OrgUnitCode}',
         '{AccountName} - Area Manager - {OrgUnitName}',
         'ORGUNIT',
         'Area',
         NULL,
         1);
END;
GO

-- 7. Branch Manager
IF NOT EXISTS (
    SELECT 1
    FROM Sec.AccountRolePolicy
    WHERE RoleCodeTemplate = '{AccountCode}_BRANCH_{OrgUnitCode}'
      AND ScopeType = 'ORGUNIT'
      AND OrgUnitType = 'Branch'
      AND OrgUnitCode IS NULL
      AND ExpandPerOrgUnit = 1
)
BEGIN
    INSERT INTO Sec.AccountRolePolicy
        (PolicyName, RoleCodeTemplate, RoleNameTemplate, ScopeType, OrgUnitType, OrgUnitCode, ExpandPerOrgUnit)
    VALUES
        ('Per-account Branch Manager',
         '{AccountCode}_BRANCH_{OrgUnitCode}',
         '{AccountName} - Branch Manager - {OrgUnitName}',
         'ORGUNIT',
         'Branch',
         NULL,
         1);
END;
GO

-- 8. Site Manager
IF NOT EXISTS (
    SELECT 1
    FROM Sec.AccountRolePolicy
    WHERE RoleCodeTemplate = '{AccountCode}_SITE_{OrgUnitCode}'
      AND ScopeType = 'ORGUNIT'
      AND OrgUnitType = 'Site'
      AND OrgUnitCode IS NULL
      AND ExpandPerOrgUnit = 1
)
BEGIN
    INSERT INTO Sec.AccountRolePolicy
        (PolicyName, RoleCodeTemplate, RoleNameTemplate, ScopeType, OrgUnitType, OrgUnitCode, ExpandPerOrgUnit)
    VALUES
        ('Per-account Site Manager',
         '{AccountCode}_SITE_{OrgUnitCode}',
         '{AccountName} - Site Manager - {OrgUnitName}',
         'ORGUNIT',
         'Site',
         NULL,
         1);
END;
GO

-- Apply to existing accounts after seeding policies
DECLARE @AccountCode NVARCHAR(50);

DECLARE AccountCur CURSOR LOCAL FAST_FORWARD FOR
    SELECT AccountCode
    FROM Dim.Account;

OPEN AccountCur;
FETCH NEXT FROM AccountCur INTO @AccountCode;

WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC App.ApplyAccountPolicies
        @AccountCode   = @AccountCode,
        @ApplyAccess   = 1,
        @ApplyPackages = 0;

    FETCH NEXT FROM AccountCur INTO @AccountCode;
END

CLOSE AccountCur;
DEALLOCATE AccountCur;
GO
