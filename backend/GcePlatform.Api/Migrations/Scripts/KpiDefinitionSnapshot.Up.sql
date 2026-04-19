-- ============================================================
-- Migration: KpiDefinitionSnapshot — Up
-- Adds DefinitionSnapshot (JSON) to KPI.Submission so that
-- KPI library metadata (name, unit, data type, category, and
-- dropdown options) is frozen at submission time. Later edits
-- to KPI.Definition or KPI.DropDownOption cannot retroactively
-- alter historical submitted data.
-- Safe to re-run: all DDL uses idempotent guards.
-- ============================================================
GO

-- ─────────────────────────────────────────────────────────────
-- 1. Add column
-- ─────────────────────────────────────────────────────────────
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('KPI.Submission')
      AND name = 'DefinitionSnapshot'
)
BEGIN
    ALTER TABLE KPI.Submission
        ADD DefinitionSnapshot NVARCHAR(MAX) NULL;
    PRINT '+ KPI.Submission.DefinitionSnapshot added';
END;
GO

-- ─────────────────────────────────────────────────────────────
-- 2. Backfill existing submissions using current definition
--    state as the best available approximation of history
-- ─────────────────────────────────────────────────────────────
-- FOR JSON PATH only works reliably inside a variable assignment (not bulk UPDATE/SELECT INTO)
-- Process row-by-row, mirroring the stored procedure pattern
DECLARE @SubmissionID  INT;
DECLARE @AssignmentID  INT;
DECLARE @Snapshot      NVARCHAR(MAX);

DECLARE cur CURSOR FAST_FORWARD FOR
    SELECT sub.SubmissionID, sub.AssignmentID
    FROM KPI.Submission AS sub
    WHERE sub.DefinitionSnapshot IS NULL;

OPEN cur;
FETCH NEXT FROM cur INTO @SubmissionID, @AssignmentID;

