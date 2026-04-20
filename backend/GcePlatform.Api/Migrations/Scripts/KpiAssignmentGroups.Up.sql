-- ============================================================
-- Migration: KpiAssignmentGroups — Up
-- Adds optional named group support to KPI assignments:
--   1. AssignmentGroupName column on KPI.AssignmentTemplate
--   2. AssignmentGroupName column on KPI.Assignment
--   3. Rebuild uniqueness indexes to include the group dimension
--   4. AssignmentGroupName column on KPI.SubmissionToken
--   5. Update App.usp_UpsertKpiAssignmentTemplate
--   6. Update App.usp_MaterializeKpiAssignmentTemplates
--   7. Update App.usp_AssignKpi
--   8. Update App.usp_CreateSubmissionToken
--   9. Update App.vKpiAssignmentTemplates
--  10. Update App.vKpiAssignments
--  11. Update App.vSiteCompletionSummary
--  12. Update App.vSiteSubmissionDetails
--  13. Update App.vSubmissionTokens
--  14. Update App.vSubmissionTokenAssignments
--  15. New view App.vAssignmentGroups
-- Safe to re-run: all DDL uses idempotent guards.
-- ============================================================
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Add AssignmentGroupName to KPI.AssignmentTemplate
-- ─────────────────────────────────────────────────────────────────────────────
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('KPI.AssignmentTemplate') AND name = 'AssignmentGroupName'
)
    ALTER TABLE KPI.AssignmentTemplate
        ADD AssignmentGroupName NVARCHAR(100) NULL;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Add AssignmentGroupName to KPI.Assignment
-- ─────────────────────────────────────────────────────────────────────────────
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('KPI.Assignment') AND name = 'AssignmentGroupName'
)
    ALTER TABLE KPI.Assignment
        ADD AssignmentGroupName NVARCHAR(100) NULL;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Rebuild KPI.AssignmentTemplate uniqueness index
--    Old: (KPIID, PeriodScheduleID, AccountId, OrgUnitId) — didn't allow two
--         templates for the same KPI+account+schedule in different groups.
--    New: Two filtered indexes — one for named groups, one for ungrouped.
-- ─────────────────────────────────────────────────────────────────────────────
IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('KPI.AssignmentTemplate')
      AND name = 'UX_KpiAssignmentTemplate_Scope'
)
    DROP INDEX UX_KpiAssignmentTemplate_Scope ON KPI.AssignmentTemplate;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('KPI.AssignmentTemplate')
      AND name = 'UX_KpiAssignmentTemplate_ScopeNoGroup'
)
    CREATE UNIQUE INDEX UX_KpiAssignmentTemplate_ScopeNoGroup
        ON KPI.AssignmentTemplate (KPIID, PeriodScheduleID, AccountId, OrgUnitId)
        WHERE AssignmentGroupName IS NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('KPI.AssignmentTemplate')
      AND name = 'UX_KpiAssignmentTemplate_ScopeWithGroup'
)
    CREATE UNIQUE INDEX UX_KpiAssignmentTemplate_ScopeWithGroup
        ON KPI.AssignmentTemplate (KPIID, PeriodScheduleID, AccountId, OrgUnitId, AssignmentGroupName)
        WHERE AssignmentGroupName IS NOT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('KPI.AssignmentTemplate')
      AND name = 'IX_KpiAssignmentTemplate_GroupName'
)
    CREATE INDEX IX_KpiAssignmentTemplate_GroupName
        ON KPI.AssignmentTemplate (AssignmentGroupName)
        WHERE AssignmentGroupName IS NOT NULL;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Rebuild KPI.Assignment uniqueness indexes
--    Old: UX_KpiAsgn_SiteLevel (KPIID, OrgUnitId, PeriodID)
--         UX_KpiAsgn_AccountLevel (KPIID, AccountId, PeriodID)
--    New: Two filtered pairs — with group and without group.
-- ─────────────────────────────────────────────────────────────────────────────
IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('KPI.Assignment')
      AND name = 'UX_KpiAsgn_SiteLevel'
)
    DROP INDEX UX_KpiAsgn_SiteLevel ON KPI.Assignment;
GO

IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('KPI.Assignment')
      AND name = 'UX_KpiAsgn_AccountLevel'
)
    DROP INDEX UX_KpiAsgn_AccountLevel ON KPI.Assignment;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('KPI.Assignment')
      AND name = 'UX_KpiAsgn_SiteLevelNoGroup'
)
    CREATE UNIQUE INDEX UX_KpiAsgn_SiteLevelNoGroup
        ON KPI.Assignment (KPIID, OrgUnitId, PeriodID)
        WHERE OrgUnitId IS NOT NULL AND AssignmentGroupName IS NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('KPI.Assignment')
      AND name = 'UX_KpiAsgn_SiteLevelWithGroup'
)
    CREATE UNIQUE INDEX UX_KpiAsgn_SiteLevelWithGroup
        ON KPI.Assignment (KPIID, OrgUnitId, PeriodID, AssignmentGroupName)
        WHERE OrgUnitId IS NOT NULL AND AssignmentGroupName IS NOT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('KPI.Assignment')
      AND name = 'UX_KpiAsgn_AccountLevelNoGroup'
)
    CREATE UNIQUE INDEX UX_KpiAsgn_AccountLevelNoGroup
        ON KPI.Assignment (KPIID, AccountId, PeriodID)
        WHERE OrgUnitId IS NULL AND AssignmentGroupName IS NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('KPI.Assignment')
      AND name = 'UX_KpiAsgn_AccountLevelWithGroup'
)
    CREATE UNIQUE INDEX UX_KpiAsgn_AccountLevelWithGroup
        ON KPI.Assignment (KPIID, AccountId, PeriodID, AssignmentGroupName)
        WHERE OrgUnitId IS NULL AND AssignmentGroupName IS NOT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('KPI.Assignment')
      AND name = 'IX_KpiAsgn_GroupName'
)
    CREATE INDEX IX_KpiAsgn_GroupName
        ON KPI.Assignment (AssignmentGroupName)
        WHERE AssignmentGroupName IS NOT NULL;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Add AssignmentGroupName to KPI.SubmissionToken
--    Tokens are group-scoped: one token per (site, period, group).
-- ─────────────────────────────────────────────────────────────────────────────
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('KPI.SubmissionToken') AND name = 'AssignmentGroupName'
)
    ALTER TABLE KPI.SubmissionToken
        ADD AssignmentGroupName NVARCHAR(100) NULL;
GO

