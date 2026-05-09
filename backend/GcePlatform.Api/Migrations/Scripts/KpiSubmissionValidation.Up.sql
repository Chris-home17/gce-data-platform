-- ============================================================
-- Migration: KpiSubmissionValidation — Up
-- Adds optional per-assignment validation rules:
--   * Min / Max / Precision for numeric-like data types
--   * Regex for text/dropdown advanced format checks
--   * Custom error message that overrides the default phrasing
--
-- All five fields are NULL by default — existing assignments and
-- submissions carry on exactly as today (no validation runs).
--
-- Snapshot pattern (matches thresholds + scoring):
--   * Rules captured onto KPI.Submission at first INSERT
--   * usp_SubmitKpi takes the rules as @SubmittedValidation* params
--     and snapshots them; it does NOT re-execute the rules. The
--     authoritative validation runs in the C# endpoint before the
--     proc is called (regex isn't natively supported in T-SQL).
-- ============================================================

-- ─── KPI.AssignmentTemplate ──────────────────────────────────

IF COL_LENGTH('KPI.AssignmentTemplate', 'ValidationMinValue') IS NULL
    ALTER TABLE KPI.AssignmentTemplate ADD ValidationMinValue DECIMAL(18,4) NULL;
GO
IF COL_LENGTH('KPI.AssignmentTemplate', 'ValidationMaxValue') IS NULL
    ALTER TABLE KPI.AssignmentTemplate ADD ValidationMaxValue DECIMAL(18,4) NULL;
GO
IF COL_LENGTH('KPI.AssignmentTemplate', 'ValidationPrecision') IS NULL
    ALTER TABLE KPI.AssignmentTemplate ADD ValidationPrecision INT NULL;
GO
IF COL_LENGTH('KPI.AssignmentTemplate', 'ValidationRegex') IS NULL
    ALTER TABLE KPI.AssignmentTemplate ADD ValidationRegex NVARCHAR(500) NULL;
GO
IF COL_LENGTH('KPI.AssignmentTemplate', 'ValidationMessage') IS NULL
    ALTER TABLE KPI.AssignmentTemplate ADD ValidationMessage NVARCHAR(500) NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE name = 'CK_KpiTpl_ValidationPrecision'
      AND parent_object_id = OBJECT_ID(N'KPI.AssignmentTemplate')
)
    ALTER TABLE KPI.AssignmentTemplate
        ADD CONSTRAINT CK_KpiTpl_ValidationPrecision
            CHECK (ValidationPrecision IS NULL OR ValidationPrecision BETWEEN 0 AND 8);
GO

-- ─── KPI.Assignment (mirror) ─────────────────────────────────

IF COL_LENGTH('KPI.Assignment', 'ValidationMinValue') IS NULL
    ALTER TABLE KPI.Assignment ADD ValidationMinValue DECIMAL(18,4) NULL;
GO
IF COL_LENGTH('KPI.Assignment', 'ValidationMaxValue') IS NULL
    ALTER TABLE KPI.Assignment ADD ValidationMaxValue DECIMAL(18,4) NULL;
GO
IF COL_LENGTH('KPI.Assignment', 'ValidationPrecision') IS NULL
    ALTER TABLE KPI.Assignment ADD ValidationPrecision INT NULL;
GO
IF COL_LENGTH('KPI.Assignment', 'ValidationRegex') IS NULL
    ALTER TABLE KPI.Assignment ADD ValidationRegex NVARCHAR(500) NULL;
GO
IF COL_LENGTH('KPI.Assignment', 'ValidationMessage') IS NULL
    ALTER TABLE KPI.Assignment ADD ValidationMessage NVARCHAR(500) NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE name = 'CK_KpiAsgn_ValidationPrecision'
      AND parent_object_id = OBJECT_ID(N'KPI.Assignment')
)
    ALTER TABLE KPI.Assignment
        ADD CONSTRAINT CK_KpiAsgn_ValidationPrecision
            CHECK (ValidationPrecision IS NULL OR ValidationPrecision BETWEEN 0 AND 8);
GO

-- ─── KPI.Submission (snapshot columns) ───────────────────────

IF COL_LENGTH('KPI.Submission', 'SubmittedValidationMinValue') IS NULL
    ALTER TABLE KPI.Submission ADD SubmittedValidationMinValue DECIMAL(18,4) NULL;
GO
IF COL_LENGTH('KPI.Submission', 'SubmittedValidationMaxValue') IS NULL
    ALTER TABLE KPI.Submission ADD SubmittedValidationMaxValue DECIMAL(18,4) NULL;
GO
IF COL_LENGTH('KPI.Submission', 'SubmittedValidationPrecision') IS NULL
    ALTER TABLE KPI.Submission ADD SubmittedValidationPrecision INT NULL;
GO
IF COL_LENGTH('KPI.Submission', 'SubmittedValidationRegex') IS NULL
    ALTER TABLE KPI.Submission ADD SubmittedValidationRegex NVARCHAR(500) NULL;
GO
IF COL_LENGTH('KPI.Submission', 'SubmittedValidationMessage') IS NULL
    ALTER TABLE KPI.Submission ADD SubmittedValidationMessage NVARCHAR(500) NULL;
GO

-- ============================================================
-- usp_AssignKpi — accept and persist five validation params
-- ============================================================

