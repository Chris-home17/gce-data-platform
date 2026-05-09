-- ============================================================
-- Migration: KpiScoring — Up (Phase 1)
-- Adds the assignment-side scoring layer:
--   * 9 scoring columns on KPI.AssignmentTemplate (KpiWeight, ScoringMode,
--     BandPointsGreen/Amber/Red, BooleanYesPoints/NoPoints,
--     MultiSelectScoreRule, PenaliseMissingOnScore).
--   * Same 9 columns mirrored on KPI.Assignment so materialised
--     assignments carry their scoring config.
--   * Points column on KPI.AssignmentTemplateDropDownOption.
--   * New table KPI.CategoryWeight (per-account weight per KPI category).
--   * New proc usp_UpsertCategoryWeights (JSON-fed bulk upsert).
--   * usp_UpsertKpiAssignmentTemplate, usp_AssignKpi,
--     usp_MaterializeKpiAssignmentTemplates, usp_CascadeAssignmentTemplateThresholds
--     extended to round-trip the new columns.
--
-- Phase 2 (deferred): submission snapshot columns + score views.
--
-- Idempotent: ALTER TABLE ADD guarded with COL_LENGTH IS NULL;
-- CREATE OR ALTER is naturally idempotent.
-- ============================================================

-- ─── KPI.AssignmentTemplate scoring columns ────────────────────

IF COL_LENGTH('KPI.AssignmentTemplate', 'KpiWeight') IS NULL
    ALTER TABLE KPI.AssignmentTemplate
        ADD KpiWeight DECIMAL(9,4) NOT NULL
            CONSTRAINT DF_KpiTpl_KpiWeight DEFAULT (1.0000);
GO

IF COL_LENGTH('KPI.AssignmentTemplate', 'ScoringMode') IS NULL
    ALTER TABLE KPI.AssignmentTemplate
        ADD ScoringMode NVARCHAR(10) NOT NULL
            CONSTRAINT DF_KpiTpl_ScoringMode DEFAULT ('Band');
GO

IF COL_LENGTH('KPI.AssignmentTemplate', 'BandPointsGreen') IS NULL
    ALTER TABLE KPI.AssignmentTemplate
        ADD BandPointsGreen DECIMAL(9,4) NOT NULL
            CONSTRAINT DF_KpiTpl_BandG DEFAULT (100);
GO

IF COL_LENGTH('KPI.AssignmentTemplate', 'BandPointsAmber') IS NULL
    ALTER TABLE KPI.AssignmentTemplate
        ADD BandPointsAmber DECIMAL(9,4) NOT NULL
            CONSTRAINT DF_KpiTpl_BandA DEFAULT (50);
GO

IF COL_LENGTH('KPI.AssignmentTemplate', 'BandPointsRed') IS NULL
    ALTER TABLE KPI.AssignmentTemplate
        ADD BandPointsRed DECIMAL(9,4) NOT NULL
            CONSTRAINT DF_KpiTpl_BandR DEFAULT (0);
GO

IF COL_LENGTH('KPI.AssignmentTemplate', 'BooleanYesPoints') IS NULL
    ALTER TABLE KPI.AssignmentTemplate ADD BooleanYesPoints DECIMAL(9,4) NULL;
GO

IF COL_LENGTH('KPI.AssignmentTemplate', 'BooleanNoPoints') IS NULL
    ALTER TABLE KPI.AssignmentTemplate ADD BooleanNoPoints DECIMAL(9,4) NULL;
GO

IF COL_LENGTH('KPI.AssignmentTemplate', 'MultiSelectScoreRule') IS NULL
    ALTER TABLE KPI.AssignmentTemplate ADD MultiSelectScoreRule NVARCHAR(10) NULL;
GO

