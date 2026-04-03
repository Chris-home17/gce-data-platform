/*
    Test.sql
    Validation queries for RBAC model. Run after Create.sql and Seed.sql.
*/
SET NOCOUNT ON;
GO

-- Financial director should see only DHL Europe hierarchy and finance reports
DECLARE @FinancialDirectorUPN NVARCHAR(320) = 'bruno.martens@fabrikam.com';
PRINT 'Sites available to Bruno Martens (Finance Director, DHL Europe)';
SELECT AccountCode, SiteCode, SiteName, CountryCode
FROM Sec.vAuthorizedSitesDynamic
WHERE UserUPN = @FinancialDirectorUPN
ORDER BY AccountCode, SiteCode;

PRINT 'Reports available to Bruno Martens';
SELECT PackageCode, ReportCode, ReportName
FROM Sec.vAuthorizedReportsDynamic
WHERE UserUPN = @FinancialDirectorUPN
ORDER BY PackageCode, ReportCode;
GO

-- SOC global admin should inherit SOC package across every account
DECLARE @SocAdminUPN NVARCHAR(320) = 'hassan.khan@fabrikam.com';
PRINT 'SOC Global admin report coverage (Hassan Khan)';
SELECT DISTINCT PackageCode, ReportCode, ReportName
FROM Sec.vAuthorizedReportsDynamic
WHERE UserUPN = @SocAdminUPN
ORDER BY PackageCode, ReportCode;

PRINT 'SOC Global admin site coverage sample (top 20 rows)';
SELECT TOP (20) AccountCode, SiteCode, SiteName
FROM Sec.vAuthorizedSitesDynamic
WHERE UserUPN = @SocAdminUPN
ORDER BY AccountCode, SiteCode;
GO

-- Country manager for Belgium should automatically span all accounts
DECLARE @BelgiumManagerUPN NVARCHAR(320) = 'felix.mercier@fabrikam.com';
PRINT 'Sites for Belgium manager (Felix Mercier)';
SELECT AccountCode, SiteCode, SiteName
FROM Sec.vAuthorizedSitesDynamic
WHERE UserUPN = @BelgiumManagerUPN
ORDER BY AccountCode, SiteCode;
GO

-- Site officer should only see assigned site
DECLARE @SiteOfficerUPN NVARCHAR(320) = 'john.doe@fabrikam.com';
PRINT 'Site officer (John Doe) visibility';
SELECT AccountCode, SiteCode, SiteName
FROM Sec.vAuthorizedSitesDynamic
WHERE UserUPN = @SiteOfficerUPN;
GO

-- Validate country across all accounts for Singapore ownership
DECLARE @SingaporeLeadUPN NVARCHAR(320) = 'ravi.patel@fabrikam.com';
PRINT 'Singapore lead (Ravi Patel) coverage';
SELECT AccountCode, SiteCode, SiteName
FROM Sec.vAuthorizedSitesDynamic
WHERE UserUPN = @SingaporeLeadUPN
ORDER BY AccountCode, SiteCode;
GO

-- Overview: each user with packages they can access
PRINT 'User to package entitlement summary';
SELECT u.UserUPN, u.PackageCode, COUNT(DISTINCT u.ReportCode) AS ReportCount
FROM Sec.vAuthorizedReportsDynamic AS u
GROUP BY u.UserUPN, u.PackageCode
ORDER BY u.UserUPN, u.PackageCode;
GO

-- Overview: confirm total site records seeded per account
PRINT 'Site counts per account';
SELECT a.AccountCode, COUNT(*) AS SiteCount
FROM Dim.OrgUnit AS ou
JOIN Dim.Account AS a ON ou.AccountId = a.AccountId
WHERE ou.OrgUnitType = 'Site'
GROUP BY a.AccountCode
ORDER BY a.AccountCode;
GO

PRINT 'Test.sql completed';
