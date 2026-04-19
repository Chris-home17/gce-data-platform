-- ============================================================
-- Migration: TagsAndKpiPackages — Up
-- Adds:
--   1. Dim.Tag           — generic platform-level tag entity
--   2. KPI.KpiTag        — many-to-many KPI ↔ Tag
--   3. KPI.KpiPackage    — named bundle of KPIs (optional Tag)
--   4. KPI.KpiPackageItem — KPIs in a package (junction)
--   5. KpiPackageId FK   — on KPI.AssignmentTemplate (tracks package origin)
--   6. App.vTags, App.vKpiPackages, App.vKpiPackageItems views
--   7. Updated App.vKpiDefinitions  — adds TagsRaw column
--   8. Updated App.vKpiAssignmentTemplates — adds KpiPackageId / KpiPackageName
--   9. New stored procedures for tags and packages
-- Safe to re-run: all DDL uses idempotent guards.
-- ============================================================
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Dim.Tag
-- ─────────────────────────────────────────────────────────────────────────────
IF OBJECT_ID('Dim.Tag', 'U') IS NULL
BEGIN
    CREATE TABLE Dim.Tag
    (
        TagId          INT            IDENTITY(1,1) NOT NULL PRIMARY KEY,
        TagCode        NVARCHAR(50)   NOT NULL,
        TagName        NVARCHAR(100)  NOT NULL,
        TagDescription NVARCHAR(500)  NULL,
        IsActive       BIT            NOT NULL CONSTRAINT DF_Tag_IsActive        DEFAULT (1),
        CreatedOnUtc   DATETIME2      NOT NULL CONSTRAINT DF_Tag_CreatedOnUtc    DEFAULT (SYSUTCDATETIME()),
        ModifiedOnUtc  DATETIME2      NOT NULL CONSTRAINT DF_Tag_ModifiedOnUtc   DEFAULT (SYSUTCDATETIME()),
        CreatedBy      NVARCHAR(128)  NOT NULL CONSTRAINT DF_Tag_CreatedBy       DEFAULT (SESSION_USER),
        ModifiedBy     NVARCHAR(128)  NOT NULL CONSTRAINT DF_Tag_ModifiedBy      DEFAULT (SESSION_USER)
    );

    CREATE UNIQUE INDEX UX_Tag_Code ON Dim.Tag (TagCode);
END;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. KPI.KpiTag (many-to-many: KPI ↔ Tag)
-- ─────────────────────────────────────────────────────────────────────────────
IF OBJECT_ID('KPI.KpiTag', 'U') IS NULL
BEGIN
    CREATE TABLE KPI.KpiTag
    (
        KpiTagId  INT NOT NULL IDENTITY(1,1) PRIMARY KEY,
        KpiId     INT NOT NULL REFERENCES KPI.Definition(KPIID) ON DELETE CASCADE,
        TagId     INT NOT NULL REFERENCES Dim.Tag(TagId),
        CONSTRAINT UX_KpiTag_KpiTag UNIQUE (KpiId, TagId)
    );

    CREATE INDEX IX_KpiTag_TagId ON KPI.KpiTag (TagId);
END;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. KPI.KpiPackage
-- ─────────────────────────────────────────────────────────────────────────────
IF OBJECT_ID('KPI.KpiPackage', 'U') IS NULL
BEGIN
    CREATE TABLE KPI.KpiPackage
    (
        KpiPackageId  INT            IDENTITY(1,1) NOT NULL PRIMARY KEY,
        PackageCode   NVARCHAR(50)   NOT NULL,
        PackageName   NVARCHAR(200)  NOT NULL,
        TagId         INT            NULL REFERENCES Dim.Tag(TagId),
        IsActive      BIT            NOT NULL CONSTRAINT DF_KpiPackage_IsActive       DEFAULT (1),
        CreatedOnUtc  DATETIME2      NOT NULL CONSTRAINT DF_KpiPackage_CreatedOnUtc   DEFAULT (SYSUTCDATETIME()),
        ModifiedOnUtc DATETIME2      NOT NULL CONSTRAINT DF_KpiPackage_ModifiedOnUtc  DEFAULT (SYSUTCDATETIME()),
        CreatedBy     NVARCHAR(128)  NOT NULL CONSTRAINT DF_KpiPackage_CreatedBy      DEFAULT (SESSION_USER),
        ModifiedBy    NVARCHAR(128)  NOT NULL CONSTRAINT DF_KpiPackage_ModifiedBy     DEFAULT (SESSION_USER),
        CONSTRAINT UX_KpiPackage_Code UNIQUE (PackageCode)
    );
