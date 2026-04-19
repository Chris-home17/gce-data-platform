-- ============================================================
-- Migration: TagsAndKpiPackages — Down
-- Reverses the TagsAndKpiPackages migration.
-- ============================================================
GO

-- Drop stored procedures
DROP PROCEDURE IF EXISTS App.usp_SetKpiPackageItems;
GO
DROP PROCEDURE IF EXISTS App.usp_SetKpiPackageActive;
GO
DROP PROCEDURE IF EXISTS App.usp_UpsertKpiPackage;
GO
DROP PROCEDURE IF EXISTS App.usp_SetKpiTags;
GO
DROP PROCEDURE IF EXISTS App.usp_SetTagActive;
GO
DROP PROCEDURE IF EXISTS App.usp_UpsertTag;
GO

-- Restore App.vKpiAssignmentTemplates without KpiPackageId
CREATE OR ALTER VIEW App.vKpiAssignmentTemplates
AS
    SELECT
        t.AssignmentTemplateID,
        t.ExternalId,
        d.KPICode,
        d.KPIName,
        d.Category,
        d.DataType,
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

-- Restore App.vKpiDefinitions without TagsRaw
CREATE OR ALTER VIEW App.vKpiDefinitions
AS
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
        ISNULL(assignments.AssignmentCount, 0) AS AssignmentCount,
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
        WHERE a.KPIID    = d.KPIID
          AND a.IsActive = 1
    ) AS assignments;
GO

-- Drop views
DROP VIEW IF EXISTS App.vKpiPackageItems;
GO
DROP VIEW IF EXISTS App.vKpiPackages;
GO
DROP VIEW IF EXISTS App.vTags;
GO

-- Drop KpiPackageId column from KPI.AssignmentTemplate
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('KPI.AssignmentTemplate')
      AND name = 'KpiPackageId'
)
BEGIN
    ALTER TABLE KPI.AssignmentTemplate DROP CONSTRAINT IF EXISTS FK__AssignmentTemplate__KpiPackageId;
    ALTER TABLE KPI.AssignmentTemplate DROP COLUMN KpiPackageId;
END;
GO

-- Drop tables (in dependency order)
DROP TABLE IF EXISTS KPI.KpiPackageItem;
GO
DROP TABLE IF EXISTS KPI.KpiPackage;
GO
DROP TABLE IF EXISTS KPI.KpiTag;
GO
DROP TABLE IF EXISTS Dim.Tag;
GO
