-- ============================================================
-- Migration: KpiSubmissionValidation — Down
-- Removes validation rule columns + related snapshot columns;
-- restores procs and views to their pre-validation bodies.
--
-- Down-migration consumers needing strict revert of the four procs
-- (usp_AssignKpi, usp_UpsertKpiAssignmentTemplate,
-- usp_MaterializeKpiAssignmentTemplates, usp_SubmitKpi) should
-- re-run the prior migration's Up.sql to restore those exactly;
-- this Down.sql drops the columns the procs reference, so any
-- subsequent INSERT through the still-validation-aware procs would
-- fail at runtime — that is the expected behaviour for a rollback.
-- ============================================================

-- Restore vSubmissionTokenAssignments without validation columns.
CREATE OR ALTER VIEW App.vSubmissionTokenAssignments
AS
    SELECT
        st.TokenId,
        asgn.AssignmentID                                       AS AssignmentId,
        asgn.ExternalId,
        d.KPICode                                               AS KpiCode,
        d.KPIName                                               AS KpiName,
        COALESCE(t.CustomKpiName,        d.KPIName)             AS EffectiveKpiName,
        COALESCE(t.CustomKpiDescription, d.KPIDescription)      AS EffectiveKpiDescription,
        d.Category,
        d.DataType,
        CAST(d.AllowMultiValue AS bit)                          AS AllowMultiValue,
        CASE
            WHEN d.DataType = 'DropDown' THEN
                COALESCE(
                    CASE
                        WHEN asgn.AssignmentTemplateID IS NOT NULL
                         AND EXISTS (
                                SELECT 1
                                FROM KPI.AssignmentTemplateDropDownOption AS x
                                WHERE x.AssignmentTemplateID = asgn.AssignmentTemplateID)
                        THEN (
                                SELECT STRING_AGG(opt.OptionValue, '||') WITHIN GROUP (ORDER BY opt.SortOrder)
                                FROM KPI.AssignmentTemplateDropDownOption AS opt
                                WHERE opt.AssignmentTemplateID = asgn.AssignmentTemplateID)
                    END,
                    (
                        SELECT STRING_AGG(opt.OptionValue, '||') WITHIN GROUP (ORDER BY opt.SortOrder)
                        FROM KPI.DropDownOption AS opt
                        WHERE opt.KPIID = d.KPIID AND opt.IsActive = 1
                    )
                )
            ELSE NULL
        END                                                     AS DropDownOptionsRaw,
        CAST(asgn.IsRequired AS bit)                            AS IsRequired,
        asgn.TargetValue, asgn.ThresholdGreen, asgn.ThresholdAmber, asgn.ThresholdRed,
        COALESCE(asgn.ThresholdDirection, d.ThresholdDirection) AS EffectiveThresholdDirection,
        asgn.SubmitterGuidance,
        sub.SubmissionID AS SubmissionId, sub.SubmissionValue, sub.SubmissionText,
        sub.SubmissionBoolean, sub.SubmissionNotes, sub.LockState,
        CAST(CASE WHEN sub.SubmissionID IS NOT NULL THEN 1 ELSE 0 END AS bit) AS IsSubmitted,
        asgn.KpiWeight,
        CAST(100.0 AS DECIMAL(9,4))                             AS MaxScore
    FROM App.vSubmissionTokens AS st
    JOIN KPI.Assignment AS asgn
        ON asgn.PeriodID = st.PeriodId
       AND asgn.IsActive = 1
       AND (asgn.OrgUnitId = st.SiteOrgUnitId
            OR (asgn.OrgUnitId IS NULL AND asgn.AccountId = st.AccountId
                AND NOT EXISTS (SELECT 1 FROM KPI.Assignment sa
                    WHERE sa.KPIID = asgn.KPIID AND sa.OrgUnitId = st.SiteOrgUnitId
                      AND sa.PeriodID = st.PeriodId AND sa.IsActive = 1
                      AND ((asgn.AssignmentGroupName IS NULL AND sa.AssignmentGroupName IS NULL)
                            OR sa.AssignmentGroupName = asgn.AssignmentGroupName))))
       AND ((st.AssignmentGroupName IS NULL AND asgn.AssignmentGroupName IS NULL)
             OR asgn.AssignmentGroupName = st.AssignmentGroupName)
    JOIN KPI.Definition AS d ON d.KPIID = asgn.KPIID
    LEFT JOIN KPI.AssignmentTemplate AS t ON t.AssignmentTemplateID = asgn.AssignmentTemplateID
    LEFT JOIN KPI.Submission AS sub ON sub.AssignmentID = asgn.AssignmentID;
GO