CREATE OR ALTER PROCEDURE App.usp_AssignKpi
    @KPICode                NVARCHAR(50),
    @AccountCode            NVARCHAR(50),
    @OrgUnitCode            NVARCHAR(50)    = NULL,
    @OrgUnitType            NVARCHAR(20)    = 'Site',
    @PeriodScheduleID       INT,
    @PeriodYear             SMALLINT,
    @PeriodMonth            TINYINT,
    @AssignmentTemplateID   INT             = NULL,
    @IsRequired             BIT             = 1,
    @TargetValue            DECIMAL(18,4)   = NULL,
    @ThresholdGreen         DECIMAL(18,4)   = NULL,
    @ThresholdAmber         DECIMAL(18,4)   = NULL,
    @ThresholdRed           DECIMAL(18,4)   = NULL,
    @ThresholdDirection     NVARCHAR(10)    = NULL,
    @SubmitterGuidance      NVARCHAR(1000)  = NULL,
    @AssignmentGroupName    NVARCHAR(100)   = NULL,
    @KpiWeight              DECIMAL(9,4)    = 1.0,
    @ScoringMode            NVARCHAR(10)    = 'Band',
    @BandPointsGreen        DECIMAL(9,4)    = 100,
    @BandPointsAmber        DECIMAL(9,4)    = 50,
    @BandPointsRed          DECIMAL(9,4)    = 0,
    @BooleanYesPoints       DECIMAL(9,4)    = NULL,
    @BooleanNoPoints        DECIMAL(9,4)    = NULL,
    @MultiSelectScoreRule   NVARCHAR(10)    = NULL,
    @PenaliseMissingOnScore BIT             = 1,
    @CategoryWeightSnapshot DECIMAL(9,4)    = NULL,
    @ValidationMinValue     DECIMAL(18,4)   = NULL,
    @ValidationMaxValue     DECIMAL(18,4)   = NULL,
    @ValidationPrecision    INT             = NULL,
    @ValidationRegex        NVARCHAR(500)   = NULL,
    @ValidationMessage      NVARCHAR(500)   = NULL,
    @ActorUPN               NVARCHAR(320)   = NULL,
    @AssignmentID           INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @KPIID INT = (SELECT KPIID FROM KPI.Definition WHERE KPICode = @KPICode AND IsActive = 1);
    IF @KPIID IS NULL THROW 50110, 'KPI not found or inactive for provided KPICode.', 1;

    DECLARE @AccountId INT = (SELECT AccountId FROM Dim.Account WHERE AccountCode = @AccountCode AND IsActive = 1);
    IF @AccountId IS NULL THROW 50111, 'Account not found or inactive.', 1;

    DECLARE @OrgUnitId INT = NULL;
    IF @OrgUnitCode IS NOT NULL
    BEGIN
        SELECT @OrgUnitId = OrgUnitId FROM Dim.OrgUnit
        WHERE AccountId = @AccountId AND OrgUnitCode = @OrgUnitCode AND OrgUnitType = @OrgUnitType AND IsActive = 1;
        IF @OrgUnitId IS NULL THROW 50112, 'OrgUnit not found or inactive for provided AccountCode + OrgUnitCode.', 1;
    END

    DECLARE @PeriodID INT = (
        SELECT PeriodID FROM KPI.Period
        WHERE PeriodScheduleID = @PeriodScheduleID AND PeriodYear = @PeriodYear AND PeriodMonth = @PeriodMonth
    );
    IF @PeriodID IS NULL THROW 50113, 'Period not found for this schedule/year/month. Create the period first using App.usp_UpsertKpiPeriod.', 1;

    DECLARE @ActorPrincipalId INT = NULL;
    IF @ActorUPN IS NOT NULL SELECT @ActorPrincipalId = UserId FROM Sec.[User] WHERE UPN = @ActorUPN;

    -- Default CategoryWeightSnapshot to live account weight if caller didn't pass one.
    IF @CategoryWeightSnapshot IS NULL
    BEGIN
        SELECT @CategoryWeightSnapshot = ISNULL(cw.Weight, 1.0)
        FROM KPI.Definition AS d
        LEFT JOIN KPI.CategoryWeight AS cw
            ON cw.AccountId = @AccountId AND cw.Category = d.Category
        WHERE d.KPIID = @KPIID;
    END

    IF @OrgUnitId IS NULL
    BEGIN
        SET @AssignmentID = (
            SELECT AssignmentID FROM KPI.Assignment
            WHERE KPIID = @KPIID AND AccountId = @AccountId AND OrgUnitId IS NULL AND PeriodID = @PeriodID
              AND ((@AssignmentGroupName IS NULL AND AssignmentGroupName IS NULL) OR AssignmentGroupName = @AssignmentGroupName)
        );
    END
    ELSE
    BEGIN
        SET @AssignmentID = (
            SELECT AssignmentID FROM KPI.Assignment
            WHERE KPIID = @KPIID AND OrgUnitId = @OrgUnitId AND PeriodID = @PeriodID
              AND ((@AssignmentGroupName IS NULL AND AssignmentGroupName IS NULL) OR AssignmentGroupName = @AssignmentGroupName)
        );
    END

    IF @AssignmentID IS NULL
    BEGIN
        INSERT INTO KPI.Assignment
            (KPIID, AccountId, OrgUnitId, PeriodID, AssignmentTemplateID, IsRequired,
             TargetValue, ThresholdGreen, ThresholdAmber, ThresholdRed,
             ThresholdDirection, SubmitterGuidance, AssignedByPrincipalId, AssignmentGroupName,
             KpiWeight, ScoringMode, BandPointsGreen, BandPointsAmber, BandPointsRed,
             BooleanYesPoints, BooleanNoPoints, MultiSelectScoreRule, PenaliseMissingOnScore,
             CategoryWeightSnapshot,
             ValidationMinValue, ValidationMaxValue, ValidationPrecision, ValidationRegex, ValidationMessage)
        VALUES
            (@KPIID, @AccountId, @OrgUnitId, @PeriodID, @AssignmentTemplateID, @IsRequired,
             @TargetValue, @ThresholdGreen, @ThresholdAmber, @ThresholdRed,
             @ThresholdDirection, @SubmitterGuidance, @ActorPrincipalId, @AssignmentGroupName,
             @KpiWeight, @ScoringMode, @BandPointsGreen, @BandPointsAmber, @BandPointsRed,
             @BooleanYesPoints, @BooleanNoPoints, @MultiSelectScoreRule, @PenaliseMissingOnScore,
             @CategoryWeightSnapshot,
             @ValidationMinValue, @ValidationMaxValue, @ValidationPrecision, @ValidationRegex, @ValidationMessage);

        SET @AssignmentID = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE KPI.Assignment
        SET IsRequired             = @IsRequired,
            TargetValue            = @TargetValue,
            ThresholdGreen         = @ThresholdGreen,
            ThresholdAmber         = @ThresholdAmber,
            ThresholdRed           = @ThresholdRed,
            ThresholdDirection     = @ThresholdDirection,
            SubmitterGuidance      = @SubmitterGuidance,
            KpiWeight              = @KpiWeight,
            ScoringMode            = @ScoringMode,
            BandPointsGreen        = @BandPointsGreen,
            BandPointsAmber        = @BandPointsAmber,
            BandPointsRed          = @BandPointsRed,
            BooleanYesPoints       = @BooleanYesPoints,
            BooleanNoPoints        = @BooleanNoPoints,
            MultiSelectScoreRule   = @MultiSelectScoreRule,
            PenaliseMissingOnScore = @PenaliseMissingOnScore,
            -- CategoryWeightSnapshot deliberately NOT touched on UPDATE (locked).
            ValidationMinValue     = @ValidationMinValue,
            ValidationMaxValue     = @ValidationMaxValue,
            ValidationPrecision    = @ValidationPrecision,
            ValidationRegex        = @ValidationRegex,
            ValidationMessage      = @ValidationMessage,
            IsActive               = 1,
            ModifiedOnUtc          = SYSUTCDATETIME(),
            ModifiedBy             = COALESCE(@ActorUPN, SESSION_USER)
        WHERE AssignmentID = @AssignmentID;
    END
