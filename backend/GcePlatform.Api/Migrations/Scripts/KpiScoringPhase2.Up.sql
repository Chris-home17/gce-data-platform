-- ============================================================
-- Migration: KpiScoringPhase2 — Up
-- Phase 2 of the KPI scoring layer:
--   * 10 snapshot columns on KPI.Submission so scoring inputs are frozen
--     at first-submit time (matches the existing threshold-snapshot pattern).
--   * One-shot backfill of historical submissions from current assignment +
--     template state (faithful since scoring config has only just landed).
--   * usp_SubmitKpi extended to snapshot the new fields on INSERT.
--   * Two new views:
--       - App.vKpiSubmissionScores: per-assignment 0–100 score (snapshot-aware,
--         NULL for excluded rows; honours PenaliseMissingOnScore when the
--         assignment has no submission).
--       - App.vSiteCompositeScore: site × period × category roll-up plus
--         the site-level composite (weighted across active categories).
--
-- Idempotent: ALTER TABLE ADD guarded with COL_LENGTH IS NULL; CREATE OR
-- ALTER is naturally idempotent.
-- ============================================================

-- ─── KPI.Submission snapshot columns ──────────────────────────

IF COL_LENGTH('KPI.Submission', 'SubmittedKpiWeight') IS NULL
    ALTER TABLE KPI.Submission ADD SubmittedKpiWeight DECIMAL(9,4) NULL;
GO

IF COL_LENGTH('KPI.Submission', 'SubmittedScoringMode') IS NULL
    ALTER TABLE KPI.Submission ADD SubmittedScoringMode NVARCHAR(10) NULL;
GO

IF COL_LENGTH('KPI.Submission', 'SubmittedBandPointsGreen') IS NULL
    ALTER TABLE KPI.Submission ADD SubmittedBandPointsGreen DECIMAL(9,4) NULL;
GO

IF COL_LENGTH('KPI.Submission', 'SubmittedBandPointsAmber') IS NULL
    ALTER TABLE KPI.Submission ADD SubmittedBandPointsAmber DECIMAL(9,4) NULL;
GO

IF COL_LENGTH('KPI.Submission', 'SubmittedBandPointsRed') IS NULL
    ALTER TABLE KPI.Submission ADD SubmittedBandPointsRed DECIMAL(9,4) NULL;
GO

IF COL_LENGTH('KPI.Submission', 'SubmittedBooleanYesPoints') IS NULL
    ALTER TABLE KPI.Submission ADD SubmittedBooleanYesPoints DECIMAL(9,4) NULL;
GO

IF COL_LENGTH('KPI.Submission', 'SubmittedBooleanNoPoints') IS NULL
    ALTER TABLE KPI.Submission ADD SubmittedBooleanNoPoints DECIMAL(9,4) NULL;
GO

IF COL_LENGTH('KPI.Submission', 'SubmittedMultiSelectScoreRule') IS NULL
    ALTER TABLE KPI.Submission ADD SubmittedMultiSelectScoreRule NVARCHAR(10) NULL;
GO

IF COL_LENGTH('KPI.Submission', 'SubmittedDropDownOptionPoints') IS NULL
    ALTER TABLE KPI.Submission ADD SubmittedDropDownOptionPoints NVARCHAR(MAX) NULL;
GO

IF COL_LENGTH('KPI.Submission', 'SubmittedPenaliseMissingOnScore') IS NULL
    ALTER TABLE KPI.Submission ADD SubmittedPenaliseMissingOnScore BIT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE name = 'CK_KpiSub_SubmittedScoringMode'
      AND parent_object_id = OBJECT_ID(N'KPI.Submission')
)
    ALTER TABLE KPI.Submission
        ADD CONSTRAINT CK_KpiSub_SubmittedScoringMode
            CHECK (SubmittedScoringMode IN ('Band','Linear') OR SubmittedScoringMode IS NULL);
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE name = 'CK_KpiSub_SubmittedMSRule'
      AND parent_object_id = OBJECT_ID(N'KPI.Submission')
)
    ALTER TABLE KPI.Submission
        ADD CONSTRAINT CK_KpiSub_SubmittedMSRule
            CHECK (SubmittedMultiSelectScoreRule IN ('Sum','Avg','Max') OR SubmittedMultiSelectScoreRule IS NULL);