-- Replace the existing site+period index with site+period+group
IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('KPI.SubmissionToken')
      AND name = 'IX_KpiSubToken_SitePeriod'
)
    DROP INDEX IX_KpiSubToken_SitePeriod ON KPI.SubmissionToken;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('KPI.SubmissionToken')
      AND name = 'IX_KpiSubToken_SitePeriodGroup'
)
    CREATE INDEX IX_KpiSubToken_SitePeriodGroup
        ON KPI.SubmissionToken (SiteOrgUnitId, PeriodId, AssignmentGroupName);
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Update App.usp_UpsertKpiAssignmentTemplate
--    Add @AssignmentGroupName parameter; include in lookup, INSERT, UPDATE.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE App.usp_UpsertKpiAssignmentTemplate
    @KPICode            NVARCHAR(50),
    @PeriodScheduleID   INT,
    @AccountCode        NVARCHAR(50),
    @OrgUnitCode        NVARCHAR(50)    = NULL,
    @OrgUnitType        NVARCHAR(20)    = 'Site',
    @StartPeriodYear    SMALLINT        = NULL,
    @StartPeriodMonth   TINYINT         = NULL,
    @EndPeriodYear      SMALLINT        = NULL,
    @EndPeriodMonth     TINYINT         = NULL,
    @IsRequired         BIT             = 1,
    @TargetValue        DECIMAL(18,4)   = NULL,
    @ThresholdGreen     DECIMAL(18,4)   = NULL,
    @ThresholdAmber     DECIMAL(18,4)   = NULL,
    @ThresholdRed       DECIMAL(18,4)   = NULL,
    @ThresholdDirection NVARCHAR(10)    = NULL,
    @SubmitterGuidance    NVARCHAR(1000)  = NULL,
    @CustomKpiName        NVARCHAR(200)   = NULL,
    @CustomKpiDescription NVARCHAR(1000)  = NULL,
    @KpiPackageId         INT             = NULL,
    @AssignmentGroupName  NVARCHAR(100)   = NULL,
    @ActorUPN             NVARCHAR(320)   = NULL,
    @AssignmentTemplateID INT OUTPUT
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
        @ScheduleEndDate = EndDate
    FROM KPI.PeriodSchedule
    WHERE PeriodScheduleID = @PeriodScheduleID
      AND IsActive = 1;

    IF @StartPeriodYear IS NULL OR @StartPeriodMonth IS NULL
    BEGIN
        SET @StartPeriodYear = YEAR(@ScheduleStartDate);
        SET @StartPeriodMonth = MONTH(@ScheduleStartDate);
    END

    IF @EndPeriodYear IS NULL AND @EndPeriodMonth IS NULL AND @ScheduleEndDate IS NOT NULL
    BEGIN
        SET @EndPeriodYear = YEAR(@ScheduleEndDate);
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
        WHERE AccountId = @AccountId
          AND OrgUnitCode = @OrgUnitCode
          AND OrgUnitType = @OrgUnitType
          AND IsActive = 1;

        IF @OrgUnitId IS NULL
            THROW 50136, 'OrgUnit not found or inactive for provided AccountCode + OrgUnitCode.', 1;
    END

    -- Look up existing template including group name (NULL-safe)
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
             CustomKpiName, CustomKpiDescription, KpiPackageId, AssignmentGroupName)
        VALUES
            (@KPIID, @PeriodScheduleID, @AccountId, @OrgUnitId, @StartPeriodYear, @StartPeriodMonth, @EndPeriodYear, @EndPeriodMonth,
             @IsRequired, @TargetValue, @ThresholdGreen, @ThresholdAmber, @ThresholdRed, @ThresholdDirection, @SubmitterGuidance,
             @CustomKpiName, @CustomKpiDescription, @KpiPackageId, @AssignmentGroupName);

        SET @AssignmentTemplateID = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE KPI.AssignmentTemplate
        SET PeriodScheduleID      = @PeriodScheduleID,
            StartPeriodYear       = @StartPeriodYear,
            StartPeriodMonth      = @StartPeriodMonth,
            EndPeriodYear         = @EndPeriodYear,
            EndPeriodMonth        = @EndPeriodMonth,
            IsRequired            = @IsRequired,
            TargetValue           = @TargetValue,
            ThresholdGreen        = @ThresholdGreen,
            ThresholdAmber        = @ThresholdAmber,
            ThresholdRed          = @ThresholdRed,
            ThresholdDirection    = @ThresholdDirection,
            SubmitterGuidance     = @SubmitterGuidance,
            CustomKpiName         = @CustomKpiName,
            CustomKpiDescription  = @CustomKpiDescription,
            KpiPackageId          = @KpiPackageId,
            IsActive              = 1,
            ModifiedOnUtc         = SYSUTCDATETIME(),
            ModifiedBy            = COALESCE(@ActorUPN, SESSION_USER)
        WHERE AssignmentTemplateID = @AssignmentTemplateID;
    END
