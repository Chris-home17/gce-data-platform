-- ============================================================
-- Migration: KpiScoring — Down
-- Reverts the scoring layer: drops the new proc, restores the four
-- updated procs to their pre-scoring versions, drops constraints +
-- columns + KPI.CategoryWeight.
-- ============================================================

IF OBJECT_ID('App.usp_UpsertCategoryWeights', 'P') IS NOT NULL
    DROP PROCEDURE App.usp_UpsertCategoryWeights;
GO

-- Restore vKpiAssignmentTemplates without the scoring columns. Must run BEFORE
-- the columns are dropped or the view definition would reference dead columns.
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
        t.KpiPackageId, pkg.PackageName AS KpiPackageName, t.AssignmentGroupName
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

-- ─── Restore usp_AssignKpi (pre-scoring signature) ──────────────

CREATE OR ALTER PROCEDURE App.usp_AssignKpi
    @KPICode              NVARCHAR(50),
    @AccountCode          NVARCHAR(50),
    @OrgUnitCode          NVARCHAR(50)    = NULL,
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
        SET IsRequired = @IsRequired, TargetValue = @TargetValue,
            ThresholdGreen = @ThresholdGreen, ThresholdAmber = @ThresholdAmber, ThresholdRed = @ThresholdRed,
            ThresholdDirection = @ThresholdDirection, SubmitterGuidance = @SubmitterGuidance,
            IsActive = 1, ModifiedOnUtc = SYSUTCDATETIME(), ModifiedBy = COALESCE(@ActorUPN, SESSION_USER)
        WHERE AssignmentID = @AssignmentID;
    END
END;
GO

-- ─── Restore usp_UpsertKpiAssignmentTemplate (pre-scoring) ──────

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
        SET PeriodScheduleID = @PeriodScheduleID, StartPeriodYear = @StartPeriodYear, StartPeriodMonth = @StartPeriodMonth,
            EndPeriodYear = @EndPeriodYear, EndPeriodMonth = @EndPeriodMonth, IsRequired = @IsRequired,
            TargetValue = @TargetValue, ThresholdGreen = @ThresholdGreen, ThresholdAmber = @ThresholdAmber,
            ThresholdRed = @ThresholdRed, ThresholdDirection = @ThresholdDirection,
            SubmitterGuidance = @SubmitterGuidance, CustomKpiName = @CustomKpiName,
            CustomKpiDescription = @CustomKpiDescription, KpiPackageId = @KpiPackageId,
            IsActive = 1, ModifiedOnUtc = SYSUTCDATETIME(), ModifiedBy = COALESCE(@ActorUPN, SESSION_USER)
        WHERE AssignmentTemplateID = @AssignmentTemplateID;
    END
END;
GO

-- ─── Restore usp_MaterializeKpiAssignmentTemplates (pre-scoring) ─

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
        @TemplateIsRequired BIT,
        @TemplateTargetValue DECIMAL(18,4),
        @TemplateThresholdGreen DECIMAL(18,4), @TemplateThresholdAmber DECIMAL(18,4), @TemplateThresholdRed DECIMAL(18,4),
        @TemplateThresholdDirection NVARCHAR(10), @TemplateSubmitterGuidance NVARCHAR(1000),
        @TemplateGroupName NVARCHAR(100),
        @SiteOrgUnitCode NVARCHAR(50);

    DECLARE template_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT t.AssignmentTemplateID, d.KPICode, t.PeriodScheduleID, sched.StartDate, sched.EndDate,
               acct.AccountCode, ou.OrgUnitCode, COALESCE(ou.OrgUnitType, 'Site'),
               t.StartPeriodYear, t.StartPeriodMonth, t.EndPeriodYear, t.EndPeriodMonth,
               t.IsRequired, t.TargetValue, t.ThresholdGreen, t.ThresholdAmber, t.ThresholdRed,
               t.ThresholdDirection, t.SubmitterGuidance, t.AssignmentGroupName
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
        @TemplateThresholdDirection, @TemplateSubmitterGuidance, @TemplateGroupName;

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
                        @ActorUPN = @ActorUPN, @AssignmentID = @GeneratedAssignmentId OUTPUT;

                    FETCH NEXT FROM site_cursor INTO @SiteOrgUnitCode;
                END
                CLOSE site_cursor;
                DEALLOCATE site_cursor;
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
                    @ActorUPN = @ActorUPN, @AssignmentID = @GeneratedAssignmentId OUTPUT;
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

-- ─── Restore usp_CascadeAssignmentTemplateThresholds (pre-scoring) ─

CREATE OR ALTER PROCEDURE App.usp_CascadeAssignmentTemplateThresholds
    @AssignmentTemplateID INT,
    @ActorUPN             NVARCHAR(320) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE a
    SET IsRequired         = t.IsRequired,
        TargetValue        = t.TargetValue,
        ThresholdGreen     = t.ThresholdGreen,
        ThresholdAmber     = t.ThresholdAmber,
        ThresholdRed       = t.ThresholdRed,
        ThresholdDirection = t.ThresholdDirection,
        SubmitterGuidance  = t.SubmitterGuidance,
        ModifiedOnUtc      = SYSUTCDATETIME(),
        ModifiedBy         = COALESCE(@ActorUPN, SESSION_USER)
    FROM KPI.Assignment         AS a
    JOIN KPI.AssignmentTemplate AS t ON t.AssignmentTemplateID = a.AssignmentTemplateID
    WHERE t.AssignmentTemplateID = @AssignmentTemplateID
      AND NOT EXISTS (SELECT 1 FROM KPI.Submission s WHERE s.AssignmentID = a.AssignmentID);
