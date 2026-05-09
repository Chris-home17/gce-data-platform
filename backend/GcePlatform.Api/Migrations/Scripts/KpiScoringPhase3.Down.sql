-- ============================================================
-- Migration: KpiScoringPhase3 — Down
-- Restores App.vSubmissionTokenAssignments without KpiWeight + MaxScore.
-- ============================================================

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
                         AND EXISTS
                            (
                                SELECT 1
                                FROM KPI.AssignmentTemplateDropDownOption AS x
                                WHERE x.AssignmentTemplateID = asgn.AssignmentTemplateID
                            )
                        THEN
                            (
                                SELECT STRING_AGG(opt.OptionValue, '||') WITHIN GROUP (ORDER BY opt.SortOrder)
                                FROM KPI.AssignmentTemplateDropDownOption AS opt
                                WHERE opt.AssignmentTemplateID = asgn.AssignmentTemplateID
                            )
                    END,
                    (
                        SELECT STRING_AGG(opt.OptionValue, '||') WITHIN GROUP (ORDER BY opt.SortOrder)
                        FROM KPI.DropDownOption AS opt
                        WHERE opt.KPIID = d.KPIID
                          AND opt.IsActive = 1
                    )
                )
            ELSE NULL
        END                                                     AS DropDownOptionsRaw,
        CAST(asgn.IsRequired AS bit)                            AS IsRequired,
        asgn.TargetValue,
        asgn.ThresholdGreen,
        asgn.ThresholdAmber,
        asgn.ThresholdRed,
        COALESCE(asgn.ThresholdDirection, d.ThresholdDirection) AS EffectiveThresholdDirection,
        asgn.SubmitterGuidance,
        sub.SubmissionID                                        AS SubmissionId,
        sub.SubmissionValue,
        sub.SubmissionText,
        sub.SubmissionBoolean,
        sub.SubmissionNotes,
        sub.LockState,
        CAST(CASE WHEN sub.SubmissionID IS NOT NULL THEN 1 ELSE 0 END AS bit) AS IsSubmitted
    FROM App.vSubmissionTokens AS st
    JOIN KPI.Assignment AS asgn
        ON asgn.PeriodID = st.PeriodId
       AND asgn.IsActive = 1
       AND (
            asgn.OrgUnitId = st.SiteOrgUnitId
            OR
            (
                asgn.OrgUnitId IS NULL
                AND asgn.AccountId = st.AccountId
                AND NOT EXISTS
                (
                    SELECT 1
                    FROM KPI.Assignment AS sa
                    WHERE sa.KPIID = asgn.KPIID
                      AND sa.OrgUnitId = st.SiteOrgUnitId
                      AND sa.PeriodID = st.PeriodId
                      AND sa.IsActive = 1
                      AND (
                            (asgn.AssignmentGroupName IS NULL AND sa.AssignmentGroupName IS NULL)
                            OR sa.AssignmentGroupName = asgn.AssignmentGroupName
                          )
                )
            )
       )
       AND (
             (st.AssignmentGroupName IS NULL AND asgn.AssignmentGroupName IS NULL)
             OR asgn.AssignmentGroupName = st.AssignmentGroupName
           )
    JOIN KPI.Definition AS d
        ON d.KPIID = asgn.KPIID
    LEFT JOIN KPI.AssignmentTemplate AS t
        ON t.AssignmentTemplateID = asgn.AssignmentTemplateID
    LEFT JOIN KPI.Submission AS sub
        ON sub.AssignmentID = asgn.AssignmentID;
GO
