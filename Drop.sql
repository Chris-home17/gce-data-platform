/*
    Drop.sql
    Removes all RBAC objects created by Create.sql. Safe to re-run.
    Drop order: App views → Sec views → functions → procedures → tables → schemas
*/
SET NOCOUNT ON;
GO

-- Drop App views first (depend on Sec views) --------------------------------------
IF OBJECT_ID('App.vCoverageSummary', 'V') IS NOT NULL
    DROP VIEW App.vCoverageSummary;
GO
IF OBJECT_ID('App.vPrincipals', 'V') IS NOT NULL
    DROP VIEW App.vPrincipals;
GO
IF OBJECT_ID('App.vSourceMappings', 'V') IS NOT NULL
    DROP VIEW App.vSourceMappings;
GO
IF OBJECT_ID('App.vOrgUnits', 'V') IS NOT NULL
    DROP VIEW App.vOrgUnits;
GO
IF OBJECT_ID('App.vDelegations', 'V') IS NOT NULL
    DROP VIEW App.vDelegations;
GO
IF OBJECT_ID('App.vPackageGrants', 'V') IS NOT NULL
    DROP VIEW App.vPackageGrants;
GO
IF OBJECT_ID('App.vGrants', 'V') IS NOT NULL
    DROP VIEW App.vGrants;
GO
IF OBJECT_ID('App.vPackagePolicies', 'V') IS NOT NULL
    DROP VIEW App.vPackagePolicies;
GO
IF OBJECT_ID('App.vAccessPolicies', 'V') IS NOT NULL
    DROP VIEW App.vAccessPolicies;
GO
IF OBJECT_ID('App.vUserRoles', 'V') IS NOT NULL
    DROP VIEW App.vUserRoles;
GO
IF OBJECT_ID('App.vUsers', 'V') IS NOT NULL
    DROP VIEW App.vUsers;
GO
IF OBJECT_ID('App.vRoleMembers', 'V') IS NOT NULL
    DROP VIEW App.vRoleMembers;
GO
IF OBJECT_ID('App.vRoles', 'V') IS NOT NULL
    DROP VIEW App.vRoles;
GO
IF OBJECT_ID('App.vBiReports', 'V') IS NOT NULL
    DROP VIEW App.vBiReports;
GO
IF OBJECT_ID('App.vPackages', 'V') IS NOT NULL
    DROP VIEW App.vPackages;
GO
IF OBJECT_ID('App.vAccounts', 'V') IS NOT NULL
    DROP VIEW App.vAccounts;
GO

-- Drop Sec views ------------------------------------------------------------------
IF OBJECT_ID('Sec.vUserAccessGaps', 'V') IS NOT NULL
    DROP VIEW Sec.vUserAccessGaps;
GO
IF OBJECT_ID('Sec.vUserCoverageSummary', 'V') IS NOT NULL
    DROP VIEW Sec.vUserCoverageSummary;
GO
IF OBJECT_ID('Sec.vPrincipalEffectiveAccess', 'V') IS NOT NULL
    DROP VIEW Sec.vPrincipalEffectiveAccess;
GO
IF OBJECT_ID('Sec.vAuthorizedReportsDynamic', 'V') IS NOT NULL
    DROP VIEW Sec.vAuthorizedReportsDynamic;
GO
IF OBJECT_ID('Sec.vAuthorizedSitesDynamic', 'V') IS NOT NULL
    DROP VIEW Sec.vAuthorizedSitesDynamic;
GO
IF OBJECT_ID('Sec.vPrincipalPackageAccess', 'V') IS NOT NULL
    DROP VIEW Sec.vPrincipalPackageAccess;
GO
IF OBJECT_ID('Sec.vUserGrantPrincipals', 'V') IS NOT NULL
    DROP VIEW Sec.vUserGrantPrincipals;
GO

-- Drop scalar functions -----------------------------------------------------------
IF OBJECT_ID('Sec.fnResolvePrincipalId', 'FN') IS NOT NULL
    DROP FUNCTION Sec.fnResolvePrincipalId;
GO
IF OBJECT_ID('Sec.fnCanAdministerScope', 'FN') IS NOT NULL
    DROP FUNCTION Sec.fnCanAdministerScope;
GO

-- Drop App stored procedures ------------------------------------------------------
IF OBJECT_ID('App.GetUserEffectiveAccess', 'P') IS NOT NULL
    DROP PROCEDURE App.GetUserEffectiveAccess;
GO
IF OBJECT_ID('App.RevokePackageGrant', 'P') IS NOT NULL
    DROP PROCEDURE App.RevokePackageGrant;
GO
IF OBJECT_ID('App.RevokeAccess', 'P') IS NOT NULL
    DROP PROCEDURE App.RevokeAccess;
GO
IF OBJECT_ID('App.GrantAccess', 'P') IS NOT NULL
    DROP PROCEDURE App.GrantAccess;
GO
IF OBJECT_ID('App.UpsertOrgUnitSourceMap', 'P') IS NOT NULL
    DROP PROCEDURE App.UpsertOrgUnitSourceMap;
GO
IF OBJECT_ID('App.RemoveRoleMember', 'P') IS NOT NULL
    DROP PROCEDURE App.RemoveRoleMember;
GO
IF OBJECT_ID('App.AddRoleMember', 'P') IS NOT NULL
    DROP PROCEDURE App.AddRoleMember;
GO
IF OBJECT_ID('App.AssignReportToPackage', 'P') IS NOT NULL
    DROP PROCEDURE App.AssignReportToPackage;