END;
GO

-- ============================================================
-- usp_UpsertKpiAssignmentTemplate — accept five new validation params
-- ============================================================

CREATE OR ALTER PROCEDURE App.usp_UpsertKpiAssignmentTemplate
    @KPICode                NVARCHAR(50),
    @PeriodScheduleID       INT,
    @AccountCode            NVARCHAR(50),
    @OrgUnitCode            NVARCHAR(50)    = NULL,
    @OrgUnitType            NVARCHAR(20)    = 'Site',
    @StartPeriodYear        SMALLINT        = NULL,
    @StartPeriodMonth       TINYINT         = NULL,
    @EndPeriodYear          SMALLINT        = NULL,
    @EndPeriodMonth         TINYINT         = NULL,
    @IsRequired             BIT             = 1,
    @TargetValue            DECIMAL(18,4)   = NULL,
    @ThresholdGreen         DECIMAL(18,4)   = NULL,
    @ThresholdAmber         DECIMAL(18,4)   = NULL,
    @ThresholdRed           DECIMAL(18,4)   = NULL,
    @ThresholdDirection     NVARCHAR(10)    = NULL,
    @SubmitterGuidance      NVARCHAR(1000)  = NULL,
    @CustomKpiName          NVARCHAR(200)   = NULL,
    @CustomKpiDescription   NVARCHAR(1000)  = NULL,
    @KpiPackageId           INT             = NULL,
    @AssignmentGroupName    NVARCHAR(100)   = NULL,
    @KpiWeight              DECIMAL(9,4)    = NULL,
    @ScoringMode            NVARCHAR(10)    = NULL,
    @BandPointsGreen        DECIMAL(9,4)    = NULL,
    @BandPointsAmber        DECIMAL(9,4)    = NULL,
    @BandPointsRed          DECIMAL(9,4)    = NULL,
    @BooleanYesPoints       DECIMAL(9,4)    = NULL,
    @BooleanNoPoints        DECIMAL(9,4)    = NULL,
    @MultiSelectScoreRule   NVARCHAR(10)    = NULL,
    @PenaliseMissingOnScore BIT             = NULL,
    @OptionPoints           NVARCHAR(MAX)   = NULL,
    @ValidationMinValue     DECIMAL(18,4)   = NULL,
    @ValidationMaxValue     DECIMAL(18,4)   = NULL,
    @ValidationPrecision    INT             = NULL,
    @ValidationRegex        NVARCHAR(500)   = NULL,
    @ValidationMessage      NVARCHAR(500)   = NULL,
    @ActorUPN               NVARCHAR(320)   = NULL,
    @AssignmentTemplateID   INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF (@StartPeriodYear IS NULL AND @StartPeriodMonth IS NOT NULL)
       OR (@StartPeriodYear IS NOT NULL AND @StartPeriodMonth IS NULL)
        THROW 50129, 'Start period year and month must both be provided or both be NULL.', 1;
    IF @StartPeriodMonth IS NOT NULL AND @StartPeriodMonth NOT BETWEEN 1 AND 12
        THROW 50130, 'StartPeriodMonth must be between 1 and 12.', 1;
    IF (@EndPeriodYear IS NULL AND @EndPeriodMonth IS NOT NULL)
       OR (@EndPeriodYear IS NOT NULL AND @EndPeriodMonth IS NULL)
        THROW 50131, 'End period year and month must both be provided or both be NULL.', 1;
    IF @EndPeriodMonth IS NOT NULL AND @EndPeriodMonth NOT BETWEEN 1 AND 12
        THROW 50132, 'EndPeriodMonth must be between 1 and 12.', 1;
    IF @StartPeriodYear IS NOT NULL AND @EndPeriodYear IS NOT NULL
       AND (@EndPeriodYear * 100 + @EndPeriodMonth) < (@StartPeriodYear * 100 + @StartPeriodMonth)
        THROW 50133, 'End period must be on or after the start period.', 1;

    DECLARE @KPIID INT = (SELECT KPIID FROM KPI.Definition WHERE KPICode = @KPICode AND IsActive = 1);
    IF @KPIID IS NULL THROW 50134, 'KPI not found or inactive for provided KPICode.', 1;
    IF NOT EXISTS (SELECT 1 FROM KPI.PeriodSchedule WHERE PeriodScheduleID = @PeriodScheduleID AND IsActive = 1)
        THROW 50137, 'Schedule not found or inactive.', 1;

    DECLARE @ScheduleStartDate DATE, @ScheduleEndDate DATE;
    SELECT @ScheduleStartDate = StartDate, @ScheduleEndDate = EndDate
    FROM KPI.PeriodSchedule WHERE PeriodScheduleID = @PeriodScheduleID AND IsActive = 1;

    IF @StartPeriodYear IS NULL OR @StartPeriodMonth IS NULL
    BEGIN SET @StartPeriodYear = YEAR(@ScheduleStartDate); SET @StartPeriodMonth = MONTH(@ScheduleStartDate); END
    IF @EndPeriodYear IS NULL AND @EndPeriodMonth IS NULL AND @ScheduleEndDate IS NOT NULL
    BEGIN SET @EndPeriodYear = YEAR(@ScheduleEndDate); SET @EndPeriodMonth = MONTH(@ScheduleEndDate); END

    DECLARE @AccountId INT = (SELECT AccountId FROM Dim.Account WHERE AccountCode = @AccountCode AND IsActive = 1);
    IF @AccountId IS NULL THROW 50135, 'Account not found or inactive.', 1;

    DECLARE @OrgUnitId INT = NULL;
    IF @OrgUnitCode IS NOT NULL
    BEGIN
        SELECT @OrgUnitId = OrgUnitId FROM Dim.OrgUnit
        WHERE AccountId = @AccountId AND OrgUnitCode = @OrgUnitCode AND OrgUnitType = @OrgUnitType AND IsActive = 1;
        IF @OrgUnitId IS NULL THROW 50136, 'OrgUnit not found or inactive for provided AccountCode + OrgUnitCode.', 1;
    END

    SET @AssignmentTemplateID = (
        SELECT AssignmentTemplateID FROM KPI.AssignmentTemplate
        WHERE KPIID = @KPIID AND PeriodScheduleID = @PeriodScheduleID AND AccountId = @AccountId
          AND ((@OrgUnitId IS NULL AND OrgUnitId IS NULL) OR OrgUnitId = @OrgUnitId)
          AND ((@AssignmentGroupName IS NULL AND AssignmentGroupName IS NULL) OR AssignmentGroupName = @AssignmentGroupName)
    );

    IF @AssignmentTemplateID IS NULL
    BEGIN
        DECLARE @SnapCategoryWeight DECIMAL(9,4);
        SELECT @SnapCategoryWeight = ISNULL(cw.Weight, 1.0)
        FROM KPI.Definition AS d
        LEFT JOIN KPI.CategoryWeight AS cw
            ON cw.AccountId = @AccountId AND cw.Category = d.Category
        WHERE d.KPIID = @KPIID;

        INSERT INTO KPI.AssignmentTemplate
            (KPIID, PeriodScheduleID, AccountId, OrgUnitId, StartPeriodYear, StartPeriodMonth, EndPeriodYear, EndPeriodMonth,
             IsRequired, TargetValue, ThresholdGreen, ThresholdAmber, ThresholdRed, ThresholdDirection, SubmitterGuidance,
             CustomKpiName, CustomKpiDescription, KpiPackageId, AssignmentGroupName,
             KpiWeight, ScoringMode, BandPointsGreen, BandPointsAmber, BandPointsRed,
             BooleanYesPoints, BooleanNoPoints, MultiSelectScoreRule, PenaliseMissingOnScore,
             CategoryWeightSnapshot,
             ValidationMinValue, ValidationMaxValue, ValidationPrecision, ValidationRegex, ValidationMessage)
        VALUES
            (@KPIID, @PeriodScheduleID, @AccountId, @OrgUnitId, @StartPeriodYear, @StartPeriodMonth, @EndPeriodYear, @EndPeriodMonth,
             @IsRequired, @TargetValue, @ThresholdGreen, @ThresholdAmber, @ThresholdRed, @ThresholdDirection, @SubmitterGuidance,
             @CustomKpiName, @CustomKpiDescription, @KpiPackageId, @AssignmentGroupName,
             COALESCE(@KpiWeight, 1.0), COALESCE(@ScoringMode, 'Band'),
             COALESCE(@BandPointsGreen, 100), COALESCE(@BandPointsAmber, 50), COALESCE(@BandPointsRed, 0),
             @BooleanYesPoints, @BooleanNoPoints, @MultiSelectScoreRule,
             COALESCE(@PenaliseMissingOnScore, @IsRequired),
             @SnapCategoryWeight,
             @ValidationMinValue, @ValidationMaxValue, @ValidationPrecision, @ValidationRegex, @ValidationMessage);

        SET @AssignmentTemplateID = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE KPI.AssignmentTemplate
        SET PeriodScheduleID       = @PeriodScheduleID,
            StartPeriodYear        = @StartPeriodYear,
            StartPeriodMonth       = @StartPeriodMonth,
            EndPeriodYear          = @EndPeriodYear,
            EndPeriodMonth         = @EndPeriodMonth,
            IsRequired             = @IsRequired,
            TargetValue            = @TargetValue,
            ThresholdGreen         = @ThresholdGreen,
            ThresholdAmber         = @ThresholdAmber,
            ThresholdRed           = @ThresholdRed,
            ThresholdDirection     = @ThresholdDirection,
            SubmitterGuidance      = @SubmitterGuidance,
            CustomKpiName          = @CustomKpiName,
            CustomKpiDescription   = @CustomKpiDescription,
            KpiPackageId           = @KpiPackageId,
            KpiWeight              = COALESCE(@KpiWeight, KpiWeight),
            ScoringMode            = COALESCE(@ScoringMode, ScoringMode),
            BandPointsGreen        = COALESCE(@BandPointsGreen, BandPointsGreen),
            BandPointsAmber        = COALESCE(@BandPointsAmber, BandPointsAmber),
            BandPointsRed          = COALESCE(@BandPointsRed, BandPointsRed),
            BooleanYesPoints       = @BooleanYesPoints,
            BooleanNoPoints        = @BooleanNoPoints,
            MultiSelectScoreRule   = @MultiSelectScoreRule,
            PenaliseMissingOnScore = COALESCE(@PenaliseMissingOnScore, PenaliseMissingOnScore),
            -- Validation rules: admin can tighten/relax any time; not locked.
            ValidationMinValue     = @ValidationMinValue,
            ValidationMaxValue     = @ValidationMaxValue,
            ValidationPrecision    = @ValidationPrecision,
            ValidationRegex        = @ValidationRegex,
            ValidationMessage      = @ValidationMessage,
            IsActive               = 1,
            ModifiedOnUtc          = SYSUTCDATETIME(),
            ModifiedBy             = COALESCE(@ActorUPN, SESSION_USER)
        WHERE AssignmentTemplateID = @AssignmentTemplateID;
    END

    IF @OptionPoints IS NOT NULL
    BEGIN
        DELETE FROM KPI.AssignmentTemplateDropDownOption
        WHERE AssignmentTemplateID = @AssignmentTemplateID;

        INSERT INTO KPI.AssignmentTemplateDropDownOption
            (AssignmentTemplateID, OptionValue, SortOrder, Points)
        SELECT
            @AssignmentTemplateID,
            JSON_VALUE(j.[value], '$.value'),
            ISNULL(TRY_CAST(JSON_VALUE(j.[value], '$.sortOrder') AS INT), CAST(j.[key] AS INT)),
            ISNULL(TRY_CAST(JSON_VALUE(j.[value], '$.points')    AS DECIMAL(9,4)), 0)
        FROM OPENJSON(@OptionPoints) AS j
        WHERE JSON_VALUE(j.[value], '$.value') IS NOT NULL;
    END
