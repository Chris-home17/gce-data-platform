-- ============================================================
-- Migration: SnapshotThresholdsOnSubmission — Down
-- Reverts to live-thresholds RAG and removes the per-submission
-- snapshot columns. Existing submitted rows lose their immutability:
-- afterwards any threshold edit re-scores history.
-- ============================================================

IF OBJECT_ID('App.usp_CascadeAssignmentTemplateThresholds', 'P') IS NOT NULL
    DROP PROCEDURE App.usp_CascadeAssignmentTemplateThresholds;
GO

-- ============================================================
-- usp_SubmitKpi — restore the pre-snapshot version (no SubmittedThreshold* writes)
-- ============================================================

CREATE OR ALTER PROCEDURE App.usp_SubmitKpi
    @AssignmentExternalId   UNIQUEIDENTIFIER,
    @SubmitterUPN           NVARCHAR(320),
    @SubmissionValue        DECIMAL(18,4)   = NULL,
    @SubmissionText         NVARCHAR(1000)  = NULL,
    @SubmissionBoolean      BIT             = NULL,
    @SubmissionNotes        NVARCHAR(500)   = NULL,
    @SourceType             NVARCHAR(20)    = 'Manual',
    @LockOnSubmit           BIT             = 1,
    @ChangeReason           NVARCHAR(500)   = NULL,
    @BypassLock             BIT             = 0,
    @SubmissionID           INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRAN;

    DECLARE @AssignmentID INT;
    DECLARE @PeriodID     INT;
    DECLARE @KPIID        INT;

    SELECT
        @AssignmentID = a.AssignmentID,
        @PeriodID     = a.PeriodID,
        @KPIID        = a.KPIID
    FROM KPI.Assignment AS a
    WHERE a.ExternalId = @AssignmentExternalId
      AND a.IsActive   = 1;

    IF @AssignmentID IS NULL
    BEGIN
        ROLLBACK;
        THROW 50201, 'Assignment not found or inactive.', 1;
    END

    DECLARE @PeriodStatus NVARCHAR(20);
    DECLARE @CloseDate    DATE;

    SELECT
        @PeriodStatus = Status,
        @CloseDate    = SubmissionCloseDate
    FROM KPI.Period
    WHERE PeriodID = @PeriodID;

    IF @BypassLock = 0 AND @PeriodStatus <> 'Open'
    BEGIN
        ROLLBACK;
        THROW 50202, 'Submissions are not accepted: period is not Open.', 1;
    END

    IF @BypassLock = 0 AND CAST(SYSUTCDATETIME() AS DATE) > @CloseDate
    BEGIN
        ROLLBACK;
        THROW 50203, 'Submissions are not accepted: the submission window has closed.', 1;
    END

    DECLARE @SubmitterPrincipalId INT = (
        SELECT UserId FROM Sec.[User] WHERE UPN = @SubmitterUPN
    );
    IF @SubmitterPrincipalId IS NULL
    BEGIN
        ROLLBACK;
        THROW 50204, 'Submitter user not found.', 1;
    END

    DECLARE @DefinitionSnapshot NVARCHAR(MAX);
    SELECT @DefinitionSnapshot = (
        SELECT
            d.KPICode, d.KPIName, d.KPIDescription,
            COALESCE(tmpl.CustomKpiName, d.KPIName)               AS EffectiveKpiName,
            COALESCE(tmpl.CustomKpiDescription, d.KPIDescription) AS EffectiveKpiDescription,
            d.Category, d.Unit, d.DataType, d.AllowMultiValue, d.CollectionType,
            a.IsRequired, a.TargetValue,
            a.ThresholdGreen, a.ThresholdAmber, a.ThresholdRed,
            COALESCE(a.ThresholdDirection, d.ThresholdDirection)  AS EffectiveThresholdDirection,
            a.SubmitterGuidance,
            JSON_QUERY(opts.OptionsJson) AS DropDownOptions
        FROM KPI.Assignment AS a
        JOIN KPI.Definition AS d ON d.KPIID = a.KPIID
        LEFT JOIN KPI.AssignmentTemplate AS tmpl ON tmpl.AssignmentTemplateID = a.AssignmentTemplateID
        OUTER APPLY (
            SELECT CASE WHEN d.DataType = 'DropDown' THEN (
                SELECT opt.OptionValue, opt.SortOrder
                FROM KPI.DropDownOption AS opt
                WHERE opt.KPIID = d.KPIID AND opt.IsActive = 1
                ORDER BY opt.SortOrder
                FOR JSON PATH
            ) ELSE NULL END AS OptionsJson
        ) AS opts
        WHERE a.AssignmentID = @AssignmentID
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );

    DECLARE @ExistingSubmissionID  INT;
    DECLARE @ExistingLockState     NVARCHAR(25);

    SELECT
        @ExistingSubmissionID = SubmissionID,
        @ExistingLockState    = LockState
    FROM KPI.Submission
    WHERE AssignmentID = @AssignmentID;

    IF @ExistingSubmissionID IS NOT NULL AND @ExistingLockState <> 'Unlocked' AND @BypassLock = 0
    BEGIN
        ROLLBACK;
        THROW 50205, 'This KPI submission is locked and cannot be modified.', 1;
    END

    IF @BypassLock = 1 AND @ExistingSubmissionID IS NOT NULL AND @ExistingLockState <> 'Unlocked'
    BEGIN
        UPDATE KPI.Submission
        SET LockState = 'Unlocked', LockedAt = NULL, LockedByPrincipalId = NULL,
            ModifiedOnUtc = SYSUTCDATETIME()
        WHERE SubmissionID = @ExistingSubmissionID;
    END

    DECLARE @NewLockState NVARCHAR(25) =
        CASE
            WHEN @SourceType = 'Automated' THEN 'LockedByAuto'
            WHEN @LockOnSubmit = 1         THEN 'Locked'
            ELSE 'Unlocked'
        END;

    DECLARE @LockedAt           DATETIME2 = CASE WHEN @NewLockState <> 'Unlocked' THEN SYSUTCDATETIME() ELSE NULL END;
    DECLARE @LockedByPrincipalId INT      = CASE WHEN @NewLockState <> 'Unlocked' THEN @SubmitterPrincipalId ELSE NULL END;

    IF @ExistingSubmissionID IS NULL
    BEGIN
        INSERT INTO KPI.Submission
            (AssignmentID, SubmittedByPrincipalId, SubmittedAt,
             SubmissionValue, SubmissionText, SubmissionBoolean, SubmissionNotes,
             SourceType, LockState, LockedAt, LockedByPrincipalId,
             DefinitionSnapshot)
        VALUES
            (@AssignmentID, @SubmitterPrincipalId, SYSUTCDATETIME(),
             @SubmissionValue, @SubmissionText, @SubmissionBoolean, @SubmissionNotes,
             @SourceType, @NewLockState, @LockedAt, @LockedByPrincipalId,
             @DefinitionSnapshot);

        SET @SubmissionID = SCOPE_IDENTITY();

        INSERT INTO KPI.SubmissionAudit
            (SubmissionID, ChangedByPrincipalId, Action, NewValue, ChangeReason)
        VALUES
            (@SubmissionID, @SubmitterPrincipalId, 'Insert',
             (SELECT @SubmissionValue AS SubmissionValue, @NewLockState AS LockState FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
             @ChangeReason);
    END
    ELSE
    BEGIN
        DECLARE @OldValue NVARCHAR(MAX);
        SELECT @OldValue = (
            SELECT SubmissionValue, SubmissionText, SubmissionNotes, LockState
            FROM KPI.Submission WHERE SubmissionID = @ExistingSubmissionID
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        UPDATE KPI.Submission
        SET SubmissionValue = @SubmissionValue, SubmissionText = @SubmissionText,
            SubmissionBoolean = @SubmissionBoolean, SubmissionNotes = @SubmissionNotes,
            SourceType = @SourceType, LockState = @NewLockState,
            LockedAt = @LockedAt, LockedByPrincipalId = @LockedByPrincipalId,
            ModifiedOnUtc = SYSUTCDATETIME()
        WHERE SubmissionID = @ExistingSubmissionID;

        SET @SubmissionID = @ExistingSubmissionID;

        INSERT INTO KPI.SubmissionAudit
            (SubmissionID, ChangedByPrincipalId, Action, OldValue, NewValue, ChangeReason)
        VALUES
            (@SubmissionID, @SubmitterPrincipalId, 'Update', @OldValue,
             (SELECT @SubmissionValue AS SubmissionValue, @NewLockState AS LockState FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
             @ChangeReason);
    END

    IF @NewLockState <> 'Unlocked'
    BEGIN
        DECLARE @SiteOrgUnitId INT = (
            SELECT OrgUnitId FROM KPI.Assignment WHERE AssignmentID = @AssignmentID
        );

        DECLARE @TotalRequired  INT;
        DECLARE @TotalSubmitted INT;

        SELECT @TotalRequired = COUNT(*)
        FROM KPI.Assignment
        WHERE OrgUnitId = @SiteOrgUnitId
          AND PeriodID  = @PeriodID
          AND IsRequired = 1
          AND IsActive   = 1;

        SELECT @TotalSubmitted = COUNT(*)
        FROM KPI.Assignment AS a
        JOIN KPI.Submission AS s ON s.AssignmentID = a.AssignmentID
        WHERE a.OrgUnitId = @SiteOrgUnitId
          AND a.PeriodID  = @PeriodID
          AND a.IsRequired = 1
          AND a.IsActive   = 1
          AND s.LockState <> 'Unlocked';

        IF @TotalRequired > 0 AND @TotalSubmitted >= @TotalRequired
        BEGIN
            UPDATE Workflow.ReminderState
SET IsResolved = 1, ResolvedAt = SYSUTCDATETIME(), ModifiedOnUtc = SYSUTCDATETIME()
WHERE OrgUnitId = @SiteOrgUnitId AND PeriodID = @PeriodID AND IsResolved = 0;
        END
    END

    COMMIT;
END;
GO

-- ============================================================
-- RAG views — restore pre-snapshot bodies (matching state after
-- IncludeTimeInRagViews migration, i.e. live thresholds + 'Time' allowed)
-- ============================================================

CREATE OR ALTER VIEW App.vKpiSubmissions
AS
    SELECT
        sub.SubmissionID, sub.ExternalId, sub.AssignmentID,
        d.KPICode, d.KPIName, d.Category, d.DataType, d.Unit,
        p.PeriodLabel, p.PeriodYear, p.PeriodMonth, p.Status AS PeriodStatus,
        site.OrgUnitId AS SiteOrgUnitId, site.OrgUnitCode AS SiteCode, site.OrgUnitName AS SiteName, site.CountryCode,
        acct.AccountCode, acct.AccountName,
        a.TargetValue, a.ThresholdGreen, a.ThresholdAmber, a.ThresholdRed,
        COALESCE(a.ThresholdDirection, d.ThresholdDirection) AS EffectiveThresholdDirection,
        sub.SubmissionValue, sub.SubmissionText, sub.SubmissionBoolean, sub.SubmissionNotes, sub.SourceType,
        submitter.UPN AS SubmittedByUPN, sub.SubmittedAt,
        sub.LockState, sub.LockedAt, locker.UPN AS LockedByUPN,
        sub.IsValid, sub.ValidationNotes,
        CASE
            WHEN d.DataType NOT IN ('Numeric','Percentage','Currency','Time') THEN NULL
            WHEN sub.SubmissionValue IS NULL                                  THEN NULL
            WHEN a.ThresholdGreen IS NULL                                     THEN NULL
            WHEN COALESCE(a.ThresholdDirection, d.ThresholdDirection) = 'Higher'
            THEN CASE
                WHEN sub.SubmissionValue >= a.ThresholdGreen THEN 'Green'
                WHEN sub.SubmissionValue >= a.ThresholdAmber THEN 'Amber'
                ELSE 'Red'
            END
            WHEN COALESCE(a.ThresholdDirection, d.ThresholdDirection) = 'Lower'
            THEN CASE
                WHEN sub.SubmissionValue <= a.ThresholdGreen THEN 'Green'
                WHEN sub.SubmissionValue <= a.ThresholdAmber THEN 'Amber'
                ELSE 'Red'
            END
            ELSE NULL
        END AS RAGStatus,
        sub.CreatedOnUtc, sub.ModifiedOnUtc
    FROM KPI.Submission AS sub
    JOIN KPI.Assignment AS a    ON a.AssignmentID = sub.AssignmentID
    JOIN KPI.Definition AS d    ON d.KPIID = a.KPIID
    JOIN KPI.Period     AS p    ON p.PeriodID = a.PeriodID
    JOIN Dim.OrgUnit    AS site ON site.OrgUnitId = a.OrgUnitId
    JOIN Dim.Account    AS acct ON acct.AccountId = a.AccountId
    LEFT JOIN Sec.[User] AS submitter ON submitter.UserId = sub.SubmittedByPrincipalId
    LEFT JOIN Sec.[User] AS locker    ON locker.UserId    = sub.LockedByPrincipalId;
GO

CREATE OR ALTER VIEW App.vSiteSubmissionDetails
AS
    SELECT
        asgn.OrgUnitId AS SiteOrgUnitId, asgn.PeriodID AS PeriodId, asgn.AssignmentID AS AssignmentId,
        asgn.ExternalId, d.KPICode AS KpiCode, d.KPIName AS KpiName,
        COALESCE(t.CustomKpiName, d.KPIName) AS EffectiveKpiName,
        d.Category, d.DataType, CAST(asgn.IsRequired AS bit) AS IsRequired,
        asgn.TargetValue, asgn.ThresholdGreen, asgn.ThresholdAmber, asgn.ThresholdRed,
        COALESCE(asgn.ThresholdDirection, d.ThresholdDirection) AS EffectiveThresholdDirection,
        sub.SubmissionID AS SubmissionId, sub.SubmissionValue, sub.SubmissionText, sub.SubmissionBoolean, sub.SubmissionNotes,
        sub.LockState, u.UPN AS SubmittedByUpn, sub.SubmittedAt,
        CAST(CASE WHEN sub.SubmissionID IS NOT NULL THEN 1 ELSE 0 END AS bit) AS IsSubmitted,
        CASE
            WHEN d.DataType NOT IN ('Numeric','Percentage','Currency','Time') THEN NULL
            WHEN sub.SubmissionValue IS NULL                                  THEN NULL
            WHEN asgn.ThresholdGreen IS NULL                                  THEN NULL
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
        END AS RagStatus,
        asgn.AssignmentGroupName
    FROM KPI.Assignment AS asgn
    JOIN KPI.Definition AS d ON d.KPIID = asgn.KPIID
    LEFT JOIN KPI.AssignmentTemplate AS t ON t.AssignmentTemplateID = asgn.AssignmentTemplateID
    LEFT JOIN KPI.Submission AS sub ON sub.AssignmentID = asgn.AssignmentID
    LEFT JOIN Sec.[User] AS u ON u.UserId = sub.SubmittedByPrincipalId
    WHERE asgn.OrgUnitId IS NOT NULL AND asgn.IsActive = 1;
GO

CREATE OR ALTER VIEW Reporting.vw_PBIKPIFact
AS
    SELECT
        s.ExternalId AS SubmissionKey, asgn.ExternalId AS AssignmentKey,
        d.ExternalId AS KPIDefinitionKey, per.ExternalId AS PeriodKey,
        per.PeriodLabel, per.PeriodYear, per.PeriodMonth,
        per.PeriodYear * 100 + per.PeriodMonth AS PeriodSortKey, per.Status AS PeriodStatus,
        d.KPICode, COALESCE(tmpl.CustomKpiName, d.KPIName) AS KPIName,
        d.Category AS KPICategory, d.Unit AS KPIUnit, d.DataType, d.CollectionType,
        per.PeriodScheduleID, ps.ScheduleName,
        asgn.AccountId, acct.AccountCode, acct.AccountName,
        asgn.OrgUnitId AS SiteId, ou.OrgUnitCode AS SiteCode, ou.OrgUnitName AS SiteName,
        CAST(CASE WHEN asgn.OrgUnitId IS NULL THEN 1 ELSE 0 END AS BIT) AS IsAccountWide,
        asgn.IsRequired,
        asgn.TargetValue, asgn.ThresholdGreen, asgn.ThresholdAmber, asgn.ThresholdRed,
        COALESCE(asgn.ThresholdDirection, d.ThresholdDirection) AS EffectiveThresholdDirection,
        s.SubmissionValue, s.SubmissionText, s.SubmissionNotes, s.SourceType, s.LockState,
        s.SubmittedAt, s.IsValid, s.ValidationNotes, s.CreatedOnUtc AS SubmissionCreatedAt,
        CASE
            WHEN s.SubmissionValue IS NULL THEN 'NoData'
            WHEN asgn.ThresholdGreen IS NULL THEN 'NoThreshold'
            WHEN COALESCE(asgn.ThresholdDirection, d.ThresholdDirection) = 'Higher'
                THEN CASE
                    WHEN s.SubmissionValue >= asgn.ThresholdGreen THEN 'Green'
                    WHEN asgn.ThresholdAmber IS NOT NULL AND s.SubmissionValue >= asgn.ThresholdAmber THEN 'Amber'
                    ELSE 'Red' END
            WHEN COALESCE(asgn.ThresholdDirection, d.ThresholdDirection) = 'Lower'
                THEN CASE
                    WHEN s.SubmissionValue <= asgn.ThresholdGreen THEN 'Green'
                    WHEN asgn.ThresholdAmber IS NOT NULL AND s.SubmissionValue <= asgn.ThresholdAmber THEN 'Amber'
                    ELSE 'Red' END
            ELSE 'NoThreshold'
        END AS RAGStatus,
        CASE
            WHEN s.SubmissionValue IS NULL THEN 4
            WHEN asgn.ThresholdGreen IS NULL THEN 5
            WHEN COALESCE(asgn.ThresholdDirection, d.ThresholdDirection) = 'Higher'
                THEN CASE
                    WHEN s.SubmissionValue >= asgn.ThresholdGreen THEN 3
                    WHEN asgn.ThresholdAmber IS NOT NULL AND s.SubmissionValue >= asgn.ThresholdAmber THEN 2
                    ELSE 1 END
            WHEN COALESCE(asgn.ThresholdDirection, d.ThresholdDirection) = 'Lower'
                THEN CASE
                    WHEN s.SubmissionValue <= asgn.ThresholdGreen THEN 3
                    WHEN asgn.ThresholdAmber IS NOT NULL AND s.SubmissionValue <= asgn.ThresholdAmber THEN 2
                    ELSE 1 END
            ELSE 5
        END AS RAGSortOrder
    FROM KPI.Submission AS s
    JOIN KPI.Assignment AS asgn ON asgn.AssignmentID = s.AssignmentID AND asgn.IsActive = 1
    JOIN KPI.Definition AS d    ON d.KPIID = asgn.KPIID
    JOIN KPI.Period AS per      ON per.PeriodID = asgn.PeriodID
    JOIN KPI.PeriodSchedule AS ps ON ps.PeriodScheduleID = per.PeriodScheduleID
    JOIN Dim.Account AS acct    ON acct.AccountId = asgn.AccountId
    LEFT JOIN Dim.OrgUnit AS ou ON ou.OrgUnitId = asgn.OrgUnitId
    LEFT JOIN KPI.AssignmentTemplate AS tmpl ON tmpl.AssignmentTemplateID = asgn.AssignmentTemplateID;
GO

CREATE OR ALTER VIEW Reporting.vw_PBIAssignmentStatus
AS
    SELECT
        asgn.ExternalId AS AssignmentKey, d.ExternalId AS KPIDefinitionKey, per.ExternalId AS PeriodKey,
        per.PeriodLabel, per.PeriodYear, per.PeriodMonth,
        per.PeriodYear * 100 + per.PeriodMonth AS PeriodSortKey, per.Status AS PeriodStatus,
        d.KPICode, COALESCE(tmpl.CustomKpiName, d.KPIName) AS KPIName,
        d.Category AS KPICategory, d.Unit AS KPIUnit, d.DataType, d.CollectionType,
        per.PeriodScheduleID, ps.ScheduleName,
        asgn.AccountId, acct.AccountCode, acct.AccountName,
        asgn.OrgUnitId AS SiteId, ou.OrgUnitCode AS SiteCode, ou.OrgUnitName AS SiteName,
        CAST(CASE WHEN asgn.OrgUnitId IS NULL THEN 1 ELSE 0 END AS BIT) AS IsAccountWide,
        asgn.IsRequired,
        asgn.TargetValue, asgn.ThresholdGreen, asgn.ThresholdAmber, asgn.ThresholdRed,
        COALESCE(asgn.ThresholdDirection, d.ThresholdDirection) AS EffectiveThresholdDirection,
        s.ExternalId AS SubmissionKey, s.SubmissionValue, s.SubmissionText, s.SourceType, s.LockState,
        s.SubmittedAt, s.IsValid,
        CAST(CASE WHEN s.SubmissionID IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS IsSubmitted,
        CAST(CASE WHEN s.LockState NOT IN ('Unlocked') AND s.SubmissionID IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS IsLocked,
        CASE
            WHEN s.SubmissionValue IS NULL THEN 'NoData'
            WHEN asgn.ThresholdGreen IS NULL THEN 'NoThreshold'
            WHEN COALESCE(asgn.ThresholdDirection, d.ThresholdDirection) = 'Higher'
                THEN CASE
                    WHEN s.SubmissionValue >= asgn.ThresholdGreen THEN 'Green'
                    WHEN asgn.ThresholdAmber IS NOT NULL AND s.SubmissionValue >= asgn.ThresholdAmber THEN 'Amber'
                    ELSE 'Red' END
            WHEN COALESCE(asgn.ThresholdDirection, d.ThresholdDirection) = 'Lower'
                THEN CASE
                    WHEN s.SubmissionValue <= asgn.ThresholdGreen THEN 'Green'
                    WHEN asgn.ThresholdAmber IS NOT NULL AND s.SubmissionValue <= asgn.ThresholdAmber THEN 'Amber'
                    ELSE 'Red' END
            ELSE 'NoThreshold'
        END AS RAGStatus,
        CASE
            WHEN s.SubmissionValue IS NULL THEN 4
            WHEN asgn.ThresholdGreen IS NULL THEN 5
            WHEN COALESCE(asgn.ThresholdDirection, d.ThresholdDirection) = 'Higher'
                THEN CASE
                    WHEN s.SubmissionValue >= asgn.ThresholdGreen THEN 3
                    WHEN asgn.ThresholdAmber IS NOT NULL AND s.SubmissionValue >= asgn.ThresholdAmber THEN 2
                    ELSE 1 END
            WHEN COALESCE(asgn.ThresholdDirection, d.ThresholdDirection) = 'Lower'
                THEN CASE
                    WHEN s.SubmissionValue <= asgn.ThresholdGreen THEN 3
                    WHEN asgn.ThresholdAmber IS NOT NULL AND s.SubmissionValue <= asgn.ThresholdAmber THEN 2
                    ELSE 1 END
            ELSE 5
        END AS RAGSortOrder
    FROM KPI.Assignment AS asgn
    LEFT JOIN KPI.Submission AS s ON s.AssignmentID = asgn.AssignmentID
    JOIN KPI.Definition AS d    ON d.KPIID = asgn.KPIID
    JOIN KPI.Period AS per      ON per.PeriodID = asgn.PeriodID
    JOIN KPI.PeriodSchedule AS ps ON ps.PeriodScheduleID = per.PeriodScheduleID
    JOIN Dim.Account AS acct    ON acct.AccountId = asgn.AccountId
    LEFT JOIN Dim.OrgUnit AS ou ON ou.OrgUnitId = asgn.OrgUnitId
    LEFT JOIN KPI.AssignmentTemplate AS tmpl ON tmpl.AssignmentTemplateID = asgn.AssignmentTemplateID
    WHERE asgn.IsActive = 1;
GO

-- ============================================================
-- Drop the snapshot columns + constraint
-- ============================================================

IF EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE name = 'CK_KpiSub_SubmittedThresholdDirection'
      AND parent_object_id = OBJECT_ID(N'KPI.Submission')
)
    ALTER TABLE KPI.Submission DROP CONSTRAINT CK_KpiSub_SubmittedThresholdDirection;
GO

IF COL_LENGTH('KPI.Submission', 'SubmittedThresholdDirection') IS NOT NULL
    ALTER TABLE KPI.Submission DROP COLUMN SubmittedThresholdDirection;
GO

IF COL_LENGTH('KPI.Submission', 'SubmittedThresholdRed') IS NOT NULL
    ALTER TABLE KPI.Submission DROP COLUMN SubmittedThresholdRed;
GO

IF COL_LENGTH('KPI.Submission', 'SubmittedThresholdAmber') IS NOT NULL
    ALTER TABLE KPI.Submission DROP COLUMN SubmittedThresholdAmber;
GO

IF COL_LENGTH('KPI.Submission', 'SubmittedThresholdGreen') IS NOT NULL
    ALTER TABLE KPI.Submission DROP COLUMN SubmittedThresholdGreen;
GO

IF COL_LENGTH('KPI.Submission', 'SubmittedTargetValue') IS NOT NULL
    ALTER TABLE KPI.Submission DROP COLUMN SubmittedTargetValue;
GO