GO

-- ─── One-shot backfill ────────────────────────────────────────
-- Faithful because Phase 1 just landed scoring config and nothing's been
-- edited yet — current assignment values equal what the submitter saw.
-- DropDown option points are pulled from the template (if any), serialised
-- as JSON [{"value":..,"points":..}, ...].

UPDATE sub
SET SubmittedKpiWeight              = a.KpiWeight,
    SubmittedScoringMode            = a.ScoringMode,
    SubmittedBandPointsGreen        = a.BandPointsGreen,
    SubmittedBandPointsAmber        = a.BandPointsAmber,
    SubmittedBandPointsRed          = a.BandPointsRed,
    SubmittedBooleanYesPoints       = a.BooleanYesPoints,
    SubmittedBooleanNoPoints        = a.BooleanNoPoints,
    SubmittedMultiSelectScoreRule   = a.MultiSelectScoreRule,
    SubmittedPenaliseMissingOnScore = a.PenaliseMissingOnScore,
    SubmittedDropDownOptionPoints   = (
        SELECT opt.OptionValue AS [value], opt.Points AS [points]
        FROM KPI.AssignmentTemplateDropDownOption AS opt
        WHERE opt.AssignmentTemplateID = a.AssignmentTemplateID
        FOR JSON PATH
    )
FROM KPI.Submission AS sub
JOIN KPI.Assignment AS a ON a.AssignmentID = sub.AssignmentID
WHERE sub.SubmittedKpiWeight IS NULL
  AND sub.SubmittedScoringMode IS NULL;
GO