END;
GO

-- ============================================================
-- usp_MaterializeKpiAssignmentTemplates — pass validation through
-- ============================================================

CREATE OR ALTER PROCEDURE App.usp_MaterializeKpiAssignmentTemplates
    @AssignmentTemplateID   INT           = NULL,
    @PeriodScheduleIDFilter INT           = NULL,
    @ActorUPN               NVARCHAR(320) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @CurrentTemplateId INT, @TemplateKpiCode NVARCHAR(50), @TemplateScheduleId INT,
        @TemplateScheduleStartDate DATE, @TemplateScheduleEndDate DATE,
        @TemplateAccountCode NVARCHAR(50), @TemplateOrgUnitCode NVARCHAR(50),
        @TemplateOrgUnitType NVARCHAR(20),
        @TemplateStartYear SMALLINT, @TemplateStartMonth TINYINT,
        @TemplateEndYear SMALLINT, @TemplateEndMonth TINYINT,
        @TemplateIsRequired BIT, @TemplateTargetValue DECIMAL(18,4),
        @TemplateThresholdGreen DECIMAL(18,4), @TemplateThresholdAmber DECIMAL(18,4), @TemplateThresholdRed DECIMAL(18,4),
        @TemplateThresholdDirection NVARCHAR(10), @TemplateSubmitterGuidance NVARCHAR(1000), @TemplateGroupName NVARCHAR(100),
        @TemplateKpiWeight DECIMAL(9,4), @TemplateScoringMode NVARCHAR(10),
        @TemplateBandG DECIMAL(9,4), @TemplateBandA DECIMAL(9,4), @TemplateBandR DECIMAL(9,4),
        @TemplateBoolY DECIMAL(9,4), @TemplateBoolN DECIMAL(9,4),
        @TemplateMSRule NVARCHAR(10), @TemplatePenaliseMissing BIT,
        @TemplateCategoryWeightSnapshot DECIMAL(9,4),
        @TemplateValidationMin DECIMAL(18,4),
        @TemplateValidationMax DECIMAL(18,4),
        @TemplateValidationPrecision INT,
        @TemplateValidationRegex NVARCHAR(500),
        @TemplateValidationMessage NVARCHAR(500),
        @SiteOrgUnitCode NVARCHAR(50);

    DECLARE template_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT t.AssignmentTemplateID, d.KPICode, t.PeriodScheduleID, sched.StartDate, sched.EndDate,
               acct.AccountCode, ou.OrgUnitCode, COALESCE(ou.OrgUnitType, 'Site'),
               t.StartPeriodYear, t.StartPeriodMonth, t.EndPeriodYear, t.EndPeriodMonth,
               t.IsRequired, t.TargetValue, t.ThresholdGreen, t.ThresholdAmber, t.ThresholdRed,
               t.ThresholdDirection, t.SubmitterGuidance, t.AssignmentGroupName,
               t.KpiWeight, t.ScoringMode,
               t.BandPointsGreen, t.BandPointsAmber, t.BandPointsRed,
               t.BooleanYesPoints, t.BooleanNoPoints,
               t.MultiSelectScoreRule, t.PenaliseMissingOnScore,
               t.CategoryWeightSnapshot,
               t.ValidationMinValue, t.ValidationMaxValue, t.ValidationPrecision,
               t.ValidationRegex, t.ValidationMessage
        FROM KPI.AssignmentTemplate AS t
        JOIN KPI.Definition         AS d     ON d.KPIID              = t.KPIID
        JOIN KPI.PeriodSchedule     AS sched ON sched.PeriodScheduleID = t.PeriodScheduleID
        JOIN Dim.Account            AS acct  ON acct.AccountId       = t.AccountId
        LEFT JOIN Dim.OrgUnit       AS ou    ON ou.OrgUnitId         = t.OrgUnitId
        WHERE t.IsActive = 1 AND sched.IsActive = 1
          AND (@AssignmentTemplateID   IS NULL OR t.AssignmentTemplateID = @AssignmentTemplateID)
          AND (@PeriodScheduleIDFilter IS NULL OR t.PeriodScheduleID    = @PeriodScheduleIDFilter)
        ORDER BY t.AssignmentTemplateID;

    OPEN template_cursor;
    FETCH NEXT FROM template_cursor INTO
        @CurrentTemplateId, @TemplateKpiCode, @TemplateScheduleId, @TemplateScheduleStartDate, @TemplateScheduleEndDate,
        @TemplateAccountCode, @TemplateOrgUnitCode, @TemplateOrgUnitType,
        @TemplateStartYear, @TemplateStartMonth, @TemplateEndYear, @TemplateEndMonth, @TemplateIsRequired,
        @TemplateTargetValue, @TemplateThresholdGreen, @TemplateThresholdAmber, @TemplateThresholdRed,
        @TemplateThresholdDirection, @TemplateSubmitterGuidance, @TemplateGroupName,
        @TemplateKpiWeight, @TemplateScoringMode, @TemplateBandG, @TemplateBandA, @TemplateBandR,
        @TemplateBoolY, @TemplateBoolN, @TemplateMSRule, @TemplatePenaliseMissing,
        @TemplateCategoryWeightSnapshot,
        @TemplateValidationMin, @TemplateValidationMax, @TemplateValidationPrecision,
        @TemplateValidationRegex, @TemplateValidationMessage;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @CurrentPeriodYear SMALLINT, @CurrentPeriodMonth TINYINT;

        DECLARE period_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT PeriodYear, PeriodMonth FROM KPI.Period
            WHERE PeriodScheduleID = @TemplateScheduleId
              AND (PeriodYear * 100 + PeriodMonth) >= (
                    COALESCE(@TemplateStartYear, YEAR(@TemplateScheduleStartDate)) * 100
                    + COALESCE(@TemplateStartMonth, MONTH(@TemplateScheduleStartDate)))
              AND (@TemplateEndYear IS NULL
                   OR (PeriodYear * 100 + PeriodMonth) <= (@TemplateEndYear * 100 + @TemplateEndMonth))
            ORDER BY PeriodYear, PeriodMonth;

        OPEN period_cursor;
        FETCH NEXT FROM period_cursor INTO @CurrentPeriodYear, @CurrentPeriodMonth;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            DECLARE @GeneratedAssignmentId INT;

            IF @TemplateOrgUnitCode IS NULL
            BEGIN
                DECLARE site_cursor CURSOR LOCAL FAST_FORWARD FOR
                    SELECT ou.OrgUnitCode FROM Dim.OrgUnit AS ou
                    JOIN Dim.Account AS acct ON acct.AccountId = ou.AccountId
                    WHERE acct.AccountCode = @TemplateAccountCode AND ou.OrgUnitType = 'Site' AND ou.IsActive = 1;

                OPEN site_cursor;
                FETCH NEXT FROM site_cursor INTO @SiteOrgUnitCode;

                WHILE @@FETCH_STATUS = 0
                BEGIN
                    SET @GeneratedAssignmentId = NULL;
                    EXEC App.usp_AssignKpi
                        @KPICode = @TemplateKpiCode, @AccountCode = @TemplateAccountCode,
                        @OrgUnitCode = @SiteOrgUnitCode, @OrgUnitType = 'Site',
                        @PeriodScheduleID = @TemplateScheduleId,
                        @PeriodYear = @CurrentPeriodYear, @PeriodMonth = @CurrentPeriodMonth,
                        @AssignmentTemplateID = @CurrentTemplateId,
                        @IsRequired = @TemplateIsRequired, @TargetValue = @TemplateTargetValue,
                        @ThresholdGreen = @TemplateThresholdGreen, @ThresholdAmber = @TemplateThresholdAmber,
                        @ThresholdRed = @TemplateThresholdRed, @ThresholdDirection = @TemplateThresholdDirection,
                        @SubmitterGuidance = @TemplateSubmitterGuidance, @AssignmentGroupName = @TemplateGroupName,
                        @KpiWeight = @TemplateKpiWeight, @ScoringMode = @TemplateScoringMode,
                        @BandPointsGreen = @TemplateBandG, @BandPointsAmber = @TemplateBandA, @BandPointsRed = @TemplateBandR,
                        @BooleanYesPoints = @TemplateBoolY, @BooleanNoPoints = @TemplateBoolN,
                        @MultiSelectScoreRule = @TemplateMSRule, @PenaliseMissingOnScore = @TemplatePenaliseMissing,
                        @CategoryWeightSnapshot = @TemplateCategoryWeightSnapshot,
                        @ValidationMinValue = @TemplateValidationMin,
                        @ValidationMaxValue = @TemplateValidationMax,
                        @ValidationPrecision = @TemplateValidationPrecision,
                        @ValidationRegex = @TemplateValidationRegex,
                        @ValidationMessage = @TemplateValidationMessage,
                        @ActorUPN = @ActorUPN, @AssignmentID = @GeneratedAssignmentId OUTPUT;

                    FETCH NEXT FROM site_cursor INTO @SiteOrgUnitCode;
                END
                CLOSE site_cursor; DEALLOCATE site_cursor;
            END
            ELSE
            BEGIN
                SET @GeneratedAssignmentId = NULL;
                EXEC App.usp_AssignKpi
                    @KPICode = @TemplateKpiCode, @AccountCode = @TemplateAccountCode,
                    @OrgUnitCode = @TemplateOrgUnitCode, @OrgUnitType = @TemplateOrgUnitType,
                    @PeriodScheduleID = @TemplateScheduleId,
                    @PeriodYear = @CurrentPeriodYear, @PeriodMonth = @CurrentPeriodMonth,
                    @AssignmentTemplateID = @CurrentTemplateId,
                    @IsRequired = @TemplateIsRequired, @TargetValue = @TemplateTargetValue,
                    @ThresholdGreen = @TemplateThresholdGreen, @ThresholdAmber = @TemplateThresholdAmber,
                    @ThresholdRed = @TemplateThresholdRed, @ThresholdDirection = @TemplateThresholdDirection,
                    @SubmitterGuidance = @TemplateSubmitterGuidance, @AssignmentGroupName = @TemplateGroupName,
                    @KpiWeight = @TemplateKpiWeight, @ScoringMode = @TemplateScoringMode,
                    @BandPointsGreen = @TemplateBandG, @BandPointsAmber = @TemplateBandA, @BandPointsRed = @TemplateBandR,
                    @BooleanYesPoints = @TemplateBoolY, @BooleanNoPoints = @TemplateBoolN,
                    @MultiSelectScoreRule = @TemplateMSRule, @PenaliseMissingOnScore = @TemplatePenaliseMissing,
                    @CategoryWeightSnapshot = @TemplateCategoryWeightSnapshot,
                    @ValidationMinValue = @TemplateValidationMin,
                    @ValidationMaxValue = @TemplateValidationMax,
                    @ValidationPrecision = @TemplateValidationPrecision,
                    @ValidationRegex = @TemplateValidationRegex,
                    @ValidationMessage = @TemplateValidationMessage,
                    @ActorUPN = @ActorUPN, @AssignmentID = @GeneratedAssignmentId OUTPUT;
            END

            FETCH NEXT FROM period_cursor INTO @CurrentPeriodYear, @CurrentPeriodMonth;
        END

        CLOSE period_cursor; DEALLOCATE period_cursor;

        FETCH NEXT FROM template_cursor INTO
            @CurrentTemplateId, @TemplateKpiCode, @TemplateScheduleId, @TemplateScheduleStartDate, @TemplateScheduleEndDate,
            @TemplateAccountCode, @TemplateOrgUnitCode, @TemplateOrgUnitType,
            @TemplateStartYear, @TemplateStartMonth, @TemplateEndYear, @TemplateEndMonth, @TemplateIsRequired,
            @TemplateTargetValue, @TemplateThresholdGreen, @TemplateThresholdAmber, @TemplateThresholdRed,
            @TemplateThresholdDirection, @TemplateSubmitterGuidance, @TemplateGroupName,
            @TemplateKpiWeight, @TemplateScoringMode, @TemplateBandG, @TemplateBandA, @TemplateBandR,
            @TemplateBoolY, @TemplateBoolN, @TemplateMSRule, @TemplatePenaliseMissing,
            @TemplateCategoryWeightSnapshot,
            @TemplateValidationMin, @TemplateValidationMax, @TemplateValidationPrecision,
            @TemplateValidationRegex, @TemplateValidationMessage;
    END

    CLOSE template_cursor; DEALLOCATE template_cursor;