WHILE @@FETCH_STATUS = 0
BEGIN
    SELECT @Snapshot = (
        SELECT
            d.KPICode,
            d.KPIName,
            d.KPIDescription,
            COALESCE(tmpl.CustomKpiName,        d.KPIName)        AS EffectiveKpiName,
            COALESCE(tmpl.CustomKpiDescription, d.KPIDescription) AS EffectiveKpiDescription,
            d.Category,
            d.Unit,
            d.DataType,
            d.AllowMultiValue,
            d.CollectionType,
            a.IsRequired,
            a.TargetValue,
            a.ThresholdGreen,
            a.ThresholdAmber,
            a.ThresholdRed,
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

    UPDATE KPI.Submission
    SET DefinitionSnapshot = @Snapshot
    WHERE SubmissionID = @SubmissionID;

    FETCH NEXT FROM cur INTO @SubmissionID, @AssignmentID;
END

CLOSE cur;
DEALLOCATE cur;
GO

PRINT '+ DefinitionSnapshot backfilled for existing submissions';
GO

-- ─────────────────────────────────────────────────────────────
-- 3. Update App.usp_SubmitKpi to capture snapshot on first
--    submission. Re-submissions leave the snapshot untouched.
-- ─────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE App.usp_SubmitKpi
    @AssignmentExternalId   UNIQUEIDENTIFIER,
    @SubmitterUPN           NVARCHAR(320),
    @SubmissionValue        DECIMAL(18,4)   = NULL,
    @SubmissionText         NVARCHAR(1000)  = NULL,  -- also used for DropDown selections
    @SubmissionBoolean      BIT             = NULL,  -- used when DataType = 'Boolean'
    @SubmissionNotes        NVARCHAR(500)   = NULL,
    @SourceType             NVARCHAR(20)    = 'Manual',
    @LockOnSubmit           BIT             = 1,   -- set to 0 for draft saves
    @ChangeReason           NVARCHAR(500)   = NULL,
    @BypassLock             BIT             = 0,   -- set to 1 for KpiAdmin post-close edits
    @SubmissionID           INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRAN;

    -- Resolve assignment
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

    -- Validate period is open and within submission window
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

    -- Resolve submitter principal
    DECLARE @SubmitterPrincipalId INT = (
        SELECT UserId FROM Sec.[User] WHERE UPN = @SubmitterUPN
    );
    IF @SubmitterPrincipalId IS NULL
    BEGIN
        ROLLBACK;
        THROW 50204, 'Submitter user not found.', 1;
    END

    -- Snapshot the full effective assignment state at first submission:
    -- library defaults + assignment-level overrides + template custom name/description
    DECLARE @DefinitionSnapshot NVARCHAR(MAX);
    SELECT @DefinitionSnapshot = (
        SELECT
            d.KPICode,
            d.KPIName,
            d.KPIDescription,
            COALESCE(tmpl.CustomKpiName,        d.KPIName)        AS EffectiveKpiName,
            COALESCE(tmpl.CustomKpiDescription, d.KPIDescription) AS EffectiveKpiDescription,
            d.Category,
            d.Unit,
            d.DataType,
            d.AllowMultiValue,
            d.CollectionType,
            a.IsRequired,
            a.TargetValue,
            a.ThresholdGreen,
            a.ThresholdAmber,
            a.ThresholdRed,
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

    -- Get existing submission if any
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

    -- KpiAdmin bypass: unlock the existing submission so the trigger allows value changes
    IF @BypassLock = 1 AND @ExistingSubmissionID IS NOT NULL AND @ExistingLockState <> 'Unlocked'
    BEGIN
        UPDATE KPI.Submission
        SET LockState           = 'Unlocked',
            LockedAt            = NULL,
            LockedByPrincipalId = NULL,
            ModifiedOnUtc       = SYSUTCDATETIME()
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
        -- First submission: snapshot the KPI definition as it exists right now
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

        -- Write audit entry
        INSERT INTO KPI.SubmissionAudit
            (SubmissionID, ChangedByPrincipalId, Action, NewValue, ChangeReason)
        VALUES
            (@SubmissionID, @SubmitterPrincipalId, 'Insert',
             (SELECT @SubmissionValue AS SubmissionValue, @NewLockState AS LockState FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
             @ChangeReason);
    END
    ELSE
    BEGIN
        -- Re-submission: update values only; DefinitionSnapshot is intentionally left unchanged
        DECLARE @OldValue NVARCHAR(MAX);
        SELECT @OldValue = (
            SELECT SubmissionValue, SubmissionText, SubmissionNotes, LockState
            FROM KPI.Submission WHERE SubmissionID = @ExistingSubmissionID
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        -- Direct UPDATE bypasses the trigger since LockState was 'Unlocked'
        UPDATE KPI.Submission
        SET SubmissionValue       = @SubmissionValue,
            SubmissionText        = @SubmissionText,
            SubmissionBoolean     = @SubmissionBoolean,
            SubmissionNotes       = @SubmissionNotes,
            SourceType            = @SourceType,
            LockState             = @NewLockState,
            LockedAt              = @LockedAt,
            LockedByPrincipalId   = @LockedByPrincipalId,
            ModifiedOnUtc         = SYSUTCDATETIME()
        WHERE SubmissionID = @ExistingSubmissionID;

        SET @SubmissionID = @ExistingSubmissionID;

        INSERT INTO KPI.SubmissionAudit
            (SubmissionID, ChangedByPrincipalId, Action, OldValue, NewValue, ChangeReason)
        VALUES
            (@SubmissionID, @SubmitterPrincipalId, 'Update',
             @OldValue,
             (SELECT @SubmissionValue AS SubmissionValue, @NewLockState AS LockState FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
             @ChangeReason);
    END

    -- Resolve reminder state for this site+period if submission is locked
    IF @NewLockState <> 'Unlocked'
    BEGIN
        DECLARE @SiteOrgUnitId INT = (
            SELECT OrgUnitId FROM KPI.Assignment WHERE AssignmentID = @AssignmentID
        );

        -- Check if ALL required assignments for this site+period are now submitted
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
            SET IsResolved    = 1,
                ResolvedAt    = SYSUTCDATETIME(),
                ModifiedOnUtc = SYSUTCDATETIME()
            WHERE OrgUnitId  = @SiteOrgUnitId
              AND PeriodID   = @PeriodID
              AND IsResolved = 0;
        END
    END

    COMMIT;
END;
GO

PRINT '+ App.usp_SubmitKpi updated with DefinitionSnapshot support';
GO