IF COL_LENGTH('KPI.AssignmentTemplate', 'PenaliseMissingOnScore') IS NULL
    ALTER TABLE KPI.AssignmentTemplate
        ADD PenaliseMissingOnScore BIT NOT NULL
            CONSTRAINT DF_KpiTpl_PenaliseMissing DEFAULT (1);
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE name = 'CK_KpiTpl_ScoringMode'
      AND parent_object_id = OBJECT_ID(N'KPI.AssignmentTemplate')
)
    ALTER TABLE KPI.AssignmentTemplate
        ADD CONSTRAINT CK_KpiTpl_ScoringMode CHECK (ScoringMode IN ('Band','Linear'));
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE name = 'CK_KpiTpl_MSRule'
      AND parent_object_id = OBJECT_ID(N'KPI.AssignmentTemplate')
)
    ALTER TABLE KPI.AssignmentTemplate
        ADD CONSTRAINT CK_KpiTpl_MSRule
            CHECK (MultiSelectScoreRule IN ('Sum','Avg','Max') OR MultiSelectScoreRule IS NULL);
GO

-- ─── KPI.Assignment scoring columns (mirror for materialised rows) ─

IF COL_LENGTH('KPI.Assignment', 'KpiWeight') IS NULL
    ALTER TABLE KPI.Assignment
        ADD KpiWeight DECIMAL(9,4) NOT NULL
            CONSTRAINT DF_KpiAsgn_KpiWeight DEFAULT (1.0000);
GO

IF COL_LENGTH('KPI.Assignment', 'ScoringMode') IS NULL
    ALTER TABLE KPI.Assignment
        ADD ScoringMode NVARCHAR(10) NOT NULL
            CONSTRAINT DF_KpiAsgn_ScoringMode DEFAULT ('Band');
GO

IF COL_LENGTH('KPI.Assignment', 'BandPointsGreen') IS NULL
    ALTER TABLE KPI.Assignment
        ADD BandPointsGreen DECIMAL(9,4) NOT NULL
            CONSTRAINT DF_KpiAsgn_BandG DEFAULT (100);
GO

IF COL_LENGTH('KPI.Assignment', 'BandPointsAmber') IS NULL
    ALTER TABLE KPI.Assignment
        ADD BandPointsAmber DECIMAL(9,4) NOT NULL
            CONSTRAINT DF_KpiAsgn_BandA DEFAULT (50);
GO

IF COL_LENGTH('KPI.Assignment', 'BandPointsRed') IS NULL
    ALTER TABLE KPI.Assignment
        ADD BandPointsRed DECIMAL(9,4) NOT NULL
            CONSTRAINT DF_KpiAsgn_BandR DEFAULT (0);
GO

IF COL_LENGTH('KPI.Assignment', 'BooleanYesPoints') IS NULL
    ALTER TABLE KPI.Assignment ADD BooleanYesPoints DECIMAL(9,4) NULL;
GO

IF COL_LENGTH('KPI.Assignment', 'BooleanNoPoints') IS NULL
    ALTER TABLE KPI.Assignment ADD BooleanNoPoints DECIMAL(9,4) NULL;
GO

IF COL_LENGTH('KPI.Assignment', 'MultiSelectScoreRule') IS NULL
    ALTER TABLE KPI.Assignment ADD MultiSelectScoreRule NVARCHAR(10) NULL;
GO

IF COL_LENGTH('KPI.Assignment', 'PenaliseMissingOnScore') IS NULL
    ALTER TABLE KPI.Assignment
        ADD PenaliseMissingOnScore BIT NOT NULL
            CONSTRAINT DF_KpiAsgn_PenaliseMissing DEFAULT (1);
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE name = 'CK_KpiAsgn_ScoringMode'
      AND parent_object_id = OBJECT_ID(N'KPI.Assignment')
)
    ALTER TABLE KPI.Assignment
        ADD CONSTRAINT CK_KpiAsgn_ScoringMode CHECK (ScoringMode IN ('Band','Linear'));
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE name = 'CK_KpiAsgn_MSRule'
      AND parent_object_id = OBJECT_ID(N'KPI.Assignment')
)
    ALTER TABLE KPI.Assignment
        ADD CONSTRAINT CK_KpiAsgn_MSRule
            CHECK (MultiSelectScoreRule IN ('Sum','Avg','Max') OR MultiSelectScoreRule IS NULL);
GO

-- ─── KPI.AssignmentTemplateDropDownOption ─────────────────────

IF COL_LENGTH('KPI.AssignmentTemplateDropDownOption', 'Points') IS NULL
    ALTER TABLE KPI.AssignmentTemplateDropDownOption
        ADD Points DECIMAL(9,4) NOT NULL
            CONSTRAINT DF_KpiTplDDOpt_Points DEFAULT (0);