END;
GO

-- ============================================================
-- usp_CascadeAssignmentTemplateThresholds — cascade validation rules
-- ============================================================

CREATE OR ALTER PROCEDURE App.usp_CascadeAssignmentTemplateThresholds
    @AssignmentTemplateID INT,
    @ActorUPN             NVARCHAR(320) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE a
    SET IsRequired             = t.IsRequired,
        TargetValue            = t.TargetValue,
        ThresholdGreen         = t.ThresholdGreen,
        ThresholdAmber         = t.ThresholdAmber,
        ThresholdRed           = t.ThresholdRed,
        ThresholdDirection     = t.ThresholdDirection,
        SubmitterGuidance      = t.SubmitterGuidance,
        KpiWeight              = t.KpiWeight,
        ScoringMode            = t.ScoringMode,
        BandPointsGreen        = t.BandPointsGreen,
        BandPointsAmber        = t.BandPointsAmber,
        BandPointsRed          = t.BandPointsRed,
        BooleanYesPoints       = t.BooleanYesPoints,
        BooleanNoPoints        = t.BooleanNoPoints,
        MultiSelectScoreRule   = t.MultiSelectScoreRule,
        PenaliseMissingOnScore = t.PenaliseMissingOnScore,
        CategoryWeightSnapshot = t.CategoryWeightSnapshot,
        ValidationMinValue     = t.ValidationMinValue,
        ValidationMaxValue     = t.ValidationMaxValue,
        ValidationPrecision    = t.ValidationPrecision,
        ValidationRegex        = t.ValidationRegex,
        ValidationMessage      = t.ValidationMessage,
        ModifiedOnUtc          = SYSUTCDATETIME(),
        ModifiedBy             = COALESCE(@ActorUPN, SESSION_USER)
    FROM KPI.Assignment         AS a
    JOIN KPI.AssignmentTemplate AS t ON t.AssignmentTemplateID = a.AssignmentTemplateID
    WHERE t.AssignmentTemplateID = @AssignmentTemplateID
      AND NOT EXISTS (SELECT 1 FROM KPI.Submission s WHERE s.AssignmentID = a.AssignmentID);