END;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. KPI.KpiPackageItem
-- ─────────────────────────────────────────────────────────────────────────────
IF OBJECT_ID('KPI.KpiPackageItem', 'U') IS NULL
BEGIN
    CREATE TABLE KPI.KpiPackageItem
    (
        KpiPackageItemId INT NOT NULL IDENTITY(1,1) PRIMARY KEY,
        KpiPackageId     INT NOT NULL REFERENCES KPI.KpiPackage(KpiPackageId) ON DELETE CASCADE,
        KpiId            INT NOT NULL REFERENCES KPI.Definition(KPIID),
        CONSTRAINT UX_KpiPackageItem_PackageKpi UNIQUE (KpiPackageId, KpiId)
    );

    CREATE INDEX IX_KpiPackageItem_KpiId ON KPI.KpiPackageItem (KpiId);
END;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. KpiPackageId column on KPI.AssignmentTemplate (tracks package origin)
-- ─────────────────────────────────────────────────────────────────────────────
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('KPI.AssignmentTemplate')
      AND name = 'KpiPackageId'
)
BEGIN
    ALTER TABLE KPI.AssignmentTemplate
        ADD KpiPackageId INT NULL REFERENCES KPI.KpiPackage(KpiPackageId);
END;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 6a. App.vTags
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER VIEW App.vTags
AS
    SELECT
        t.TagId,
        t.TagCode,
        t.TagName,
        t.TagDescription,
        t.IsActive,
        ISNULL(usage.KpiCount, 0) AS KpiCount
    FROM Dim.Tag AS t
    OUTER APPLY
    (
        SELECT COUNT(*) AS KpiCount
        FROM KPI.KpiTag AS kt
        WHERE kt.TagId = t.TagId
    ) AS usage;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 6b. App.vKpiPackages
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER VIEW App.vKpiPackages
AS
    SELECT
        p.KpiPackageId,
        p.PackageCode,
        p.PackageName,
        p.TagId,
        t.TagCode,
        t.TagName AS TagName,
        p.IsActive,
        ISNULL(items.KpiCount, 0) AS KpiCount
    FROM KPI.KpiPackage AS p
    LEFT JOIN Dim.Tag AS t ON t.TagId = p.TagId
    OUTER APPLY
    (
        SELECT COUNT(*) AS KpiCount
        FROM KPI.KpiPackageItem AS pi
        WHERE pi.KpiPackageId = p.KpiPackageId
    ) AS items;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 6c. App.vKpiPackageItems
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER VIEW App.vKpiPackageItems
AS
    SELECT
        pi.KpiPackageItemId,
        pi.KpiPackageId,
        pi.KpiId,
        d.KPICode   AS KpiCode,
        d.KPIName   AS KpiName,
        d.Category,
        d.DataType,
        d.IsActive  AS KpiIsActive
    FROM KPI.KpiPackageItem AS pi
    JOIN KPI.Definition AS d ON d.KPIID = pi.KpiId;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Update App.vKpiDefinitions — add TagsRaw column
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER VIEW App.vKpiDefinitions
AS
    SELECT
        d.KPIID,
        d.ExternalId,
        d.KPICode,
        d.KPIName,
        d.KPIDescription,
        d.Category,
        d.Unit,
        d.DataType,
        d.AllowMultiValue,
        d.CollectionType,
        d.ThresholdDirection,
        d.SourceSystemRef,
        d.IsActive,
        d.CreatedOnUtc,
        d.ModifiedOnUtc,
        ISNULL(assignments.AssignmentCount, 0) AS AssignmentCount,
        CASE WHEN d.DataType = 'DropDown' THEN (
            SELECT STRING_AGG(opt.OptionValue, '||') WITHIN GROUP (ORDER BY opt.SortOrder)
            FROM KPI.DropDownOption AS opt
            WHERE opt.KPIID = d.KPIID AND opt.IsActive = 1
        ) ELSE NULL END AS DropDownOptionsRaw,
        -- Tags as pipe-delimited "TagId:TagName" pairs for efficient frontend parsing
        (
            SELECT STRING_AGG(CAST(t.TagId AS NVARCHAR(10)) + ':' + t.TagName, '|')
            FROM KPI.KpiTag AS kt
            JOIN Dim.Tag AS t ON t.TagId = kt.TagId
            WHERE kt.KpiId = d.KPIID
        ) AS TagsRaw
    FROM KPI.Definition AS d
    OUTER APPLY
    (
        SELECT COUNT(*) AS AssignmentCount
        FROM KPI.Assignment AS a
        WHERE a.KPIID    = d.KPIID
          AND a.IsActive = 1
    ) AS assignments;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. Update App.vKpiAssignmentTemplates — add KpiPackageId / KpiPackageName
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
        -- Package tracking (new columns)
        t.KpiPackageId,
        pkg.PackageName AS KpiPackageName,
        ISNULL(instances.GeneratedAssignmentCount, 0) AS GeneratedAssignmentCount
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
-- 9. Stored procedures
-- ─────────────────────────────────────────────────────────────────────────────