-- Restore vKpiAssignmentTemplates without validation columns.
CREATE OR ALTER VIEW App.vKpiAssignmentTemplates
AS
    SELECT
        t.AssignmentTemplateID, t.ExternalId, d.KPICode, d.KPIName, d.Category, d.DataType,
        sched.PeriodScheduleID, sched.ScheduleName, sched.FrequencyType, sched.FrequencyInterval,
        acct.AccountId, acct.AccountCode, acct.AccountName,
        t.OrgUnitId, ou.OrgUnitCode AS SiteCode, ou.OrgUnitName AS SiteName,
        CASE WHEN t.OrgUnitId IS NULL THEN 1 ELSE 0 END AS IsAccountWide,
        t.StartPeriodYear, t.StartPeriodMonth, t.EndPeriodYear, t.EndPeriodMonth,
        t.IsRequired, t.TargetValue, t.ThresholdGreen, t.ThresholdAmber, t.ThresholdRed,
        COALESCE(t.ThresholdDirection, d.ThresholdDirection) AS EffectiveThresholdDirection,
        t.SubmitterGuidance, t.CustomKpiName, t.CustomKpiDescription,
        COALESCE(t.CustomKpiName,        d.KPIName)        AS EffectiveKpiName,
        COALESCE(t.CustomKpiDescription, d.KPIDescription) AS EffectiveKpiDescription,
        t.IsActive, ISNULL(instances.GeneratedAssignmentCount, 0) AS GeneratedAssignmentCount,
        t.KpiPackageId, pkg.PackageName AS KpiPackageName, t.AssignmentGroupName,
        t.KpiWeight, t.ScoringMode,
        t.BandPointsGreen, t.BandPointsAmber, t.BandPointsRed,
        t.BooleanYesPoints, t.BooleanNoPoints,
        t.MultiSelectScoreRule, t.PenaliseMissingOnScore,
        t.CategoryWeightSnapshot,
        (
            SELECT opt.OptionValue AS [value], opt.Points AS [points], opt.SortOrder AS [sortOrder]
            FROM KPI.AssignmentTemplateDropDownOption AS opt
            WHERE opt.AssignmentTemplateID = t.AssignmentTemplateID
            ORDER BY opt.SortOrder, opt.OptionValue
            FOR JSON PATH
        ) AS OptionPointsRaw
    FROM KPI.AssignmentTemplate AS t
    JOIN KPI.Definition         AS d    ON d.KPIID = t.KPIID
    LEFT JOIN KPI.PeriodSchedule AS sched ON sched.PeriodScheduleID = t.PeriodScheduleID
    JOIN Dim.Account            AS acct ON acct.AccountId = t.AccountId
    LEFT JOIN Dim.OrgUnit       AS ou   ON ou.OrgUnitId = t.OrgUnitId
    LEFT JOIN KPI.KpiPackage    AS pkg  ON pkg.KpiPackageId = t.KpiPackageId
    OUTER APPLY (
        SELECT COUNT(*) AS GeneratedAssignmentCount
        FROM KPI.Assignment AS a
        JOIN KPI.Period     AS p ON p.PeriodID = a.PeriodID
        WHERE a.KPIID = t.KPIID AND a.AccountId = t.AccountId
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
              CASE WHEN sched.FrequencyType = 'Monthly' THEN 1
                   WHEN sched.FrequencyType = 'EveryNMonths' THEN sched.FrequencyInterval
                   WHEN sched.FrequencyType = 'Quarterly' THEN 3
                   WHEN sched.FrequencyType = 'SemiAnnual' THEN 6
                   WHEN sched.FrequencyType = 'Annual' THEN 12
                   ELSE 1 END) = 0
    ) AS instances;
GO

-- Drop check constraints
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_KpiAsgn_ValidationPrecision' AND parent_object_id = OBJECT_ID(N'KPI.Assignment'))
    ALTER TABLE KPI.Assignment DROP CONSTRAINT CK_KpiAsgn_ValidationPrecision;
GO
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_KpiTpl_ValidationPrecision' AND parent_object_id = OBJECT_ID(N'KPI.AssignmentTemplate'))
    ALTER TABLE KPI.AssignmentTemplate DROP CONSTRAINT CK_KpiTpl_ValidationPrecision;
GO

-- Drop columns
DECLARE @sql NVARCHAR(MAX);
DECLARE @cols TABLE (tbl SYSNAME, col SYSNAME);
INSERT @cols VALUES
    ('KPI.Submission','SubmittedValidationMessage'),
    ('KPI.Submission','SubmittedValidationRegex'),
    ('KPI.Submission','SubmittedValidationPrecision'),
    ('KPI.Submission','SubmittedValidationMaxValue'),
    ('KPI.Submission','SubmittedValidationMinValue'),
    ('KPI.Assignment','ValidationMessage'),
    ('KPI.Assignment','ValidationRegex'),
    ('KPI.Assignment','ValidationPrecision'),
    ('KPI.Assignment','ValidationMaxValue'),
    ('KPI.Assignment','ValidationMinValue'),
    ('KPI.AssignmentTemplate','ValidationMessage'),
    ('KPI.AssignmentTemplate','ValidationRegex'),
    ('KPI.AssignmentTemplate','ValidationPrecision'),
    ('KPI.AssignmentTemplate','ValidationMaxValue'),
    ('KPI.AssignmentTemplate','ValidationMinValue');

DECLARE @tbl SYSNAME, @col SYSNAME;
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT tbl, col FROM @cols;
OPEN c; FETCH NEXT FROM c INTO @tbl, @col;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF COL_LENGTH(@tbl, @col) IS NOT NULL
    BEGIN
        SET @sql = 'ALTER TABLE ' + @tbl + ' DROP COLUMN ' + QUOTENAME(@col) + ';';
        EXEC sp_executesql @sql;
    END
    FETCH NEXT FROM c INTO @tbl, @col;
END
CLOSE c; DEALLOCATE c;
GO