END;
GO

-- ============================================================
-- usp_SubmitKpi — accept and snapshot validation rules
-- ============================================================
-- Validation itself is enforced in the C# endpoint before this proc
-- is called (regex isn't natively supported in T-SQL). The proc just
-- captures the rules onto KPI.Submission so admins can later see
-- "what rule was this value validated against?".

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

    -- Snapshot block: thresholds + scoring + validation rules.
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
    DECLARE @SnapValMin             DECIMAL(18,4);
    DECLARE @SnapValMax             DECIMAL(18,4);
    DECLARE @SnapValPrecision       INT;
    DECLARE @SnapValRegex           NVARCHAR(500);
    DECLARE @SnapValMessage         NVARCHAR(500);

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
        @SnapTemplateId         = a.AssignmentTemplateID,
        @SnapValMin             = a.ValidationMinValue,
        @SnapValMax             = a.ValidationMaxValue,
        @SnapValPrecision       = a.ValidationPrecision,
        @SnapValRegex           = a.ValidationRegex,
        @SnapValMessage         = a.ValidationMessage
    FROM KPI.Assignment AS a
    JOIN KPI.Definition AS d ON d.KPIID = a.KPIID
    WHERE a.AssignmentID = @AssignmentID;

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
             SubmittedPenaliseMissingOnScore,
             SubmittedValidationMinValue, SubmittedValidationMaxValue, SubmittedValidationPrecision,
             SubmittedValidationRegex, SubmittedValidationMessage)
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
             @SnapPenaliseMissing,
             @SnapValMin, @SnapValMax, @SnapValPrecision,
             @SnapValRegex, @SnapValMessage);

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
SET IsResolved    = 1,
    ResolvedAt    = SYSUTCDATETIME(),
    ModifiedOnUtc = SYSUTCDATETIME()