GO
IF OBJECT_ID('App.UpsertBiReport', 'P') IS NOT NULL
    DROP PROCEDURE App.UpsertBiReport;
GO
IF OBJECT_ID('App.UpsertPackage', 'P') IS NOT NULL
    DROP PROCEDURE App.UpsertPackage;
GO
IF OBJECT_ID('App.SecurityHealthCheck', 'P') IS NOT NULL
    DROP PROCEDURE App.SecurityHealthCheck;
GO
IF OBJECT_ID('App.ApplyAccountPolicies', 'P') IS NOT NULL
    DROP PROCEDURE App.ApplyAccountPolicies;
GO
IF OBJECT_ID('App.UpsertAccount', 'P') IS NOT NULL
    DROP PROCEDURE App.UpsertAccount;
GO
IF OBJECT_ID('App.UpsertRole', 'P') IS NOT NULL
    DROP PROCEDURE App.UpsertRole;
GO
IF OBJECT_ID('App.UpsertUser', 'P') IS NOT NULL
    DROP PROCEDURE App.UpsertUser;
GO
IF OBJECT_ID('App.CreateOrEnsureSitePath', 'P') IS NOT NULL
    DROP PROCEDURE App.CreateOrEnsureSitePath;
GO
IF OBJECT_ID('App.InsertOrgUnit', 'P') IS NOT NULL
    DROP PROCEDURE App.InsertOrgUnit;
GO

-- Drop Sec stored procedures ------------------------------------------------------
IF OBJECT_ID('Sec.GrantCountryAllAccounts', 'P') IS NOT NULL
    DROP PROCEDURE Sec.GrantCountryAllAccounts;
GO
IF OBJECT_ID('Sec.RevokeDelegation', 'P') IS NOT NULL
    DROP PROCEDURE Sec.RevokeDelegation;
GO
IF OBJECT_ID('Sec.GrantDelegation', 'P') IS NOT NULL
    DROP PROCEDURE Sec.GrantDelegation;
GO
IF OBJECT_ID('Sec.GrantAllAccounts', 'P') IS NOT NULL
    DROP PROCEDURE Sec.GrantAllAccounts;
GO
IF OBJECT_ID('Sec.GrantPathPrefix', 'P') IS NOT NULL
    DROP PROCEDURE Sec.GrantPathPrefix;
GO
IF OBJECT_ID('Sec.GrantFullAccount', 'P') IS NOT NULL
    DROP PROCEDURE Sec.GrantFullAccount;
GO
IF OBJECT_ID('Sec.GrantGlobal', 'P') IS NOT NULL
    DROP PROCEDURE Sec.GrantGlobal;
GO
IF OBJECT_ID('Sec.GrantGlobalAllPackages', 'P') IS NOT NULL
    DROP PROCEDURE Sec.GrantGlobalAllPackages;
GO

-- Drop tables (child to parent) ---------------------------------------------------
IF OBJECT_ID('Sec.PrincipalDelegation', 'U') IS NOT NULL
    DROP TABLE Sec.PrincipalDelegation;
GO
IF OBJECT_ID('Sec.AccountPackagePolicy', 'U') IS NOT NULL
    DROP TABLE Sec.AccountPackagePolicy;
GO
IF OBJECT_ID('Sec.AccountAccessPolicy', 'U') IS NOT NULL
    DROP TABLE Sec.AccountAccessPolicy;
GO
IF OBJECT_ID('Sec.AccountRolePolicy', 'U') IS NOT NULL
    DROP TABLE Sec.AccountRolePolicy;
GO
IF OBJECT_ID('Sec.PrincipalPackageGrant', 'U') IS NOT NULL
    DROP TABLE Sec.PrincipalPackageGrant;
GO
IF OBJECT_ID('Sec.PrincipalAccessGrant', 'U') IS NOT NULL
    DROP TABLE Sec.PrincipalAccessGrant;
GO
IF OBJECT_ID('Dim.OrgUnitSourceMap', 'U') IS NOT NULL
    DROP TABLE Dim.OrgUnitSourceMap;
GO
IF OBJECT_ID('Sec.RoleMembership', 'U') IS NOT NULL
    DROP TABLE Sec.RoleMembership;
GO
IF OBJECT_ID('Sec.Role', 'U') IS NOT NULL
    DROP TABLE Sec.Role;
GO
IF OBJECT_ID('Sec.[User]', 'U') IS NOT NULL
    DROP TABLE Sec.[User];
GO
IF OBJECT_ID('Sec.Principal', 'U') IS NOT NULL
    DROP TABLE Sec.Principal;
GO
IF OBJECT_ID('Dim.BiReportPackage', 'U') IS NOT NULL
    DROP TABLE Dim.BiReportPackage;
GO
IF OBJECT_ID('Dim.BiReport', 'U') IS NOT NULL
    DROP TABLE Dim.BiReport;
GO
IF OBJECT_ID('Dim.Package', 'U') IS NOT NULL
    DROP TABLE Dim.Package;
GO
IF OBJECT_ID('Dim.OrgUnit', 'U') IS NOT NULL
    DROP TABLE Dim.OrgUnit;
GO
IF OBJECT_ID('Dim.Account', 'U') IS NOT NULL
    DROP TABLE Dim.Account;
GO

-- Finally drop schemas ------------------------------------------------------------
IF EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'App')
    EXEC ('DROP SCHEMA App');
GO
IF EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Sec')
    EXEC ('DROP SCHEMA Sec');
GO
IF EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Dim')
    EXEC ('DROP SCHEMA Dim');
GO

PRINT 'Drop.sql completed';