END;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Update App.usp_AssignKpi
--    Add @AssignmentGroupName; stamp on INSERT; include in uniqueness lookup.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE App.usp_AssignKpi
    @KPICode              NVARCHAR(50),
    @AccountCode          NVARCHAR(50),
    @OrgUnitCode          NVARCHAR(50)    = NULL,   -- NULL = account-wide
    @OrgUnitType          NVARCHAR(20)    = 'Site',
    @PeriodScheduleID     INT,
    @PeriodYear           SMALLINT,
    @PeriodMonth          TINYINT,
    @AssignmentTemplateID INT             = NULL,
    @IsRequired           BIT             = 1,
    @TargetValue          DECIMAL(18,4)   = NULL,
    @ThresholdGreen       DECIMAL(18,4)   = NULL,
    @ThresholdAmber       DECIMAL(18,4)   = NULL,
    @ThresholdRed         DECIMAL(18,4)   = NULL,
    @ThresholdDirection   NVARCHAR(10)    = NULL,
    @SubmitterGuidance    NVARCHAR(1000)  = NULL,
    @AssignmentGroupName  NVARCHAR(100)   = NULL,
    @ActorUPN             NVARCHAR(320)   = NULL,
    @AssignmentID         INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    -- Resolve KPI
    DECLARE @KPIID INT = (SELECT KPIID FROM KPI.Definition WHERE KPICode = @KPICode AND IsActive = 1);
    IF @KPIID IS NULL
        THROW 50110, 'KPI not found or inactive for provided KPICode.', 1;

    -- Resolve Account
    DECLARE @AccountId INT = (SELECT AccountId FROM Dim.Account WHERE AccountCode = @AccountCode AND IsActive = 1);
    IF @AccountId IS NULL
        THROW 50111, 'Account not found or inactive.', 1;

    -- Resolve OrgUnit (site) if provided
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

    -- Resolve Period (scoped to schedule)
    DECLARE @PeriodID INT = (
        SELECT PeriodID FROM KPI.Period
        WHERE PeriodScheduleID = @PeriodScheduleID
          AND PeriodYear       = @PeriodYear
          AND PeriodMonth      = @PeriodMonth
    );
    IF @PeriodID IS NULL
        THROW 50113, 'Period not found for this schedule/year/month. Create the period first using App.usp_UpsertKpiPeriod.', 1;

    -- Resolve actor
    DECLARE @ActorPrincipalId INT = NULL;
    IF @ActorUPN IS NOT NULL
        SELECT @ActorPrincipalId = UserId FROM Sec.[User] WHERE UPN = @ActorUPN;

    -- Look up existing assignment including group name (NULL-safe)
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
             ThresholdDirection, SubmitterGuidance, AssignedByPrincipalId, AssignmentGroupName)
        VALUES
            (@KPIID, @AccountId, @OrgUnitId, @PeriodID, @AssignmentTemplateID, @IsRequired,
             @TargetValue, @ThresholdGreen, @ThresholdAmber, @ThresholdRed,
             @ThresholdDirection, @SubmitterGuidance, @ActorPrincipalId, @AssignmentGroupName);

        SET @AssignmentID = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE KPI.Assignment
        SET IsRequired          = @IsRequired,
            TargetValue         = @TargetValue,
            ThresholdGreen      = @ThresholdGreen,
            ThresholdAmber      = @ThresholdAmber,
            ThresholdRed        = @ThresholdRed,
            ThresholdDirection  = @ThresholdDirection,
            SubmitterGuidance   = @SubmitterGuidance,
            IsActive            = 1,   -- reactivate if previously deactivated
            ModifiedOnUtc       = SYSUTCDATETIME(),
            ModifiedBy          = COALESCE(@ActorUPN, SESSION_USER)
        WHERE AssignmentID = @AssignmentID;
    END