WHERE OrgUnitId  = @SiteOrgUnitId
  AND PeriodID   = @PeriodID
  AND IsResolved = 0;
        END
    END

    COMMIT;
END;
GO

-- ============================================================
-- vKpiAssignmentTemplates — surface validation rules
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
        t.PenaliseMissingOnScore,
        t.CategoryWeightSnapshot,
        t.ValidationMinValue,
        t.ValidationMaxValue,
        t.ValidationPrecision,
        t.ValidationRegex,
        t.ValidationMessage,
        (
            SELECT opt.OptionValue AS [value],
                   opt.Points      AS [points],
                   opt.SortOrder   AS [sortOrder]
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

-- ============================================================
-- vSubmissionTokenAssignments — surface validation rules so the
-- capture page can run client-side validation.
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
        CAST(CASE WHEN sub.SubmissionID IS NOT NULL THEN 1 ELSE 0 END AS bit) AS IsSubmitted,
        asgn.KpiWeight,
        CAST(100.0 AS DECIMAL(9,4))                             AS MaxScore,
        asgn.ValidationMinValue,
        asgn.ValidationMaxValue,
        asgn.ValidationPrecision,
        asgn.ValidationRegex,
        asgn.ValidationMessage
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
                AND NOT EXISTS (
                    SELECT 1
                    FROM KPI.Assignment AS sa
                    WHERE sa.KPIID = asgn.KPIID
                      AND sa.OrgUnitId = st.SiteOrgUnitId
                      AND sa.PeriodID = st.PeriodId
                      AND sa.IsActive = 1
                      AND ((asgn.AssignmentGroupName IS NULL AND sa.AssignmentGroupName IS NULL)
                            OR sa.AssignmentGroupName = asgn.AssignmentGroupName))
            )
       )
       AND ((st.AssignmentGroupName IS NULL AND asgn.AssignmentGroupName IS NULL)
             OR asgn.AssignmentGroupName = st.AssignmentGroupName)
    JOIN KPI.Definition AS d ON d.KPIID = asgn.KPIID
    LEFT JOIN KPI.AssignmentTemplate AS t ON t.AssignmentTemplateID = asgn.AssignmentTemplateID
    LEFT JOIN KPI.Submission AS sub ON sub.AssignmentID = asgn.AssignmentID;
GO
