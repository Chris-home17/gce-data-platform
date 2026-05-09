-- ============================================================
-- Migration: KpiScoringPhase2 — Down
-- Drops the score views, restores usp_SubmitKpi to the Phase-1
-- (threshold-only) snapshot version, and removes the new submission
-- snapshot columns + check constraints.
-- ============================================================

IF OBJECT_ID('App.vSiteCompositeScore', 'V') IS NOT NULL
    DROP VIEW App.vSiteCompositeScore;
GO

IF OBJECT_ID('App.vKpiSubmissionScores', 'V') IS NOT NULL
    DROP VIEW App.vKpiSubmissionScores;
GO

-- Restore usp_SubmitKpi to the Phase-1 (threshold-only snapshot) version.
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

    DECLARE @AssignmentID INT, @PeriodID INT, @KPIID INT;

    SELECT @AssignmentID = a.AssignmentID, @PeriodID = a.PeriodID, @KPIID = a.KPIID
    FROM KPI.Assignment AS a
    WHERE a.ExternalId = @AssignmentExternalId AND a.IsActive = 1;

    IF @AssignmentID IS NULL BEGIN ROLLBACK; THROW 50201, 'Assignment not found or inactive.', 1; END

    DECLARE @PeriodStatus NVARCHAR(20), @CloseDate DATE;
    SELECT @PeriodStatus = Status, @CloseDate = SubmissionCloseDate
    FROM KPI.Period WHERE PeriodID = @PeriodID;

    IF @BypassLock = 0 AND @PeriodStatus <> 'Open' BEGIN ROLLBACK; THROW 50202, 'Submissions are not accepted: period is not Open.', 1; END
    IF @BypassLock = 0 AND CAST(SYSUTCDATETIME() AS DATE) > @CloseDate BEGIN ROLLBACK; THROW 50203, 'Submissions are not accepted: the submission window has closed.', 1; END

    DECLARE @SubmitterPrincipalId INT = (SELECT UserId FROM Sec.[User] WHERE UPN = @SubmitterUPN);
    IF @SubmitterPrincipalId IS NULL BEGIN ROLLBACK; THROW 50204, 'Submitter user not found.', 1; END

    DECLARE @DefinitionSnapshot NVARCHAR(MAX);
    SELECT @DefinitionSnapshot = (
        SELECT d.KPICode, d.KPIName, d.KPIDescription,
            COALESCE(tmpl.CustomKpiName, d.KPIName) AS EffectiveKpiName,
            COALESCE(tmpl.CustomKpiDescription, d.KPIDescription) AS EffectiveKpiDescription,
            d.Category, d.Unit, d.DataType, d.AllowMultiValue, d.CollectionType,
            a.IsRequired, a.TargetValue, a.ThresholdGreen, a.ThresholdAmber, a.ThresholdRed,
            COALESCE(a.ThresholdDirection, d.ThresholdDirection) AS EffectiveThresholdDirection,
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
                ORDER BY opt.SortOrder FOR JSON PATH
            ) ELSE NULL END AS OptionsJson
        ) AS opts
        WHERE a.AssignmentID = @AssignmentID
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );

    DECLARE @ExistingSubmissionID INT, @ExistingLockState NVARCHAR(25);
    SELECT @ExistingSubmissionID = SubmissionID, @ExistingLockState = LockState
    FROM KPI.Submission WHERE AssignmentID = @AssignmentID;

    IF @ExistingSubmissionID IS NOT NULL AND @ExistingLockState <> 'Unlocked' AND @BypassLock = 0
    BEGIN ROLLBACK; THROW 50205, 'This KPI submission is locked and cannot be modified.', 1; END

    IF @BypassLock = 1 AND @ExistingSubmissionID IS NOT NULL AND @ExistingLockState <> 'Unlocked'
    BEGIN
        UPDATE KPI.Submission
        SET LockState = 'Unlocked', LockedAt = NULL, LockedByPrincipalId = NULL, ModifiedOnUtc = SYSUTCDATETIME()
        WHERE SubmissionID = @ExistingSubmissionID;
    END

    DECLARE @NewLockState NVARCHAR(25) = CASE
        WHEN @SourceType = 'Automated' THEN 'LockedByAuto'
        WHEN @LockOnSubmit = 1 THEN 'Locked' ELSE 'Unlocked' END;
    DECLARE @LockedAt DATETIME2 = CASE WHEN @NewLockState <> 'Unlocked' THEN SYSUTCDATETIME() ELSE NULL END;
    DECLARE @LockedByPrincipalId INT = CASE WHEN @NewLockState <> 'Unlocked' THEN @SubmitterPrincipalId ELSE NULL END;

    DECLARE @SnapTargetValue DECIMAL(18,4), @SnapThresholdGreen DECIMAL(18,4),
            @SnapThresholdAmber DECIMAL(18,4), @SnapThresholdRed DECIMAL(18,4),
            @SnapThresholdDirection NVARCHAR(10);

    SELECT @SnapTargetValue = a.TargetValue, @SnapThresholdGreen = a.ThresholdGreen,
           @SnapThresholdAmber = a.ThresholdAmber, @SnapThresholdRed = a.ThresholdRed,
           @SnapThresholdDirection = COALESCE(a.ThresholdDirection, d.ThresholdDirection)
    FROM KPI.Assignment AS a JOIN KPI.Definition AS d ON d.KPIID = a.KPIID
    WHERE a.AssignmentID = @AssignmentID;

    IF @ExistingSubmissionID IS NULL
    BEGIN
        INSERT INTO KPI.Submission
            (AssignmentID, SubmittedByPrincipalId, SubmittedAt,
             SubmissionValue, SubmissionText, SubmissionBoolean, SubmissionNotes,
             SourceType, LockState, LockedAt, LockedByPrincipalId, DefinitionSnapshot,
             SubmittedTargetValue, SubmittedThresholdGreen, SubmittedThresholdAmber,
             SubmittedThresholdRed, SubmittedThresholdDirection)
        VALUES
            (@AssignmentID, @SubmitterPrincipalId, SYSUTCDATETIME(),
             @SubmissionValue, @SubmissionText, @SubmissionBoolean, @SubmissionNotes,
             @SourceType, @NewLockState, @LockedAt, @LockedByPrincipalId, @DefinitionSnapshot,
             @SnapTargetValue, @SnapThresholdGreen, @SnapThresholdAmber,
             @SnapThresholdRed, @SnapThresholdDirection);

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
        DECLARE @SiteOrgUnitId INT = (SELECT OrgUnitId FROM KPI.Assignment WHERE AssignmentID = @AssignmentID);
        DECLARE @TotalRequired INT, @TotalSubmitted INT;

        SELECT @TotalRequired = COUNT(*) FROM KPI.Assignment
        WHERE OrgUnitId = @SiteOrgUnitId AND PeriodID = @PeriodID AND IsRequired = 1 AND IsActive = 1;

        SELECT @TotalSubmitted = COUNT(*) FROM KPI.Assignment AS a
        JOIN KPI.Submission AS s ON s.AssignmentID = a.AssignmentID
        WHERE a.OrgUnitId = @SiteOrgUnitId AND a.PeriodID = @PeriodID
          AND a.IsRequired = 1 AND a.IsActive = 1 AND s.LockState <> 'Unlocked';

        IF @TotalRequired > 0 AND @TotalSubmitted >= @TotalRequired
        BEGIN
            UPDATE KPI.SiteReminderState
            SET ReminderResolved = 1, ReminderResolvedAt = SYSUTCDATETIME(), ModifiedOnUtc = SYSUTCDATETIME()
            WHERE SiteOrgUnitId = @SiteOrgUnitId AND PeriodID = @PeriodID AND ReminderResolved = 0;
        END
    END

    COMMIT;