END;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. Update App.usp_MaterializeKpiAssignmentTemplates
--    Fetch AssignmentGroupName from template cursor; pass to usp_AssignKpi.
-- ─────────────────────────────────────────────────────────────────────────────
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
        -- Used when expanding account-wide templates to per-site assignments
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
            t.AssignmentGroupName
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
        @TemplateThresholdDirection, @TemplateSubmitterGuidance, @TemplateGroupName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @CurrentPeriodYear SMALLINT;
        DECLARE @CurrentPeriodMonth TINYINT;

        -- Periods already belong to the right schedule — no frequency modulo needed
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
                -- Account-wide template: expand to one per-site assignment for every active site
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
                        @KPICode              = @TemplateKpiCode,
                        @AccountCode          = @TemplateAccountCode,
                        @OrgUnitCode          = @SiteOrgUnitCode,
                        @OrgUnitType          = 'Site',
                        @PeriodScheduleID     = @TemplateScheduleId,
                        @PeriodYear           = @CurrentPeriodYear,
                        @PeriodMonth          = @CurrentPeriodMonth,
                        @AssignmentTemplateID = @CurrentTemplateId,
                        @IsRequired           = @TemplateIsRequired,
                        @TargetValue          = @TemplateTargetValue,
                        @ThresholdGreen       = @TemplateThresholdGreen,
                        @ThresholdAmber       = @TemplateThresholdAmber,
                        @ThresholdRed         = @TemplateThresholdRed,
                        @ThresholdDirection   = @TemplateThresholdDirection,
                        @SubmitterGuidance    = @TemplateSubmitterGuidance,
                        @AssignmentGroupName  = @TemplateGroupName,
                        @ActorUPN             = @ActorUPN,
                        @AssignmentID         = @GeneratedAssignmentId OUTPUT;

                    FETCH NEXT FROM site_cursor INTO @SiteOrgUnitCode;
                END

                CLOSE site_cursor;
                DEALLOCATE site_cursor;
            END
            ELSE
            BEGIN
                -- Site-specific template: single assignment
                SET @GeneratedAssignmentId = NULL;
                EXEC App.usp_AssignKpi
                    @KPICode              = @TemplateKpiCode,
                    @AccountCode          = @TemplateAccountCode,
                    @OrgUnitCode          = @TemplateOrgUnitCode,
                    @OrgUnitType          = @TemplateOrgUnitType,
                    @PeriodScheduleID     = @TemplateScheduleId,
                    @PeriodYear           = @CurrentPeriodYear,
                    @PeriodMonth          = @CurrentPeriodMonth,
                    @AssignmentTemplateID = @CurrentTemplateId,
                    @IsRequired           = @TemplateIsRequired,
                    @TargetValue          = @TemplateTargetValue,
                    @ThresholdGreen       = @TemplateThresholdGreen,
                    @ThresholdAmber       = @TemplateThresholdAmber,
                    @ThresholdRed         = @TemplateThresholdRed,
                    @ThresholdDirection   = @TemplateThresholdDirection,
                    @SubmitterGuidance    = @TemplateSubmitterGuidance,
                    @AssignmentGroupName  = @TemplateGroupName,
                    @ActorUPN             = @ActorUPN,
                    @AssignmentID         = @GeneratedAssignmentId OUTPUT;
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
            @TemplateThresholdDirection, @TemplateSubmitterGuidance, @TemplateGroupName;
    END

    CLOSE template_cursor;
    DEALLOCATE template_cursor;
END;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. Update App.usp_CreateSubmissionToken
--    Accept optional @AssignmentGroupName; stamp on INSERT.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE App.usp_CreateSubmissionToken
    @SiteOrgUnitId       INT,
    @PeriodId            INT,
    @CreatedBy           NVARCHAR(128),
    @AssignmentGroupName NVARCHAR(100)    = NULL,
    @TokenId             UNIQUEIDENTIFIER OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @AccountId INT;
    DECLARE @SubmissionCloseDate DATE;
    DECLARE @ExpiresAtUtc DATETIME2;

    SELECT @AccountId = AccountId
    FROM App.vOrgUnits
    WHERE OrgUnitId = @SiteOrgUnitId
      AND OrgUnitType = 'Site'
      AND IsActive = 1;

    IF @AccountId IS NULL
        THROW 50210, 'Active site not found.', 1;

    SELECT @SubmissionCloseDate = CAST(SubmissionCloseDate AS DATE)
    FROM App.vKpiPeriods
    WHERE PeriodId = @PeriodId;

    IF @SubmissionCloseDate IS NULL
        THROW 50211, 'Period not found.', 1;

    SET @ExpiresAtUtc = DATEADD(SECOND, -1, DATEADD(DAY, 1, CAST(@SubmissionCloseDate AS DATETIME2)));
    SET @TokenId = NEWID();

    INSERT INTO KPI.SubmissionToken
        (TokenId, SiteOrgUnitId, AccountId, PeriodId, ExpiresAtUtc, CreatedBy, AssignmentGroupName)
    VALUES
        (@TokenId, @SiteOrgUnitId, @AccountId, @PeriodId, @ExpiresAtUtc, @CreatedBy, @AssignmentGroupName);
