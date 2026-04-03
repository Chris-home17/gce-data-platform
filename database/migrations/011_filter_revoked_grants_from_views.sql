/*
    Migration 011 — Filter revoked grants out of App.vGrants and App.vPackageGrants

    Problem:
        App.RevokeAccess / App.RevokePackageGrant soft-delete by setting RevokedAt,
        but both views had no WHERE clause, so revoked grants continued to appear in
        the user/role detail screens after being revoked.

    Fix:
        Add WHERE RevokedAt IS NULL to both views so only active grants are returned.
        App.vGrantHistory (the audit view) is intentionally left unchanged — it should
        show the full history including revoked rows.
*/

SET NOCOUNT ON;
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
        ISNULL(a.AccountCode, 'ALL')          AS AccountCode,
        ISNULL(a.AccountName, 'All Accounts') AS AccountName,
        ISNULL(ou.OrgUnitType, 'N/A')         AS OrgUnitType,
        ISNULL(ou.OrgUnitCode, 'N/A')         AS OrgUnitCode,
        ISNULL(ou.OrgUnitName, 'N/A')         AS OrgUnitName,
        pag.GrantedOnUtc
    FROM Sec.PrincipalAccessGrant AS pag
    JOIN Sec.Principal AS p  ON p.PrincipalId  = pag.PrincipalId
    LEFT JOIN Dim.Account AS a   ON a.AccountId    = pag.AccountId
    LEFT JOIN Dim.OrgUnit AS ou  ON ou.OrgUnitId   = pag.OrgUnitId
    WHERE pag.RevokedAt IS NULL;
GO

CREATE OR ALTER VIEW App.vPackageGrants
AS
    SELECT
        ppg.PrincipalPackageGrantId,
        p.PrincipalId,
        p.PrincipalType,
        p.PrincipalName,
        ppg.GrantScope,
        ISNULL(pkg.PackageCode, 'ALL')          AS PackageCode,
        ISNULL(pkg.PackageName, 'All Packages') AS PackageName,
        ppg.GrantedOnUtc
    FROM Sec.PrincipalPackageGrant AS ppg
    JOIN Sec.Principal AS p      ON p.PrincipalId  = ppg.PrincipalId
    LEFT JOIN Dim.Package AS pkg ON pkg.PackageId   = ppg.PackageId
    WHERE ppg.RevokedAt IS NULL;
GO

PRINT 'Migration 011: App.vGrants and App.vPackageGrants now exclude revoked grants.';
GO