-- ============================================================
-- usp_SubmitKpi — extend the snapshot block with scoring fields
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

    -- Snapshot block: thresholds AND scoring config, locked at first INSERT.
    DECLARE @SnapTargetValue        DECIMAL(18,4);
    DECLARE @SnapThresholdGreen     DECIMAL(18,4);
    DECLARE @SnapThresholdAmber     DECIMAL(18,4);
    DECLARE @SnapThresholdRed       DECIMAL(18,4);
    DECLARE @SnapThresholdDirection NVARCHAR(10);
    DECLARE @SnapKpiWeight          DECIMAL(9,4);
    DECLARE @SnapScoringMode        NVARCHAR(10);
    DECLARE @SnapBandG              DECIMAL(9,4);
    DECLARE @SnapBandA              DECIMAL(9,4);
    DECLARE @SnapBandR              DECIMAL(9,4);
    DECLARE @SnapBoolY              DECIMAL(9,4);
    DECLARE @SnapBoolN              DECIMAL(9,4);
    DECLARE @SnapMSRule             NVARCHAR(10);
    DECLARE @SnapPenaliseMissing    BIT;
    DECLARE @SnapTemplateId         INT;

    SELECT
        @SnapTargetValue        = a.TargetValue,
        @SnapThresholdGreen     = a.ThresholdGreen,
        @SnapThresholdAmber     = a.ThresholdAmber,
        @SnapThresholdRed       = a.ThresholdRed,
        @SnapThresholdDirection = COALESCE(a.ThresholdDirection, d.ThresholdDirection),
        @SnapKpiWeight          = a.KpiWeight,
        @SnapScoringMode        = a.ScoringMode,
        @SnapBandG              = a.BandPointsGreen,
        @SnapBandA              = a.BandPointsAmber,
        @SnapBandR              = a.BandPointsRed,
        @SnapBoolY              = a.BooleanYesPoints,
        @SnapBoolN              = a.BooleanNoPoints,
        @SnapMSRule             = a.MultiSelectScoreRule,
        @SnapPenaliseMissing    = a.PenaliseMissingOnScore,
        @SnapTemplateId         = a.AssignmentTemplateID
    FROM KPI.Assignment AS a
    JOIN KPI.Definition AS d ON d.KPIID = a.KPIID
    WHERE a.AssignmentID = @AssignmentID;

    -- DropDown option points (NULL when there's no template or no options)
    DECLARE @SnapDDPoints NVARCHAR(MAX) = (
        SELECT opt.OptionValue AS [value], opt.Points AS [points]
        FROM KPI.AssignmentTemplateDropDownOption AS opt
        WHERE opt.AssignmentTemplateID = @SnapTemplateId
        FOR JSON PATH
    );

    IF @ExistingSubmissionID IS NULL
    BEGIN
        INSERT INTO KPI.Submission
            (AssignmentID, SubmittedByPrincipalId, SubmittedAt,
             SubmissionValue, SubmissionText, SubmissionBoolean, SubmissionNotes,
             SourceType, LockState, LockedAt, LockedByPrincipalId,
             DefinitionSnapshot,
             SubmittedTargetValue, SubmittedThresholdGreen, SubmittedThresholdAmber,
             SubmittedThresholdRed, SubmittedThresholdDirection,
             SubmittedKpiWeight, SubmittedScoringMode,
             SubmittedBandPointsGreen, SubmittedBandPointsAmber, SubmittedBandPointsRed,
             SubmittedBooleanYesPoints, SubmittedBooleanNoPoints,
             SubmittedMultiSelectScoreRule, SubmittedDropDownOptionPoints,
             SubmittedPenaliseMissingOnScore)
        VALUES
            (@AssignmentID, @SubmitterPrincipalId, SYSUTCDATETIME(),
             @SubmissionValue, @SubmissionText, @SubmissionBoolean, @SubmissionNotes,
             @SourceType, @NewLockState, @LockedAt, @LockedByPrincipalId,
             @DefinitionSnapshot,
             @SnapTargetValue, @SnapThresholdGreen, @SnapThresholdAmber,
             @SnapThresholdRed, @SnapThresholdDirection,
             @SnapKpiWeight, @SnapScoringMode,
             @SnapBandG, @SnapBandA, @SnapBandR,
             @SnapBoolY, @SnapBoolN,
             @SnapMSRule, @SnapDDPoints,
             @SnapPenaliseMissing);

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

    -- Reminder-state side effect (unchanged from the Phase 1 version)
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
            UPDATE KPI.SiteReminderState
            SET ReminderResolved = 1,
                ReminderResolvedAt = SYSUTCDATETIME(),
                ModifiedOnUtc      = SYSUTCDATETIME()
            WHERE SiteOrgUnitId = @SiteOrgUnitId
              AND PeriodID      = @PeriodID
              AND ReminderResolved = 0;
        END
    END

    COMMIT;
END;
GO

-- ============================================================
-- App.vKpiSubmissionScores — per-assignment normalised 0–100 score
-- ============================================================
-- One row per active assignment. Score is NULL for excluded rows
-- (Text data type, missing+not-penalised, no submission yet on
-- DropDown without snapshotted points). Otherwise 0–100 inclusive.
-- Uses snapshot-aware reads via COALESCE(snap, live) — same pattern
-- as App.vKpiSubmissions for thresholds.

CREATE OR ALTER VIEW App.vKpiSubmissionScores
AS
SELECT
    a.AssignmentID,
    a.AccountId,
    a.OrgUnitId    AS SiteOrgUnitId,
    a.PeriodID,
    a.IsRequired,
    sub.SubmissionID,
    sub.LockState,
    d.KPIID,
    d.KPICode,
    d.KPIName,
    d.Category,
    d.DataType,
    COALESCE(sub.SubmittedKpiWeight,            a.KpiWeight)              AS KpiWeight,
    COALESCE(sub.SubmittedPenaliseMissingOnScore, a.PenaliseMissingOnScore) AS PenaliseMissingOnScore,
    -- Score is NULL for "exclude from rollup", a number 0–100 otherwise.
    CASE
        WHEN d.DataType = 'Text' THEN NULL
        WHEN sub.SubmissionID IS NULL THEN
            CASE WHEN COALESCE(sub.SubmittedPenaliseMissingOnScore, a.PenaliseMissingOnScore) = 1
                  AND a.IsRequired = 1
                 THEN 0
                 ELSE NULL
            END
        WHEN d.DataType = 'Boolean' THEN
            CASE
                WHEN sub.SubmissionBoolean IS NULL THEN NULL
                WHEN sub.SubmissionBoolean = 1 THEN COALESCE(sub.SubmittedBooleanYesPoints, a.BooleanYesPoints, 100)
                ELSE COALESCE(sub.SubmittedBooleanNoPoints, a.BooleanNoPoints, 0)
            END
        WHEN d.DataType = 'DropDown' THEN dd.Points
        WHEN d.DataType IN ('Numeric','Percentage','Currency','Time') THEN num.Score
        ELSE NULL
    END AS Score,
    100.0 AS MaxScore
FROM KPI.Assignment AS a
JOIN KPI.Definition AS d ON d.KPIID = a.KPIID
LEFT JOIN KPI.Submission AS sub ON sub.AssignmentID = a.AssignmentID
OUTER APPLY (
    -- DropDown aggregate. STRING_SPLIT happily consumes NULL via ISNULL();
    -- non-DropDown rows compute against an empty selection and get NULL.
    SELECT
        CASE COALESCE(sub.SubmittedMultiSelectScoreRule, a.MultiSelectScoreRule)
            WHEN 'Sum' THEN
                (SELECT CASE WHEN ISNULL(SUM(p.points), 0) > 100 THEN 100 ELSE ISNULL(SUM(p.points), 0) END
                 FROM STRING_SPLIT(ISNULL(sub.SubmissionText, ''), '|') AS sel
                 LEFT JOIN OPENJSON(COALESCE(sub.SubmittedDropDownOptionPoints, '[]'))
                    WITH (value NVARCHAR(200) '$.value', points DECIMAL(9,4) '$.points') AS p
                    ON LTRIM(RTRIM(sel.value)) = p.value
                 WHERE LTRIM(RTRIM(sel.value)) <> '')
            WHEN 'Avg' THEN
                (SELECT AVG(ISNULL(p.points, 0))
                 FROM STRING_SPLIT(ISNULL(sub.SubmissionText, ''), '|') AS sel
                 LEFT JOIN OPENJSON(COALESCE(sub.SubmittedDropDownOptionPoints, '[]'))
                    WITH (value NVARCHAR(200) '$.value', points DECIMAL(9,4) '$.points') AS p
                    ON LTRIM(RTRIM(sel.value)) = p.value
                 WHERE LTRIM(RTRIM(sel.value)) <> '')
            WHEN 'Max' THEN
                (SELECT MAX(ISNULL(p.points, 0))
                 FROM STRING_SPLIT(ISNULL(sub.SubmissionText, ''), '|') AS sel
                 LEFT JOIN OPENJSON(COALESCE(sub.SubmittedDropDownOptionPoints, '[]'))
                    WITH (value NVARCHAR(200) '$.value', points DECIMAL(9,4) '$.points') AS p
                    ON LTRIM(RTRIM(sel.value)) = p.value
                 WHERE LTRIM(RTRIM(sel.value)) <> '')
            ELSE
                -- Single-select fallback when AllowMultiValue=0 or rule is NULL.
                (SELECT TOP 1 ISNULL(p.points, 0)
                 FROM OPENJSON(COALESCE(sub.SubmittedDropDownOptionPoints, '[]'))
                    WITH (value NVARCHAR(200) '$.value', points DECIMAL(9,4) '$.points') AS p
                 WHERE p.value = sub.SubmissionText)
        END AS Points
) AS dd
OUTER APPLY (
    -- Numeric/Percentage/Currency/Time score using snapshot-aware reads.
    SELECT
        CASE
            WHEN sub.SubmissionValue IS NULL THEN NULL
            WHEN COALESCE(sub.SubmittedThresholdGreen, a.ThresholdGreen) IS NULL THEN NULL
            WHEN COALESCE(sub.SubmittedScoringMode, a.ScoringMode) = 'Linear' THEN
                CASE COALESCE(sub.SubmittedThresholdDirection, a.ThresholdDirection, d.ThresholdDirection)
                    WHEN 'Higher' THEN
                        CASE
                            WHEN sub.SubmissionValue >= COALESCE(sub.SubmittedThresholdGreen, a.ThresholdGreen)
                                THEN COALESCE(sub.SubmittedBandPointsGreen, a.BandPointsGreen)
                            WHEN sub.SubmissionValue >= COALESCE(sub.SubmittedThresholdAmber, a.ThresholdAmber)
                                THEN COALESCE(sub.SubmittedBandPointsAmber, a.BandPointsAmber)
                                   + (sub.SubmissionValue - COALESCE(sub.SubmittedThresholdAmber, a.ThresholdAmber))
                                   / NULLIF(COALESCE(sub.SubmittedThresholdGreen, a.ThresholdGreen)
                                          - COALESCE(sub.SubmittedThresholdAmber, a.ThresholdAmber), 0)
                                   * (COALESCE(sub.SubmittedBandPointsGreen, a.BandPointsGreen)
                                    - COALESCE(sub.SubmittedBandPointsAmber, a.BandPointsAmber))
                            WHEN sub.SubmissionValue >= COALESCE(sub.SubmittedThresholdRed, a.ThresholdRed)
                                THEN COALESCE(sub.SubmittedBandPointsRed, a.BandPointsRed)
                                   + (sub.SubmissionValue - COALESCE(sub.SubmittedThresholdRed, a.ThresholdRed))
                                   / NULLIF(COALESCE(sub.SubmittedThresholdAmber, a.ThresholdAmber)
                                          - COALESCE(sub.SubmittedThresholdRed, a.ThresholdRed), 0)
                                   * (COALESCE(sub.SubmittedBandPointsAmber, a.BandPointsAmber)
                                    - COALESCE(sub.SubmittedBandPointsRed, a.BandPointsRed))
                            ELSE COALESCE(sub.SubmittedBandPointsRed, a.BandPointsRed)
                        END
                    WHEN 'Lower' THEN
                        CASE
                            WHEN sub.SubmissionValue <= COALESCE(sub.SubmittedThresholdGreen, a.ThresholdGreen)
                                THEN COALESCE(sub.SubmittedBandPointsGreen, a.BandPointsGreen)
                            WHEN sub.SubmissionValue <= COALESCE(sub.SubmittedThresholdAmber, a.ThresholdAmber)
                                THEN COALESCE(sub.SubmittedBandPointsAmber, a.BandPointsAmber)
                                   + (COALESCE(sub.SubmittedThresholdAmber, a.ThresholdAmber) - sub.SubmissionValue)
                                   / NULLIF(COALESCE(sub.SubmittedThresholdAmber, a.ThresholdAmber)
                                          - COALESCE(sub.SubmittedThresholdGreen, a.ThresholdGreen), 0)
                                   * (COALESCE(sub.SubmittedBandPointsGreen, a.BandPointsGreen)
                                    - COALESCE(sub.SubmittedBandPointsAmber, a.BandPointsAmber))
                            WHEN sub.SubmissionValue <= COALESCE(sub.SubmittedThresholdRed, a.ThresholdRed)
                                THEN COALESCE(sub.SubmittedBandPointsRed, a.BandPointsRed)
                                   + (COALESCE(sub.SubmittedThresholdRed, a.ThresholdRed) - sub.SubmissionValue)
                                   / NULLIF(COALESCE(sub.SubmittedThresholdRed, a.ThresholdRed)
                                          - COALESCE(sub.SubmittedThresholdAmber, a.ThresholdAmber), 0)
                                   * (COALESCE(sub.SubmittedBandPointsAmber, a.BandPointsAmber)
                                    - COALESCE(sub.SubmittedBandPointsRed, a.BandPointsRed))
                            ELSE COALESCE(sub.SubmittedBandPointsRed, a.BandPointsRed)
                        END
                    ELSE NULL
                END
            ELSE
                CASE COALESCE(sub.SubmittedThresholdDirection, a.ThresholdDirection, d.ThresholdDirection)
                    WHEN 'Higher' THEN
                        CASE
                            WHEN sub.SubmissionValue >= COALESCE(sub.SubmittedThresholdGreen, a.ThresholdGreen)
                                THEN COALESCE(sub.SubmittedBandPointsGreen, a.BandPointsGreen)
                            WHEN sub.SubmissionValue >= COALESCE(sub.SubmittedThresholdAmber, a.ThresholdAmber)
                                THEN COALESCE(sub.SubmittedBandPointsAmber, a.BandPointsAmber)
                            ELSE COALESCE(sub.SubmittedBandPointsRed, a.BandPointsRed)
                        END
                    WHEN 'Lower' THEN
                        CASE
                            WHEN sub.SubmissionValue <= COALESCE(sub.SubmittedThresholdGreen, a.ThresholdGreen)
                                THEN COALESCE(sub.SubmittedBandPointsGreen, a.BandPointsGreen)
                            WHEN sub.SubmissionValue <= COALESCE(sub.SubmittedThresholdAmber, a.ThresholdAmber)
                                THEN COALESCE(sub.SubmittedBandPointsAmber, a.BandPointsAmber)
                            ELSE COALESCE(sub.SubmittedBandPointsRed, a.BandPointsRed)
                        END
                    ELSE NULL
                END
        END AS Score
) AS num
WHERE a.IsActive = 1;
GO

-- ============================================================
-- App.vSiteCompositeScore — site × period × category roll-up + composite
-- ============================================================
-- Returns one row per (Account, Site, Period, Category) so the frontend
-- can render both the per-category breakdown panel and the site-level
-- composite (same value across all category rows for that site×period).

CREATE OR ALTER VIEW App.vSiteCompositeScore
AS
WITH per_category AS (
    SELECT
        s.AccountId,
        s.SiteOrgUnitId,
        s.PeriodID,
        s.Category,
        SUM(CASE WHEN s.Score IS NULL THEN 0 ELSE s.Score * s.KpiWeight END) AS WeightedScore,
        SUM(CASE WHEN s.Score IS NULL THEN 0 ELSE s.KpiWeight END)           AS WeightSum,
        SUM(CASE WHEN s.Score IS NOT NULL THEN 1 ELSE 0 END)                  AS ScoredCount,
        COUNT(*)                                                              AS TotalCount
    FROM App.vKpiSubmissionScores AS s
    WHERE s.SiteOrgUnitId IS NOT NULL          -- skip account-wide assignments at this layer
    GROUP BY s.AccountId, s.SiteOrgUnitId, s.PeriodID, s.Category
),
weighted AS (
    SELECT
        pc.AccountId, pc.SiteOrgUnitId, pc.PeriodID, pc.Category,
        pc.ScoredCount, pc.TotalCount,
        CASE WHEN pc.WeightSum = 0 THEN NULL
             ELSE pc.WeightedScore / pc.WeightSum
        END                                AS CategoryScore,
        ISNULL(cw.Weight, 1.0)             AS CategoryWeight,
        CAST(ISNULL(cw.IsActive, 1) AS BIT) AS CategoryActive
    FROM per_category AS pc
    LEFT JOIN KPI.CategoryWeight AS cw
      ON cw.AccountId = pc.AccountId AND cw.Category = pc.Category
)
SELECT
    w.AccountId,
    w.SiteOrgUnitId,
    w.PeriodID,
    w.Category,
    w.CategoryScore,
    w.CategoryWeight,
    w.CategoryActive,
    w.ScoredCount,
    w.TotalCount,
    SUM(CASE WHEN w.CategoryScore IS NULL OR w.CategoryActive = 0
             THEN 0 ELSE w.CategoryScore * w.CategoryWeight END)
        OVER (PARTITION BY w.AccountId, w.SiteOrgUnitId, w.PeriodID)
    /
    NULLIF(SUM(CASE WHEN w.CategoryScore IS NULL OR w.CategoryActive = 0
                    THEN 0 ELSE w.CategoryWeight END)
        OVER (PARTITION BY w.AccountId, w.SiteOrgUnitId, w.PeriodID), 0)
        AS CompositeScore
FROM weighted AS w;
GO
