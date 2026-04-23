-- ============================================================
-- Migration: SplitKpiPermissions — Down
-- Re-inserts the legacy kpi.manage row and removes the two new codes
-- (including any PlatformRolePermission rows referencing them).
-- ============================================================

IF NOT EXISTS (SELECT 1 FROM App.PlatformPermission WHERE PermissionCode = 'kpi.manage')
    INSERT INTO App.PlatformPermission (PermissionCode, DisplayName, Description, Category, SortOrder)
    VALUES ('kpi.manage', 'Manage KPI',
            'Manage KPI library, schedules, assignments, and periods.',
            'KPI', 50);
GO

DELETE rp
FROM App.PlatformRolePermission AS rp
JOIN App.PlatformPermission AS p ON p.PermissionId = rp.PermissionId
WHERE p.PermissionCode IN ('kpi.admin', 'kpi.assign');
GO

IF EXISTS (SELECT 1 FROM App.PlatformPermission WHERE PermissionCode = 'kpi.admin')
    DELETE FROM App.PlatformPermission WHERE PermissionCode = 'kpi.admin';
GO

IF EXISTS (SELECT 1 FROM App.PlatformPermission WHERE PermissionCode = 'kpi.assign')
    DELETE FROM App.PlatformPermission WHERE PermissionCode = 'kpi.assign';
GO