GO

-- ─── KPI.CategoryWeight (new) ──────────────────────────────────

IF OBJECT_ID('KPI.CategoryWeight', 'U') IS NULL
BEGIN
    CREATE TABLE KPI.CategoryWeight
    (
        CategoryWeightId INT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_KpiCategoryWeight PRIMARY KEY,
        AccountId        INT NOT NULL,
        Category         NVARCHAR(100) NOT NULL,
        Weight           DECIMAL(9,4) NOT NULL
            CONSTRAINT DF_KpiCatWeight_Weight DEFAULT (1.0),
        IsActive         BIT NOT NULL
            CONSTRAINT DF_KpiCatWeight_IsActive DEFAULT (1),
        CreatedOnUtc     DATETIME2 NOT NULL
            CONSTRAINT DF_KpiCatWeight_Created DEFAULT (SYSUTCDATETIME()),
        ModifiedOnUtc    DATETIME2 NOT NULL
            CONSTRAINT DF_KpiCatWeight_Modified DEFAULT (SYSUTCDATETIME()),
        CreatedBy        NVARCHAR(128) NOT NULL
            CONSTRAINT DF_KpiCatWeight_CreatedBy DEFAULT (SESSION_USER),
        ModifiedBy       NVARCHAR(128) NOT NULL
            CONSTRAINT DF_KpiCatWeight_ModifiedBy DEFAULT (SESSION_USER),
        CONSTRAINT FK_KpiCatWeight_Account FOREIGN KEY (AccountId)
            REFERENCES Dim.Account (AccountId),
        CONSTRAINT UX_KpiCatWeight UNIQUE (AccountId, Category)
    );

    CREATE INDEX IX_KpiCatWeight_Account ON KPI.CategoryWeight (AccountId);
END;
GO

-- ============================================================
-- usp_AssignKpi — pass scoring columns through on INSERT/UPDATE
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
    @ActorUPN               NVARCHAR(320)   = NULL,
    @AssignmentID           INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @KPIID INT = (SELECT KPIID FROM KPI.Definition WHERE KPICode = @KPICode AND IsActive = 1);
    IF @KPIID IS NULL
        THROW 50110, 'KPI not found or inactive for provided KPICode.', 1;

    DECLARE @AccountId INT = (SELECT AccountId FROM Dim.Account WHERE AccountCode = @AccountCode AND IsActive = 1);
    IF @AccountId IS NULL
        THROW 50111, 'Account not found or inactive.', 1;

    DECLARE @OrgUnitId INT = NULL;
    IF @OrgUnitCode IS NOT NULL
    BEGIN
        SELECT @OrgUnitId = OrgUnitId
        FROM Dim.OrgUnit
        WHERE AccountId    = @AccountId
          AND OrgUnitCode  = @OrgUnitCode
          AND OrgUnitType  = @OrgUnitType
          AND IsActive     = 1;

        IF @OrgUnitId IS NULL
            THROW 50112, 'OrgUnit not found or inactive for provided AccountCode + OrgUnitCode.', 1;
    END

    DECLARE @PeriodID INT = (
        SELECT PeriodID FROM KPI.Period
        WHERE PeriodScheduleID = @PeriodScheduleID
          AND PeriodYear       = @PeriodYear
          AND PeriodMonth      = @PeriodMonth
    );
    IF @PeriodID IS NULL
        THROW 50113, 'Period not found for this schedule/year/month. Create the period first using App.usp_UpsertKpiPeriod.', 1;

    DECLARE @ActorPrincipalId INT = NULL;
    IF @ActorUPN IS NOT NULL
        SELECT @ActorPrincipalId = UserId FROM Sec.[User] WHERE UPN = @ActorUPN;

    IF @OrgUnitId IS NULL
    BEGIN
        SET @AssignmentID = (
            SELECT AssignmentID FROM KPI.Assignment
            WHERE KPIID = @KPIID
              AND AccountId = @AccountId
              AND OrgUnitId IS NULL
              AND PeriodID = @PeriodID
              AND (
                    (@AssignmentGroupName IS NULL AND AssignmentGroupName IS NULL)
                    OR AssignmentGroupName = @AssignmentGroupName
                  )
        );
    END
    ELSE
    BEGIN
        SET @AssignmentID = (
            SELECT AssignmentID FROM KPI.Assignment
            WHERE KPIID = @KPIID
              AND OrgUnitId = @OrgUnitId
              AND PeriodID = @PeriodID
              AND (
                    (@AssignmentGroupName IS NULL AND AssignmentGroupName IS NULL)
                    OR AssignmentGroupName = @AssignmentGroupName
                  )
        );
    END

    IF @AssignmentID IS NULL
    BEGIN
        INSERT INTO KPI.Assignment
            (KPIID, AccountId, OrgUnitId, PeriodID, AssignmentTemplateID, IsRequired,
             TargetValue, ThresholdGreen, ThresholdAmber, ThresholdRed,
             ThresholdDirection, SubmitterGuidance, AssignedByPrincipalId, AssignmentGroupName,
             KpiWeight, ScoringMode, BandPointsGreen, BandPointsAmber, BandPointsRed,
             BooleanYesPoints, BooleanNoPoints, MultiSelectScoreRule, PenaliseMissingOnScore)
        VALUES
            (@KPIID, @AccountId, @OrgUnitId, @PeriodID, @AssignmentTemplateID, @IsRequired,
             @TargetValue, @ThresholdGreen, @ThresholdAmber, @ThresholdRed,
             @ThresholdDirection, @SubmitterGuidance, @ActorPrincipalId, @AssignmentGroupName,
             @KpiWeight, @ScoringMode, @BandPointsGreen, @BandPointsAmber, @BandPointsRed,
             @BooleanYesPoints, @BooleanNoPoints, @MultiSelectScoreRule, @PenaliseMissingOnScore);

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
            IsActive               = 1,
            ModifiedOnUtc          = SYSUTCDATETIME(),
            ModifiedBy             = COALESCE(@ActorUPN, SESSION_USER)
        WHERE AssignmentID = @AssignmentID;
    END
