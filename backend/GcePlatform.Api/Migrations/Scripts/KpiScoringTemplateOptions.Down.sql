-- ============================================================
-- Migration: KpiScoringTemplateOptions — Down
-- ============================================================

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
        ISNULL(instances.GeneratedAssignmentCount, 0) AS GeneratedAssignmentCount,
        t.KpiPackageId,
        pkg.PackageName AS KpiPackageName,
        t.AssignmentGroupName,
        t.KpiWeight,
        t.ScoringMode,
        t.BandPointsGreen,
        t.BandPointsAmber,
        t.BandPointsRed,
        t.BooleanYesPoints,
        t.BooleanNoPoints,
        t.MultiSelectScoreRule,
        t.PenaliseMissingOnScore
    FROM KPI.AssignmentTemplate AS t
    JOIN KPI.Definition         AS d    ON d.KPIID = t.KPIID
    LEFT JOIN KPI.PeriodSchedule AS sched ON sched.PeriodScheduleID = t.PeriodScheduleID
    JOIN Dim.Account            AS acct ON acct.AccountId = t.AccountId
    LEFT JOIN Dim.OrgUnit       AS ou   ON ou.OrgUnitId = t.OrgUnitId
    LEFT JOIN KPI.KpiPackage    AS pkg  ON pkg.KpiPackageId = t.KpiPackageId
    OUTER APPLY
    (
        SELECT COUNT(*) AS GeneratedAssignmentCount
        FROM KPI.Assignment AS a
        JOIN KPI.Period     AS p ON p.PeriodID = a.PeriodID
        WHERE a.KPIID = t.KPIID
          AND a.AccountId = t.AccountId
          AND ((t.OrgUnitId IS NULL AND a.OrgUnitId IS NULL) OR a.OrgUnitId = t.OrgUnitId)
          AND ((t.AssignmentGroupName IS NULL AND a.AssignmentGroupName IS NULL)
                OR a.AssignmentGroupName = t.AssignmentGroupName)
          AND (p.PeriodYear * 100 + p.PeriodMonth) >= (
                COALESCE(t.StartPeriodYear, YEAR(sched.StartDate)) * 100
                + COALESCE(t.StartPeriodMonth, MONTH(sched.StartDate)))
          AND (COALESCE(t.EndPeriodYear, YEAR(sched.EndDate)) IS NULL
                OR (p.PeriodYear * 100 + p.PeriodMonth) <= (
                    COALESCE(t.EndPeriodYear, YEAR(sched.EndDate)) * 100
                    + COALESCE(t.EndPeriodMonth, MONTH(sched.EndDate))))
          AND (DATEDIFF(MONTH,
                    DATEFROMPARTS(YEAR(sched.StartDate), MONTH(sched.StartDate), 1),
                    DATEFROMPARTS(p.PeriodYear, p.PeriodMonth, 1))
              %
              CASE
                  WHEN sched.FrequencyType = 'Monthly' THEN 1
                  WHEN sched.FrequencyType = 'EveryNMonths' THEN sched.FrequencyInterval
                  WHEN sched.FrequencyType = 'Quarterly' THEN 3
                  WHEN sched.FrequencyType = 'SemiAnnual' THEN 6
                  WHEN sched.FrequencyType = 'Annual' THEN 12
                  ELSE 1
              END) = 0
    ) AS instances;
GO

IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_KpiSub_AssignmentScoring'
      AND object_id = OBJECT_ID(N'KPI.Submission')
)
    DROP INDEX IX_KpiSub_AssignmentScoring ON KPI.Submission;
GO