END;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. Update App.vKpiAssignmentTemplates — add AssignmentGroupName
-- ─────────────────────────────────────────────────────────────────────────────
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
        t.AssignmentGroupName
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
          AND (
                (t.OrgUnitId IS NULL AND a.OrgUnitId IS NULL)
                OR a.OrgUnitId = t.OrgUnitId
              )
          AND (
                (t.AssignmentGroupName IS NULL AND a.AssignmentGroupName IS NULL)
                OR a.AssignmentGroupName = t.AssignmentGroupName
              )
          AND (p.PeriodYear * 100 + p.PeriodMonth) >= (
                COALESCE(t.StartPeriodYear, YEAR(sched.StartDate)) * 100
                + COALESCE(t.StartPeriodMonth, MONTH(sched.StartDate))
              )
          AND (
                COALESCE(t.EndPeriodYear, YEAR(sched.EndDate)) IS NULL
                OR (p.PeriodYear * 100 + p.PeriodMonth) <= (
                    COALESCE(t.EndPeriodYear, YEAR(sched.EndDate)) * 100
                    + COALESCE(t.EndPeriodMonth, MONTH(sched.EndDate))
                )
              )
          AND (
                DATEDIFF(
                    MONTH,
                    DATEFROMPARTS(YEAR(sched.StartDate), MONTH(sched.StartDate), 1),
                    DATEFROMPARTS(p.PeriodYear, p.PeriodMonth, 1)
                )
                %
                CASE
                    WHEN sched.FrequencyType = 'Monthly' THEN 1
                    WHEN sched.FrequencyType = 'EveryNMonths' THEN sched.FrequencyInterval
                    WHEN sched.FrequencyType = 'Quarterly' THEN 3
                    WHEN sched.FrequencyType = 'SemiAnnual' THEN 6
                    WHEN sched.FrequencyType = 'Annual' THEN 12
                    ELSE 1
                END
              ) = 0
    ) AS instances;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 11. Update App.vKpiAssignments — add AssignmentGroupName
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER VIEW App.vKpiAssignments
AS
    -- Used by: assignment management screen (K-03), assign KPI modal
    SELECT
        a.AssignmentID,
        a.ExternalId,
        a.KPIID,
        d.KPICode,
        d.KPIName,
        d.Category,
        d.DataType,
        d.CollectionType,
        a.AccountId,
        acct.AccountCode,
        acct.AccountName,
        a.OrgUnitId,
        ou.OrgUnitCode      AS SiteCode,
        ou.OrgUnitName      AS SiteName,
        ou.CountryCode,
        -- NULL OrgUnitId = account-wide assignment
        CASE WHEN a.OrgUnitId IS NULL THEN 1 ELSE 0 END AS IsAccountWide,
        a.PeriodID,
        p.PeriodScheduleID,
        sched.ScheduleName,
        p.PeriodLabel,
        p.PeriodYear,
        p.PeriodMonth,
        p.Status            AS PeriodStatus,
        a.IsRequired,
        a.TargetValue,
        a.ThresholdGreen,
        a.ThresholdAmber,
        a.ThresholdRed,
        -- Effective threshold direction: assignment override > definition default
        COALESCE(a.ThresholdDirection, d.ThresholdDirection) AS EffectiveThresholdDirection,
        a.SubmitterGuidance,
        -- Source template (NULL for manually created assignments)
        a.AssignmentTemplateID,
        -- Effective name / description: template override → library default
        COALESCE(tmpl.CustomKpiName,        d.KPIName)        AS EffectiveKpiName,
        COALESCE(tmpl.CustomKpiDescription, d.KPIDescription) AS EffectiveKpiDescription,
        a.IsActive,
        a.CreatedOnUtc,
        a.ModifiedOnUtc,
        -- Escalation contact count for this site+period
        ISNULL(esc.ContactCount, 0) AS EscalationContactCount,
        a.AssignmentGroupName
    FROM KPI.Assignment AS a
    JOIN KPI.Definition             AS d     ON d.KPIID       = a.KPIID
    JOIN Dim.Account                AS acct  ON acct.AccountId = a.AccountId
    JOIN KPI.Period                 AS p     ON p.PeriodID    = a.PeriodID
    LEFT JOIN KPI.PeriodSchedule    AS sched ON sched.PeriodScheduleID = p.PeriodScheduleID
    LEFT JOIN Dim.OrgUnit           AS ou    ON ou.OrgUnitId  = a.OrgUnitId
    LEFT JOIN KPI.AssignmentTemplate AS tmpl ON tmpl.AssignmentTemplateID = a.AssignmentTemplateID
    OUTER APPLY
    (
        SELECT COUNT(*) AS ContactCount
        FROM KPI.EscalationContact AS ec
        WHERE ec.OrgUnitId = a.OrgUnitId
          AND ec.PeriodID  = a.PeriodID
          AND ec.IsActive  = 1
    ) AS esc;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 12. Update App.vSiteCompletionSummary — group by AssignmentGroupName