END;
GO

-- Drop the new check constraints
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_KpiSub_SubmittedMSRule' AND parent_object_id = OBJECT_ID(N'KPI.Submission'))
    ALTER TABLE KPI.Submission DROP CONSTRAINT CK_KpiSub_SubmittedMSRule;
GO
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_KpiSub_SubmittedScoringMode' AND parent_object_id = OBJECT_ID(N'KPI.Submission'))
    ALTER TABLE KPI.Submission DROP CONSTRAINT CK_KpiSub_SubmittedScoringMode;
GO

-- Drop scoring snapshot columns (no defaults to clean up — they're all nullable)
DECLARE @col SYSNAME, @sql NVARCHAR(MAX);
DECLARE @cols TABLE (col SYSNAME);
INSERT @cols VALUES
    ('SubmittedPenaliseMissingOnScore'),('SubmittedDropDownOptionPoints'),
    ('SubmittedMultiSelectScoreRule'),('SubmittedBooleanNoPoints'),('SubmittedBooleanYesPoints'),
    ('SubmittedBandPointsRed'),('SubmittedBandPointsAmber'),('SubmittedBandPointsGreen'),
    ('SubmittedScoringMode'),('SubmittedKpiWeight');

DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT col FROM @cols;
OPEN c; FETCH NEXT FROM c INTO @col;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF COL_LENGTH('KPI.Submission', @col) IS NOT NULL
    BEGIN
        SET @sql = 'ALTER TABLE KPI.Submission DROP COLUMN ' + QUOTENAME(@col) + ';';
        EXEC sp_executesql @sql;
    END
    FETCH NEXT FROM c INTO @col;
END
CLOSE c; DEALLOCATE c;
GO