END;
GO

-- ============================================================
-- usp_UpsertKpiAssignmentTemplate — accept scoring + JSON option points
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
    -- New scoring fields (NULL keeps current value on UPDATE; uses defaults on INSERT)
    @KpiWeight              DECIMAL(9,4)    = NULL,
    @ScoringMode            NVARCHAR(10)    = NULL,
    @BandPointsGreen        DECIMAL(9,4)    = NULL,
    @BandPointsAmber        DECIMAL(9,4)    = NULL,
    @BandPointsRed          DECIMAL(9,4)    = NULL,
    @BooleanYesPoints       DECIMAL(9,4)    = NULL,
    @BooleanNoPoints        DECIMAL(9,4)    = NULL,
    @MultiSelectScoreRule   NVARCHAR(10)    = NULL,
    @PenaliseMissingOnScore BIT             = NULL,
    -- JSON array: [{"value":"Yes","points":10,"sortOrder":1}, ...]
    -- When non-NULL, replaces all rows in KPI.AssignmentTemplateDropDownOption
    -- for this template. When NULL, options are left untouched.
    @OptionPoints           NVARCHAR(MAX)   = NULL,
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

    IF @StartPeriodYear IS NOT NULL
       AND @EndPeriodYear IS NOT NULL
       AND (@EndPeriodYear * 100 + @EndPeriodMonth) < (@StartPeriodYear * 100 + @StartPeriodMonth)
        THROW 50133, 'End period must be on or after the start period.', 1;

    DECLARE @KPIID INT = (SELECT KPIID FROM KPI.Definition WHERE KPICode = @KPICode AND IsActive = 1);
    IF @KPIID IS NULL
        THROW 50134, 'KPI not found or inactive for provided KPICode.', 1;

    IF NOT EXISTS (SELECT 1 FROM KPI.PeriodSchedule WHERE PeriodScheduleID = @PeriodScheduleID AND IsActive = 1)
        THROW 50137, 'Schedule not found or inactive.', 1;

    DECLARE @ScheduleStartDate DATE;
    DECLARE @ScheduleEndDate DATE;

    SELECT
        @ScheduleStartDate = StartDate,
        @ScheduleEndDate   = EndDate
    FROM KPI.PeriodSchedule
    WHERE PeriodScheduleID = @PeriodScheduleID
      AND IsActive = 1;

    IF @StartPeriodYear IS NULL OR @StartPeriodMonth IS NULL
    BEGIN
        SET @StartPeriodYear  = YEAR(@ScheduleStartDate);
        SET @StartPeriodMonth = MONTH(@ScheduleStartDate);
    END

    IF @EndPeriodYear IS NULL AND @EndPeriodMonth IS NULL AND @ScheduleEndDate IS NOT NULL
    BEGIN
        SET @EndPeriodYear  = YEAR(@ScheduleEndDate);
        SET @EndPeriodMonth = MONTH(@ScheduleEndDate);
    END

    DECLARE @AccountId INT = (SELECT AccountId FROM Dim.Account WHERE AccountCode = @AccountCode AND IsActive = 1);
    IF @AccountId IS NULL
        THROW 50135, 'Account not found or inactive.', 1;

    DECLARE @OrgUnitId INT = NULL;
    IF @OrgUnitCode IS NOT NULL
    BEGIN
        SELECT @OrgUnitId = OrgUnitId
        FROM Dim.OrgUnit
        WHERE AccountId    = @AccountId
          AND OrgUnitCode  = @OrgUnitCode
          AND OrgUnitType  = @OrgUnitType
          AND IsActive     = 1;

        IF @OrgUnitId IS NULL
            THROW 50136, 'OrgUnit not found or inactive for provided AccountCode + OrgUnitCode.', 1;
    END

    SET @AssignmentTemplateID = (
        SELECT AssignmentTemplateID
        FROM KPI.AssignmentTemplate
        WHERE KPIID = @KPIID
          AND PeriodScheduleID = @PeriodScheduleID
          AND AccountId = @AccountId
          AND (
                (@OrgUnitId IS NULL AND OrgUnitId IS NULL)
                OR OrgUnitId = @OrgUnitId
              )
          AND (
                (@AssignmentGroupName IS NULL AND AssignmentGroupName IS NULL)
                OR AssignmentGroupName = @AssignmentGroupName
              )
    );

    IF @AssignmentTemplateID IS NULL
    BEGIN
        INSERT INTO KPI.AssignmentTemplate
            (KPIID, PeriodScheduleID, AccountId, OrgUnitId, StartPeriodYear, StartPeriodMonth, EndPeriodYear, EndPeriodMonth,
             IsRequired, TargetValue, ThresholdGreen, ThresholdAmber, ThresholdRed, ThresholdDirection, SubmitterGuidance,
             CustomKpiName, CustomKpiDescription, KpiPackageId, AssignmentGroupName,
             KpiWeight, ScoringMode, BandPointsGreen, BandPointsAmber, BandPointsRed,
             BooleanYesPoints, BooleanNoPoints, MultiSelectScoreRule, PenaliseMissingOnScore)
        VALUES
            (@KPIID, @PeriodScheduleID, @AccountId, @OrgUnitId, @StartPeriodYear, @StartPeriodMonth, @EndPeriodYear, @EndPeriodMonth,
             @IsRequired, @TargetValue, @ThresholdGreen, @ThresholdAmber, @ThresholdRed, @ThresholdDirection, @SubmitterGuidance,
             @CustomKpiName, @CustomKpiDescription, @KpiPackageId, @AssignmentGroupName,
             COALESCE(@KpiWeight, 1.0),
             COALESCE(@ScoringMode, 'Band'),
             COALESCE(@BandPointsGreen, 100),
             COALESCE(@BandPointsAmber, 50),
             COALESCE(@BandPointsRed, 0),
             @BooleanYesPoints,
             @BooleanNoPoints,
             @MultiSelectScoreRule,
             COALESCE(@PenaliseMissingOnScore, @IsRequired));

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
            IsActive               = 1,
            ModifiedOnUtc          = SYSUTCDATETIME(),
            ModifiedBy             = COALESCE(@ActorUPN, SESSION_USER)
        WHERE AssignmentTemplateID = @AssignmentTemplateID;
    END

    -- Replace dropdown option points when JSON provided. NULL = leave alone.
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
-- usp_MaterializeKpiAssignmentTemplates — pass scoring through to assignments
-- ============================================================