END;
GO

-- ─── Drop check constraints + scoring columns ─────────────────

IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_KpiAsgn_MSRule' AND parent_object_id = OBJECT_ID(N'KPI.Assignment'))
    ALTER TABLE KPI.Assignment DROP CONSTRAINT CK_KpiAsgn_MSRule;
GO
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_KpiAsgn_ScoringMode' AND parent_object_id = OBJECT_ID(N'KPI.Assignment'))
    ALTER TABLE KPI.Assignment DROP CONSTRAINT CK_KpiAsgn_ScoringMode;
GO
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_KpiTpl_MSRule' AND parent_object_id = OBJECT_ID(N'KPI.AssignmentTemplate'))
    ALTER TABLE KPI.AssignmentTemplate DROP CONSTRAINT CK_KpiTpl_MSRule;
GO
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_KpiTpl_ScoringMode' AND parent_object_id = OBJECT_ID(N'KPI.AssignmentTemplate'))
    ALTER TABLE KPI.AssignmentTemplate DROP CONSTRAINT CK_KpiTpl_ScoringMode;
GO

-- KPI.Assignment columns + their default constraints
DECLARE @sql NVARCHAR(MAX);
DECLARE @asgnCols TABLE (col SYSNAME);
INSERT @asgnCols VALUES
    ('PenaliseMissingOnScore'),('MultiSelectScoreRule'),('BooleanNoPoints'),('BooleanYesPoints'),
    ('BandPointsRed'),('BandPointsAmber'),('BandPointsGreen'),('ScoringMode'),('KpiWeight');

DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT col FROM @asgnCols;
DECLARE @col SYSNAME;
OPEN c; FETCH NEXT FROM c INTO @col;
WHILE @@FETCH_STATUS = 0
BEGIN
    -- Drop default constraint if any
    SELECT @sql = 'ALTER TABLE KPI.Assignment DROP CONSTRAINT ' + QUOTENAME(dc.name) + ';'
    FROM sys.default_constraints dc
    JOIN sys.columns col ON col.default_object_id = dc.object_id
    WHERE dc.parent_object_id = OBJECT_ID(N'KPI.Assignment')
      AND col.name = @col;
    IF @sql IS NOT NULL EXEC sp_executesql @sql;
    SET @sql = NULL;

    IF COL_LENGTH('KPI.Assignment', @col) IS NOT NULL
    BEGIN
        SET @sql = 'ALTER TABLE KPI.Assignment DROP COLUMN ' + QUOTENAME(@col) + ';';
        EXEC sp_executesql @sql;
    END
    FETCH NEXT FROM c INTO @col;
END
CLOSE c; DEALLOCATE c;
GO

-- KPI.AssignmentTemplate columns + their default constraints
DECLARE @sql NVARCHAR(MAX);
DECLARE @tplCols TABLE (col SYSNAME);
INSERT @tplCols VALUES
    ('PenaliseMissingOnScore'),('MultiSelectScoreRule'),('BooleanNoPoints'),('BooleanYesPoints'),
    ('BandPointsRed'),('BandPointsAmber'),('BandPointsGreen'),('ScoringMode'),('KpiWeight');

DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT col FROM @tplCols;
DECLARE @col SYSNAME;
OPEN c; FETCH NEXT FROM c INTO @col;
WHILE @@FETCH_STATUS = 0
BEGIN
    SELECT @sql = 'ALTER TABLE KPI.AssignmentTemplate DROP CONSTRAINT ' + QUOTENAME(dc.name) + ';'
    FROM sys.default_constraints dc
    JOIN sys.columns col ON col.default_object_id = dc.object_id
    WHERE dc.parent_object_id = OBJECT_ID(N'KPI.AssignmentTemplate')
      AND col.name = @col;
    IF @sql IS NOT NULL EXEC sp_executesql @sql;
    SET @sql = NULL;

    IF COL_LENGTH('KPI.AssignmentTemplate', @col) IS NOT NULL
    BEGIN
        SET @sql = 'ALTER TABLE KPI.AssignmentTemplate DROP COLUMN ' + QUOTENAME(@col) + ';';
        EXEC sp_executesql @sql;
    END
    FETCH NEXT FROM c INTO @col;
END
CLOSE c; DEALLOCATE c;
GO

-- KPI.AssignmentTemplateDropDownOption.Points
IF EXISTS (
    SELECT 1 FROM sys.default_constraints dc
    JOIN sys.columns col ON col.default_object_id = dc.object_id
    WHERE dc.parent_object_id = OBJECT_ID(N'KPI.AssignmentTemplateDropDownOption')
      AND col.name = 'Points'
)
BEGIN
    DECLARE @dn SYSNAME = (
        SELECT dc.name FROM sys.default_constraints dc
        JOIN sys.columns col ON col.default_object_id = dc.object_id
        WHERE dc.parent_object_id = OBJECT_ID(N'KPI.AssignmentTemplateDropDownOption') AND col.name = 'Points'
    );
    DECLARE @s NVARCHAR(MAX) = 'ALTER TABLE KPI.AssignmentTemplateDropDownOption DROP CONSTRAINT ' + QUOTENAME(@dn) + ';';
    EXEC sp_executesql @s;
END
GO

IF COL_LENGTH('KPI.AssignmentTemplateDropDownOption', 'Points') IS NOT NULL
    ALTER TABLE KPI.AssignmentTemplateDropDownOption DROP COLUMN Points;
GO

-- ─── Drop KPI.CategoryWeight ─────────────────────────────────

IF OBJECT_ID('KPI.CategoryWeight', 'U') IS NOT NULL
    DROP TABLE KPI.CategoryWeight;
GO
