-- ============================================================
-- Migration: IncludeTimeInRagViews — Down
-- Restores the previous DataType allowlist (no 'Time') in the
-- two RAG-status views. After rolling back, Time KPIs will once
-- again surface no RAG dot in the monitoring UI.
-- ============================================================

CREATE OR ALTER VIEW App.vKpiSubmissions
AS
    SELECT
        sub.SubmissionID,
        sub.ExternalId,
        sub.AssignmentID,
        d.KPICode,
        d.KPIName,
        d.Category,
        d.DataType,
        d.Unit,
        p.PeriodLabel,
        p.PeriodYear,
        p.PeriodMonth,
        p.Status            AS PeriodStatus,
        site.OrgUnitId      AS SiteOrgUnitId,
        site.OrgUnitCode    AS SiteCode,
        site.OrgUnitName    AS SiteName,
        site.CountryCode,
        acct.AccountCode,
        acct.AccountName,
        a.TargetValue,
        a.ThresholdGreen,
        a.ThresholdAmber,
        a.ThresholdRed,
        COALESCE(a.ThresholdDirection, d.ThresholdDirection) AS EffectiveThresholdDirection,
        sub.SubmissionValue,
        sub.SubmissionText,
        sub.SubmissionBoolean,
        sub.SubmissionNotes,
        sub.SourceType,
        submitter.UPN       AS SubmittedByUPN,
        sub.SubmittedAt,
        sub.LockState,
        sub.LockedAt,
        locker.UPN          AS LockedByUPN,
        sub.IsValid,
        sub.ValidationNotes,
        CASE
            WHEN d.DataType NOT IN ('Numeric','Percentage','Currency') THEN NULL
            WHEN sub.SubmissionValue IS NULL                           THEN NULL
            WHEN a.ThresholdGreen IS NULL                              THEN NULL
            WHEN COALESCE(a.ThresholdDirection, d.ThresholdDirection) = 'Higher'
            THEN
                CASE
                    WHEN sub.SubmissionValue >= a.ThresholdGreen THEN 'Green'
                    WHEN sub.SubmissionValue >= a.ThresholdAmber THEN 'Amber'
                    ELSE 'Red'
                END
            WHEN COALESCE(a.ThresholdDirection, d.ThresholdDirection) = 'Lower'
            THEN
                CASE
                    WHEN sub.SubmissionValue <= a.ThresholdGreen THEN 'Green'
                    WHEN sub.SubmissionValue <= a.ThresholdAmber THEN 'Amber'
                    ELSE 'Red'
                END
            ELSE NULL
        END                 AS RAGStatus,
        sub.CreatedOnUtc,
        sub.ModifiedOnUtc
    FROM KPI.Submission AS sub
    JOIN KPI.Assignment AS a    ON a.AssignmentID   = sub.AssignmentID
    JOIN KPI.Definition AS d    ON d.KPIID          = a.KPIID
    JOIN KPI.Period     AS p    ON p.PeriodID        = a.PeriodID
    JOIN Dim.OrgUnit    AS site ON site.OrgUnitId    = a.OrgUnitId
    JOIN Dim.Account    AS acct ON acct.AccountId    = a.AccountId
    LEFT JOIN Sec.[User] AS submitter ON submitter.UserId = sub.SubmittedByPrincipalId
    LEFT JOIN Sec.[User] AS locker    ON locker.UserId    = sub.LockedByPrincipalId;
GO

CREATE OR ALTER VIEW App.vSiteSubmissionDetails
AS
    SELECT
        asgn.OrgUnitId                                           AS SiteOrgUnitId,
        asgn.PeriodID                                            AS PeriodId,
        asgn.AssignmentID                                        AS AssignmentId,
        asgn.ExternalId,
        d.KPICode                                                AS KpiCode,
        d.KPIName                                                AS KpiName,
        COALESCE(t.CustomKpiName, d.KPIName)                     AS EffectiveKpiName,
        d.Category,
        d.DataType,
        CAST(asgn.IsRequired AS bit)                             AS IsRequired,
        asgn.TargetValue,
        asgn.ThresholdGreen,
        asgn.ThresholdAmber,
        asgn.ThresholdRed,
        COALESCE(asgn.ThresholdDirection, d.ThresholdDirection)  AS EffectiveThresholdDirection,
        sub.SubmissionID                                         AS SubmissionId,
        sub.SubmissionValue,
        sub.SubmissionText,
        sub.SubmissionBoolean,
        sub.SubmissionNotes,
        sub.LockState,
        u.UPN                                                    AS SubmittedByUpn,
        sub.SubmittedAt,
        CAST(CASE WHEN sub.SubmissionID IS NOT NULL THEN 1 ELSE 0 END AS bit) AS IsSubmitted,
        CASE
            WHEN d.DataType NOT IN ('Numeric','Percentage','Currency') THEN NULL
            WHEN sub.SubmissionValue IS NULL                           THEN NULL
            WHEN asgn.ThresholdGreen IS NULL                           THEN NULL
            WHEN COALESCE(asgn.ThresholdDirection, d.ThresholdDirection) = 'Higher'
            THEN CASE
                WHEN sub.SubmissionValue >= asgn.ThresholdGreen THEN 'Green'
                WHEN sub.SubmissionValue >= asgn.ThresholdAmber THEN 'Amber'
                ELSE 'Red'
            END
            WHEN COALESCE(asgn.ThresholdDirection, d.ThresholdDirection) = 'Lower'
            THEN CASE
                WHEN sub.SubmissionValue <= asgn.ThresholdGreen THEN 'Green'
                WHEN sub.SubmissionValue <= asgn.ThresholdAmber THEN 'Amber'
                ELSE 'Red'
            END
            ELSE NULL
        END                                                      AS RagStatus,
        asgn.AssignmentGroupName
    FROM KPI.Assignment AS asgn
    JOIN KPI.Definition AS d
        ON d.KPIID = asgn.KPIID
    LEFT JOIN KPI.AssignmentTemplate AS t
        ON t.AssignmentTemplateID = asgn.AssignmentTemplateID
    LEFT JOIN KPI.Submission AS sub
        ON sub.AssignmentID = asgn.AssignmentID
    LEFT JOIN Sec.[User] AS u
        ON u.UserId = sub.SubmittedByPrincipalId
    WHERE asgn.OrgUnitId IS NOT NULL
      AND asgn.IsActive = 1;
GO