CREATE OR ALTER PROCEDURE App.usp_MaterializeKpiAssignmentTemplates
    @AssignmentTemplateID   INT           = NULL,
    @PeriodScheduleIDFilter INT           = NULL,
    @ActorUPN               NVARCHAR(320) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @CurrentTemplateId INT,
        @TemplateKpiCode NVARCHAR(50),
        @TemplateScheduleId INT,
        @TemplateScheduleStartDate DATE,
        @TemplateScheduleEndDate DATE,
        @TemplateAccountCode NVARCHAR(50),
        @TemplateOrgUnitCode NVARCHAR(50),
        @TemplateOrgUnitType NVARCHAR(20),
        @TemplateStartYear SMALLINT,
        @TemplateStartMonth TINYINT,
        @TemplateEndYear SMALLINT,
        @TemplateEndMonth TINYINT,
        @TemplateIsRequired BIT,
        @TemplateTargetValue DECIMAL(18,4),
        @TemplateThresholdGreen DECIMAL(18,4),
        @TemplateThresholdAmber DECIMAL(18,4),
        @TemplateThresholdRed DECIMAL(18,4),
        @TemplateThresholdDirection NVARCHAR(10),
        @TemplateSubmitterGuidance NVARCHAR(1000),
        @TemplateGroupName NVARCHAR(100),
        @TemplateKpiWeight DECIMAL(9,4),
        @TemplateScoringMode NVARCHAR(10),
        @TemplateBandG DECIMAL(9,4),
        @TemplateBandA DECIMAL(9,4),
        @TemplateBandR DECIMAL(9,4),
        @TemplateBoolY DECIMAL(9,4),
        @TemplateBoolN DECIMAL(9,4),
        @TemplateMSRule NVARCHAR(10),
        @TemplatePenaliseMissing BIT,
        @SiteOrgUnitCode NVARCHAR(50);

    DECLARE template_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT
            t.AssignmentTemplateID,
            d.KPICode,
            t.PeriodScheduleID,
            sched.StartDate,
            sched.EndDate,
            acct.AccountCode,
            ou.OrgUnitCode,
            COALESCE(ou.OrgUnitType, 'Site') AS OrgUnitType,
            t.StartPeriodYear,
            t.StartPeriodMonth,
            t.EndPeriodYear,
            t.EndPeriodMonth,
            t.IsRequired,
            t.TargetValue,
            t.ThresholdGreen,
            t.ThresholdAmber,
            t.ThresholdRed,
            t.ThresholdDirection,
            t.SubmitterGuidance,
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
        JOIN KPI.Definition         AS d     ON d.KPIID              = t.KPIID
        JOIN KPI.PeriodSchedule     AS sched ON sched.PeriodScheduleID = t.PeriodScheduleID
        JOIN Dim.Account            AS acct  ON acct.AccountId       = t.AccountId
        LEFT JOIN Dim.OrgUnit       AS ou    ON ou.OrgUnitId         = t.OrgUnitId
        WHERE t.IsActive = 1
          AND sched.IsActive = 1
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
        @TemplateBoolY, @TemplateBoolN, @TemplateMSRule, @TemplatePenaliseMissing;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @CurrentPeriodYear SMALLINT;
        DECLARE @CurrentPeriodMonth TINYINT;

        DECLARE period_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT PeriodYear, PeriodMonth
            FROM KPI.Period
            WHERE PeriodScheduleID = @TemplateScheduleId
              AND (PeriodYear * 100 + PeriodMonth) >= (
                    COALESCE(@TemplateStartYear, YEAR(@TemplateScheduleStartDate)) * 100
                    + COALESCE(@TemplateStartMonth, MONTH(@TemplateScheduleStartDate))
                  )
              AND (
                    @TemplateEndYear IS NULL
                    OR (PeriodYear * 100 + PeriodMonth) <= (@TemplateEndYear * 100 + @TemplateEndMonth)
                  )
            ORDER BY PeriodYear, PeriodMonth;

        OPEN period_cursor;
        FETCH NEXT FROM period_cursor INTO @CurrentPeriodYear, @CurrentPeriodMonth;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            DECLARE @GeneratedAssignmentId INT;

            IF @TemplateOrgUnitCode IS NULL
            BEGIN
                DECLARE site_cursor CURSOR LOCAL FAST_FORWARD FOR
                    SELECT ou.OrgUnitCode
                    FROM Dim.OrgUnit AS ou
                    JOIN Dim.Account AS acct ON acct.AccountId = ou.AccountId
                    WHERE acct.AccountCode = @TemplateAccountCode
                      AND ou.OrgUnitType   = 'Site'
                      AND ou.IsActive      = 1;

                OPEN site_cursor;
                FETCH NEXT FROM site_cursor INTO @SiteOrgUnitCode;

                WHILE @@FETCH_STATUS = 0
                BEGIN
                    SET @GeneratedAssignmentId = NULL;
                    EXEC App.usp_AssignKpi
                        @KPICode                = @TemplateKpiCode,
                        @AccountCode            = @TemplateAccountCode,
                        @OrgUnitCode            = @SiteOrgUnitCode,
                        @OrgUnitType            = 'Site',
                        @PeriodScheduleID       = @TemplateScheduleId,
                        @PeriodYear             = @CurrentPeriodYear,
                        @PeriodMonth            = @CurrentPeriodMonth,
                        @AssignmentTemplateID   = @CurrentTemplateId,
                        @IsRequired             = @TemplateIsRequired,
                        @TargetValue            = @TemplateTargetValue,
                        @ThresholdGreen         = @TemplateThresholdGreen,
                        @ThresholdAmber         = @TemplateThresholdAmber,
                        @ThresholdRed           = @TemplateThresholdRed,
                        @ThresholdDirection     = @TemplateThresholdDirection,
                        @SubmitterGuidance      = @TemplateSubmitterGuidance,
                        @AssignmentGroupName    = @TemplateGroupName,
                        @KpiWeight              = @TemplateKpiWeight,
                        @ScoringMode            = @TemplateScoringMode,
                        @BandPointsGreen        = @TemplateBandG,
                        @BandPointsAmber        = @TemplateBandA,
                        @BandPointsRed          = @TemplateBandR,
                        @BooleanYesPoints       = @TemplateBoolY,
                        @BooleanNoPoints        = @TemplateBoolN,
                        @MultiSelectScoreRule   = @TemplateMSRule,
                        @PenaliseMissingOnScore = @TemplatePenaliseMissing,
                        @ActorUPN               = @ActorUPN,
                        @AssignmentID           = @GeneratedAssignmentId OUTPUT;

                    FETCH NEXT FROM site_cursor INTO @SiteOrgUnitCode;
                END

                CLOSE site_cursor;
                DEALLOCATE site_cursor;
            END
            ELSE
            BEGIN
                SET @GeneratedAssignmentId = NULL;
                EXEC App.usp_AssignKpi
                    @KPICode                = @TemplateKpiCode,
                    @AccountCode            = @TemplateAccountCode,
                    @OrgUnitCode            = @TemplateOrgUnitCode,
                    @OrgUnitType            = @TemplateOrgUnitType,
                    @PeriodScheduleID       = @TemplateScheduleId,
                    @PeriodYear             = @CurrentPeriodYear,
                    @PeriodMonth            = @CurrentPeriodMonth,
                    @AssignmentTemplateID   = @CurrentTemplateId,
                    @IsRequired             = @TemplateIsRequired,
                    @TargetValue            = @TemplateTargetValue,
                    @ThresholdGreen         = @TemplateThresholdGreen,
                    @ThresholdAmber         = @TemplateThresholdAmber,
                    @ThresholdRed           = @TemplateThresholdRed,
                    @ThresholdDirection     = @TemplateThresholdDirection,
                    @SubmitterGuidance      = @TemplateSubmitterGuidance,
                    @AssignmentGroupName    = @TemplateGroupName,
                    @KpiWeight              = @TemplateKpiWeight,
                    @ScoringMode            = @TemplateScoringMode,
                    @BandPointsGreen        = @TemplateBandG,
                    @BandPointsAmber        = @TemplateBandA,
                    @BandPointsRed          = @TemplateBandR,
                    @BooleanYesPoints       = @TemplateBoolY,
                    @BooleanNoPoints        = @TemplateBoolN,
                    @MultiSelectScoreRule   = @TemplateMSRule,
                    @PenaliseMissingOnScore = @TemplatePenaliseMissing,
                    @ActorUPN               = @ActorUPN,
                    @AssignmentID           = @GeneratedAssignmentId OUTPUT;
            END

            FETCH NEXT FROM period_cursor INTO @CurrentPeriodYear, @CurrentPeriodMonth;
        END

        CLOSE period_cursor;
        DEALLOCATE period_cursor;

        FETCH NEXT FROM template_cursor INTO
            @CurrentTemplateId, @TemplateKpiCode, @TemplateScheduleId, @TemplateScheduleStartDate, @TemplateScheduleEndDate,
            @TemplateAccountCode, @TemplateOrgUnitCode, @TemplateOrgUnitType,
            @TemplateStartYear, @TemplateStartMonth, @TemplateEndYear, @TemplateEndMonth, @TemplateIsRequired,
            @TemplateTargetValue, @TemplateThresholdGreen, @TemplateThresholdAmber, @TemplateThresholdRed,
            @TemplateThresholdDirection, @TemplateSubmitterGuidance, @TemplateGroupName,
            @TemplateKpiWeight, @TemplateScoringMode, @TemplateBandG, @TemplateBandA, @TemplateBandR,
            @TemplateBoolY, @TemplateBoolN, @TemplateMSRule, @TemplatePenaliseMissing;
    END

    CLOSE template_cursor;
    DEALLOCATE template_cursor;