--     Now produces one row per (Site, Period, AssignmentGroupName).
--     NULL AssignmentGroupName = ungrouped assignments.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER VIEW App.vSiteCompletionSummary
AS
    -- Expand both site-specific and account-wide assignments to individual site rows.
    -- Account-wide assignments share a single submission row; if submitted it counts
    -- as complete for every site in the account.
    -- Site-specific assignments shadow account-wide ones for the same KPI + period.
    WITH AllSiteAssignments AS
    (
        -- 1. Site-specific: one row per assignment, scoped to its own site
        SELECT
            a.AssignmentID,
            a.PeriodID,
            a.AccountId,
            a.OrgUnitId     AS SiteOrgUnitId,
            a.AssignmentGroupName
        FROM KPI.Assignment AS a
        JOIN Dim.OrgUnit    AS ou
            ON  ou.OrgUnitId   = a.OrgUnitId
            AND ou.OrgUnitType = 'Site'
        WHERE a.IsActive    = 1
          AND a.OrgUnitId   IS NOT NULL

        UNION ALL

        -- 2. Account-wide: expand to every active Site under the same account.
        -- Suppressed where a site-specific assignment exists for the same KPI + period + group.
        SELECT
            a.AssignmentID,
            a.PeriodID,
            a.AccountId,
            site.OrgUnitId  AS SiteOrgUnitId,
            a.AssignmentGroupName
        FROM KPI.Assignment AS a
        JOIN Dim.OrgUnit    AS site
            ON  site.AccountId   = a.AccountId
            AND site.OrgUnitType = 'Site'
            AND site.IsActive    = 1
        WHERE a.IsActive    = 1
          AND a.OrgUnitId   IS NULL       -- account-wide flag
          AND NOT EXISTS (
                SELECT 1 FROM KPI.Assignment AS sa
                WHERE  sa.KPIID     = a.KPIID
                  AND  sa.OrgUnitId = site.OrgUnitId
                  AND  sa.PeriodID  = a.PeriodID
                  AND  sa.IsActive  = 1
                  AND  (
                         (a.AssignmentGroupName IS NULL AND sa.AssignmentGroupName IS NULL)
                         OR sa.AssignmentGroupName = a.AssignmentGroupName
                       )
          )
    )
    SELECT
        acct.AccountId,
        acct.AccountCode,
        acct.AccountName,
        site.OrgUnitId          AS SiteOrgUnitId,
        site.OrgUnitCode        AS SiteCode,
        site.OrgUnitName        AS SiteName,
        site.CountryCode,
        p.PeriodID,
        p.PeriodLabel,
        p.Status                AS PeriodStatus,
        -- Total required assignments for this site+period+group
        COUNT(sa.AssignmentID)                                   AS TotalRequired,
        -- Submitted
        SUM(CASE WHEN sub.SubmissionID IS NOT NULL
                  AND sub.LockState <> 'LockedByPeriodClose'
                 THEN 1 ELSE 0 END)                             AS TotalSubmitted,
        -- Locked (confirmed)
        SUM(CASE WHEN sub.LockState IN ('Locked','LockedByAuto','LockedByPeriodClose')
                 THEN 1 ELSE 0 END)                             AS TotalLocked,
        -- Missing (assigned but no submission yet)
        SUM(CASE WHEN sub.SubmissionID IS NULL THEN 1 ELSE 0 END) AS TotalMissing,
        -- Completion percentage
        CASE
            WHEN COUNT(sa.AssignmentID) = 0 THEN NULL
            ELSE CAST(
                    SUM(CASE WHEN sub.SubmissionID IS NOT NULL
                              AND sub.LockState <> 'LockedByPeriodClose'
                             THEN 1 ELSE 0 END) * 100.0
                    / COUNT(sa.AssignmentID)
                 AS DECIMAL(5,1))
        END                                                     AS CompletionPct,
        -- Exception flags for the Account Director view
        CAST(CASE
            WHEN p.Status = 'Open'
             AND DATEDIFF(DAY, CAST(SYSUTCDATETIME() AS DATE), p.SubmissionCloseDate) <= 3
             AND SUM(CASE WHEN sub.SubmissionID IS NULL THEN 1 ELSE 0 END) * 100.0
                 / NULLIF(COUNT(sa.AssignmentID), 0) > 50
            THEN 1 ELSE 0
        END AS BIT)                                             AS IsLateRisk,
        CAST(CASE
            WHEN p.Status = 'Closed'
             AND SUM(CASE WHEN sub.SubmissionID IS NULL THEN 1 ELSE 0 END) > 0
            THEN 1 ELSE 0
        END AS BIT)                                             AS IsOverdue,
        -- Schedule context
        p.PeriodScheduleID,
        sched.ScheduleName,
        -- Reminder state (keyed to site+period)
        rs.CurrentLevel         AS ReminderLevel,
        rs.LastReminderSentAt,
        rs.NextReminderDueAt,
        rs.IsResolved           AS ReminderResolved,
        -- Group dimension (NULL = ungrouped)
        sa.AssignmentGroupName  AS GroupName
    FROM AllSiteAssignments      AS sa
    JOIN KPI.Period              AS p     ON p.PeriodID    = sa.PeriodID
    JOIN KPI.PeriodSchedule     AS sched ON sched.PeriodScheduleID = p.PeriodScheduleID
    JOIN Dim.OrgUnit             AS site  ON site.OrgUnitId = sa.SiteOrgUnitId
    JOIN Dim.Account             AS acct  ON acct.AccountId = sa.AccountId
    LEFT JOIN KPI.Submission     AS sub   ON sub.AssignmentID = sa.AssignmentID
    LEFT JOIN Workflow.ReminderState AS rs
        ON rs.OrgUnitId = sa.SiteOrgUnitId
       AND rs.PeriodID  = sa.PeriodID
    GROUP BY
        acct.AccountId, acct.AccountCode, acct.AccountName,
        site.OrgUnitId, site.OrgUnitCode, site.OrgUnitName, site.CountryCode,
        p.PeriodID, p.PeriodLabel, p.Status, p.SubmissionCloseDate, p.PeriodScheduleID,
        sched.ScheduleName,
        rs.CurrentLevel, rs.LastReminderSentAt, rs.NextReminderDueAt, rs.IsResolved,
        sa.AssignmentGroupName;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 13. Update App.vSiteSubmissionDetails — add AssignmentGroupName
