-- ============================================================
-- Migration: SplitKpiPermissions — Up
-- Replaces the coarse `kpi.manage` permission with two codes:
--   * kpi.admin  — platform KPI authoring (library, periods, packages).
--                  A strict superset; admins bypass every kpi.assign check.
--   * kpi.assign — account-scoped KPI work (assignment templates, materialize,
--                  package->templates, submission unlock).
--
-- Legacy rows are hard-deleted. The platform is not yet in production; a clean
-- break is preferred over an alias. Existing App.PlatformRolePermission rows
-- that reference `kpi.manage` are removed too — affected roles must be
-- re-granted via the admin UI.
--
-- Safe to re-run: guarded by IF NOT EXISTS / IF EXISTS.
-- ============================================================

IF NOT EXISTS (SELECT 1 FROM App.PlatformPermission WHERE PermissionCode = 'kpi.admin')
    INSERT INTO App.PlatformPermission (PermissionCode, DisplayName, Description, Category, SortOrder)
    VALUES ('kpi.admin', 'Manage KPI Library',
            'Full KPI administration: library, periods, packages, and all assignment operations.',
            'KPI', 50);
GO

IF NOT EXISTS (SELECT 1 FROM App.PlatformPermission WHERE PermissionCode = 'kpi.assign')
    INSERT INTO App.PlatformPermission (PermissionCode, DisplayName, Description, Category, SortOrder)
    VALUES ('kpi.assign', 'Manage KPI Assignments',
            'Assign KPIs to sites and manage account-level KPI submissions.',
            'KPI', 51);
GO

-- Clean up any PlatformRolePermission rows referencing the retired code
-- before we drop the parent (FK would block the delete otherwise).
DELETE rp
FROM App.PlatformRolePermission AS rp
JOIN App.PlatformPermission AS p ON p.PermissionId = rp.PermissionId
WHERE p.PermissionCode = 'kpi.manage';
GO

IF EXISTS (SELECT 1 FROM App.PlatformPermission WHERE PermissionCode = 'kpi.manage')
    DELETE FROM App.PlatformPermission WHERE PermissionCode = 'kpi.manage';
GO