-- 9a. App.usp_UpsertTag
CREATE OR ALTER PROCEDURE App.usp_UpsertTag
    @TagCode        NVARCHAR(50),
    @TagName        NVARCHAR(100),
    @TagDescription NVARCHAR(500)  = NULL,
    @ActorUPN       NVARCHAR(320)  = NULL,
    @TagId          INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @TagId = (SELECT TagId FROM Dim.Tag WHERE TagCode = @TagCode);

    IF @TagId IS NULL
    BEGIN
        -- Validate uniqueness of name as well (friendlier error than unique constraint)
        IF EXISTS (SELECT 1 FROM Dim.Tag WHERE TagName = @TagName)
            THROW 50300, 'A tag with this name already exists.', 1;

        INSERT INTO Dim.Tag (TagCode, TagName, TagDescription, IsActive, CreatedBy, ModifiedBy)
        VALUES (@TagCode, @TagName, @TagDescription, 1,
                COALESCE(@ActorUPN, SESSION_USER),
                COALESCE(@ActorUPN, SESSION_USER));

        SET @TagId = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        -- Validate name uniqueness excluding self
        IF EXISTS (SELECT 1 FROM Dim.Tag WHERE TagName = @TagName AND TagId <> @TagId)
            THROW 50301, 'A tag with this name already exists.', 1;

        UPDATE Dim.Tag
        SET TagName        = @TagName,
            TagDescription = @TagDescription,
            ModifiedOnUtc  = SYSUTCDATETIME(),
            ModifiedBy     = COALESCE(@ActorUPN, SESSION_USER)
        WHERE TagId = @TagId;
    END
END;
GO

-- 9b. App.usp_SetTagActive
CREATE OR ALTER PROCEDURE App.usp_SetTagActive
    @TagId    INT,
    @IsActive BIT,
    @ActorUPN NVARCHAR(320) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM Dim.Tag WHERE TagId = @TagId)
        THROW 50302, 'Tag not found.', 1;

    UPDATE Dim.Tag
    SET IsActive      = @IsActive,
        ModifiedOnUtc = SYSUTCDATETIME(),
        ModifiedBy    = COALESCE(@ActorUPN, SESSION_USER)
    WHERE TagId = @TagId;
END;
GO