-- ─────────────────────────────────────────────────────────────────────────────
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

-- ─────────────────────────────────────────────────────────────────────────────
-- 14. Update App.vSubmissionTokens — add AssignmentGroupName
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER VIEW App.vSubmissionTokens
AS
    SELECT
        st.TokenId,
        st.SiteOrgUnitId,
        st.AccountId,
        st.PeriodId,
        site.OrgUnitCode AS SiteCode,
        site.OrgUnitName AS SiteName,
        acct.AccountCode,
        acct.AccountName,
        period.PeriodLabel,
        period.Status AS PeriodStatus,
        CAST(period.SubmissionCloseDate AS DATETIME2) AS PeriodCloseDate,
        st.ExpiresAtUtc,
        st.CreatedBy,
        st.CreatedAtUtc,
        st.RevokedAtUtc,
        st.AssignmentGroupName
    FROM KPI.SubmissionToken AS st
    JOIN App.vOrgUnits AS site
        ON site.OrgUnitId = st.SiteOrgUnitId
    JOIN App.vAccounts AS acct
        ON acct.AccountId = st.AccountId
    JOIN App.vKpiPeriods AS period
        ON period.PeriodId = st.PeriodId;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 15. Update App.vSubmissionTokenAssignments — filter by group
--     When the token has a group name, only return assignments for that group.
--     When the token has no group (NULL), return only ungrouped assignments.
-- ─────────────────────────────────────────────────────────────────────────────
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
       -- Filter assignments to match the token's group (NULL-safe)
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

-- ─────────────────────────────────────────────────────────────────────────────
-- 16. New view: App.vAssignmentGroups
--     Distinct group names per account — used to populate the group combobox.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER VIEW App.vAssignmentGroups
AS
    SELECT DISTINCT
        t.AccountId,
        acct.AccountCode,
        acct.AccountName,
        t.AssignmentGroupName AS GroupName
    FROM KPI.AssignmentTemplate AS t
    JOIN Dim.Account AS acct ON acct.AccountId = t.AccountId
    WHERE t.AssignmentGroupName IS NOT NULL
      AND t.IsActive = 1;
GO