END;
GO

-- ============================================================
-- usp_CascadeAssignmentTemplateThresholds — also cascade scoring config
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
        ModifiedOnUtc          = SYSUTCDATETIME(),
        ModifiedBy             = COALESCE(@ActorUPN, SESSION_USER)
    FROM KPI.Assignment         AS a
    JOIN KPI.AssignmentTemplate AS t ON t.AssignmentTemplateID = a.AssignmentTemplateID
    WHERE t.AssignmentTemplateID = @AssignmentTemplateID
      AND NOT EXISTS (SELECT 1 FROM KPI.Submission s WHERE s.AssignmentID = a.AssignmentID);
END;
GO

-- ============================================================
-- usp_UpsertCategoryWeights — JSON-fed bulk upsert per account
-- ============================================================
-- @WeightsJson format: [{"category":"Safety","weight":0.30,"isActive":true}, ...]
-- Categories not present in the JSON are left untouched. Pass IsActive=0 to disable.

CREATE OR ALTER PROCEDURE App.usp_UpsertCategoryWeights
    @AccountCode NVARCHAR(50),
    @WeightsJson NVARCHAR(MAX),
    @ActorUPN    NVARCHAR(320) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @AccountId INT = (SELECT AccountId FROM Dim.Account WHERE AccountCode = @AccountCode AND IsActive = 1);
    IF @AccountId IS NULL
        THROW 50250, 'Account not found or inactive.', 1;

    DECLARE @Actor NVARCHAR(128) = COALESCE(@ActorUPN, SESSION_USER);

    ;WITH input AS (
        SELECT
            JSON_VALUE(j.[value], '$.category')                          AS Category,
            TRY_CAST(JSON_VALUE(j.[value], '$.weight')   AS DECIMAL(9,4)) AS Weight,
            TRY_CAST(JSON_VALUE(j.[value], '$.isActive') AS BIT)         AS IsActive
        FROM OPENJSON(@WeightsJson) AS j
    )
    MERGE KPI.CategoryWeight AS tgt
    USING input AS src
       ON tgt.AccountId = @AccountId AND tgt.Category = src.Category
    WHEN MATCHED THEN
        UPDATE SET Weight        = ISNULL(src.Weight, tgt.Weight),
                   IsActive      = ISNULL(src.IsActive, tgt.IsActive),
                   ModifiedOnUtc = SYSUTCDATETIME(),
                   ModifiedBy    = @Actor
    WHEN NOT MATCHED BY TARGET AND src.Category IS NOT NULL THEN
        INSERT (AccountId, Category, Weight, IsActive, CreatedBy, ModifiedBy)
        VALUES (@AccountId, src.Category, ISNULL(src.Weight, 1.0), ISNULL(src.IsActive, 1), @Actor, @Actor);
END;
GO

-- ============================================================
-- vKpiAssignmentTemplates — project the new scoring columns
-- so the assignment-templates endpoint can return them.
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