-- 9c. App.usp_SetKpiTags  (replace-all: deletes existing, inserts new set)
CREATE OR ALTER PROCEDURE App.usp_SetKpiTags
    @KpiId    INT,
    @TagIds   NVARCHAR(MAX),  -- comma-separated tag IDs, e.g. '1,3,7' (empty string = clear all)
    @ActorUPN NVARCHAR(320) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM KPI.Definition WHERE KPIID = @KpiId)
        THROW 50303, 'KPI not found.', 1;

    -- Remove all current tags for this KPI
    DELETE FROM KPI.KpiTag WHERE KpiId = @KpiId;

    -- Re-insert provided tags (empty or NULL = clear only)
    IF @TagIds IS NOT NULL AND LEN(LTRIM(RTRIM(@TagIds))) > 0
    BEGIN
        INSERT INTO KPI.KpiTag (KpiId, TagId)
        SELECT @KpiId, CAST(LTRIM(RTRIM(value)) AS INT)
        FROM STRING_SPLIT(@TagIds, ',')
        WHERE LEN(LTRIM(RTRIM(value))) > 0
          AND ISNUMERIC(LTRIM(RTRIM(value))) = 1;

        -- Validate that all provided TagIds actually exist
        IF EXISTS (
            SELECT 1
            FROM KPI.KpiTag AS kt
            WHERE kt.KpiId = @KpiId
              AND NOT EXISTS (SELECT 1 FROM Dim.Tag WHERE TagId = kt.TagId)
        )
            THROW 50304, 'One or more TagIds are invalid.', 1;
    END
END;
GO

-- 9d. App.usp_UpsertKpiPackage
CREATE OR ALTER PROCEDURE App.usp_UpsertKpiPackage
    @PackageCode  NVARCHAR(50),
    @PackageName  NVARCHAR(200),
    @TagId        INT           = NULL,
    @ActorUPN     NVARCHAR(320) = NULL,
    @KpiPackageId INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @KpiPackageId = (SELECT KpiPackageId FROM KPI.KpiPackage WHERE PackageCode = @PackageCode);

    -- Validate TagId if provided
    IF @TagId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Dim.Tag WHERE TagId = @TagId AND IsActive = 1)
        THROW 50310, 'Tag not found or inactive.', 1;

    IF @KpiPackageId IS NULL
    BEGIN
        INSERT INTO KPI.KpiPackage (PackageCode, PackageName, TagId, IsActive, CreatedBy, ModifiedBy)
        VALUES (@PackageCode, @PackageName, @TagId, 1,
                COALESCE(@ActorUPN, SESSION_USER),
                COALESCE(@ActorUPN, SESSION_USER));

        SET @KpiPackageId = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE KPI.KpiPackage
        SET PackageName   = @PackageName,
            TagId         = @TagId,
            ModifiedOnUtc = SYSUTCDATETIME(),
            ModifiedBy    = COALESCE(@ActorUPN, SESSION_USER)
        WHERE KpiPackageId = @KpiPackageId;
    END
END;
GO

-- 9e. App.usp_SetKpiPackageActive
CREATE OR ALTER PROCEDURE App.usp_SetKpiPackageActive
    @KpiPackageId INT,
    @IsActive     BIT,
    @ActorUPN     NVARCHAR(320) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM KPI.KpiPackage WHERE KpiPackageId = @KpiPackageId)
        THROW 50311, 'KPI Package not found.', 1;

    UPDATE KPI.KpiPackage
    SET IsActive      = @IsActive,
        ModifiedOnUtc = SYSUTCDATETIME(),
        ModifiedBy    = COALESCE(@ActorUPN, SESSION_USER)
    WHERE KpiPackageId = @KpiPackageId;
END;
GO

-- 9e-b. Update App.usp_UpsertKpiAssignmentTemplate to accept @KpiPackageId
CREATE OR ALTER PROCEDURE App.usp_UpsertKpiAssignmentTemplate
    @KPICode              NVARCHAR(50),
    @PeriodScheduleID     INT,
    @AccountCode          NVARCHAR(50),
    @OrgUnitCode          NVARCHAR(50)    = NULL,
    @OrgUnitType          NVARCHAR(20)    = 'Site',
    @StartPeriodYear      SMALLINT        = NULL,
    @StartPeriodMonth     TINYINT         = NULL,
    @EndPeriodYear        SMALLINT        = NULL,
    @EndPeriodMonth       TINYINT         = NULL,
    @IsRequired           BIT             = 1,
    @TargetValue          DECIMAL(18,4)   = NULL,
    @ThresholdGreen       DECIMAL(18,4)   = NULL,
    @ThresholdAmber       DECIMAL(18,4)   = NULL,
    @ThresholdRed         DECIMAL(18,4)   = NULL,
    @ThresholdDirection   NVARCHAR(10)    = NULL,
    @SubmitterGuidance    NVARCHAR(1000)  = NULL,
    @CustomKpiName        NVARCHAR(200)   = NULL,
    @CustomKpiDescription NVARCHAR(1000)  = NULL,
    @KpiPackageId         INT             = NULL,
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
        WHERE AccountId   = @AccountId
          AND OrgUnitCode = @OrgUnitCode
          AND OrgUnitType = @OrgUnitType
          AND IsActive    = 1;

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
    );

    IF @AssignmentTemplateID IS NULL
    BEGIN
        INSERT INTO KPI.AssignmentTemplate
            (KPIID, PeriodScheduleID, AccountId, OrgUnitId,
             StartPeriodYear, StartPeriodMonth, EndPeriodYear, EndPeriodMonth,
             IsRequired, TargetValue, ThresholdGreen, ThresholdAmber, ThresholdRed,
             ThresholdDirection, SubmitterGuidance, CustomKpiName, CustomKpiDescription,
             KpiPackageId)
        VALUES
            (@KPIID, @PeriodScheduleID, @AccountId, @OrgUnitId,
             @StartPeriodYear, @StartPeriodMonth, @EndPeriodYear, @EndPeriodMonth,
             @IsRequired, @TargetValue, @ThresholdGreen, @ThresholdAmber, @ThresholdRed,
             @ThresholdDirection, @SubmitterGuidance, @CustomKpiName, @CustomKpiDescription,
             @KpiPackageId);

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
            KpiPackageId          = COALESCE(@KpiPackageId, KpiPackageId),
            IsActive              = 1,
            ModifiedOnUtc         = SYSUTCDATETIME(),
            ModifiedBy            = COALESCE(@ActorUPN, SESSION_USER)
        WHERE AssignmentTemplateID = @AssignmentTemplateID;
    END
END;
GO

-- 9f. App.usp_SetKpiPackageItems (replace-all membership)
CREATE OR ALTER PROCEDURE App.usp_SetKpiPackageItems
    @KpiPackageId INT,
    @KpiIds       NVARCHAR(MAX),  -- comma-separated KPI IDs (empty = clear all)
    @ActorUPN     NVARCHAR(320)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM KPI.KpiPackage WHERE KpiPackageId = @KpiPackageId)
        THROW 50312, 'KPI Package not found.', 1;

    -- Remove all current items
    DELETE FROM KPI.KpiPackageItem WHERE KpiPackageId = @KpiPackageId;

    IF @KpiIds IS NOT NULL AND LEN(LTRIM(RTRIM(@KpiIds))) > 0
    BEGIN
        -- Validate all provided KpiIds exist
        DECLARE @BadId NVARCHAR(20);
        SELECT TOP 1 @BadId = LTRIM(RTRIM(value))
        FROM STRING_SPLIT(@KpiIds, ',')
        WHERE LEN(LTRIM(RTRIM(value))) > 0
          AND ISNUMERIC(LTRIM(RTRIM(value))) = 1
          AND NOT EXISTS (SELECT 1 FROM KPI.Definition WHERE KPIID = CAST(LTRIM(RTRIM(value)) AS INT));

        IF @BadId IS NOT NULL
            THROW 50313, 'One or more KPI IDs are invalid.', 1;

        INSERT INTO KPI.KpiPackageItem (KpiPackageId, KpiId)
        SELECT DISTINCT @KpiPackageId, CAST(LTRIM(RTRIM(value)) AS INT)
        FROM STRING_SPLIT(@KpiIds, ',')
        WHERE LEN(LTRIM(RTRIM(value))) > 0
          AND ISNUMERIC(LTRIM(RTRIM(value))) = 1;
    END

    UPDATE KPI.KpiPackage
    SET ModifiedOnUtc = SYSUTCDATETIME(),
        ModifiedBy    = COALESCE(@ActorUPN, SESSION_USER)
    WHERE KpiPackageId = @KpiPackageId;
END;
GO
