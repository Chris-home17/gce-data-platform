-- ============================================================
-- Migration: KpiCategoryGlobal — Up
-- ============================================================
-- Converts the free-text KPI Category column into a global lookup table
-- (KPI.Category: KpiCategoryId / Code / Name / Description). Adds
-- KpiCategoryId FK to KPI.Definition + KPI.CategoryWeight, drops the
-- legacy text columns, rebuilds dependent views/procs to JOIN through
-- the lookup. Read views still expose a "Category" column (now sourced
-- from c.Name) so existing Dapper queries keep working.
--
-- Auto-code generation for KPI codes: when usp_UpsertKpiDefinition is
-- called with @KPICode = NULL or '' on INSERT, the code is generated as
-- {CategoryCode}-NNN where NNN is the next available 3-digit suffix in
-- that category, falling back to natural numbers past 999.
-- ============================================================


-- ─── 1. KPI.Category lookup table ────────────────────────────
IF OBJECT_ID('KPI.Category', 'U') IS NULL
BEGIN
    CREATE TABLE KPI.Category
    (
        KpiCategoryId  INT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_KpiCategory PRIMARY KEY,
        ExternalId     UNIQUEIDENTIFIER  NOT NULL
            CONSTRAINT DF_KpiCategory_ExternalId DEFAULT (NEWID()),
        Code           NVARCHAR(20)      NOT NULL,
        Name           NVARCHAR(100)     NOT NULL,
        Description    NVARCHAR(500)     NULL,
        IsActive       BIT               NOT NULL
            CONSTRAINT DF_KpiCategory_IsActive DEFAULT (1),
        CreatedOnUtc   DATETIME2(3)      NOT NULL
            CONSTRAINT DF_KpiCategory_CreatedOn DEFAULT (SYSUTCDATETIME()),
        CreatedBy      NVARCHAR(128)     NOT NULL
            CONSTRAINT DF_KpiCategory_CreatedBy DEFAULT (SESSION_USER),
        ModifiedOnUtc  DATETIME2(3)      NOT NULL
            CONSTRAINT DF_KpiCategory_ModifiedOn DEFAULT (SYSUTCDATETIME()),
        ModifiedBy     NVARCHAR(128)     NOT NULL
            CONSTRAINT DF_KpiCategory_ModifiedBy DEFAULT (SESSION_USER)
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID('KPI.Category') AND name = 'UX_KpiCategory_Code')
    CREATE UNIQUE INDEX UX_KpiCategory_Code        ON KPI.Category (Code);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID('KPI.Category') AND name = 'UX_KpiCategory_ExternalId')
    CREATE UNIQUE INDEX UX_KpiCategory_ExternalId  ON KPI.Category (ExternalId);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID('KPI.Category') AND name = 'IX_KpiCategory_IsActive')
    CREATE INDEX IX_KpiCategory_IsActive ON KPI.Category (IsActive);
GO


-- ─── 2. Backfill from existing distinct categories ──────────
-- Pull DISTINCT category strings from both Definition and CategoryWeight; generate
-- a 3-letter base code (uppercase, alphanumeric only); use ROW_NUMBER to dedupe
-- collisions. Codes are immutable from this point forward.

;WITH src AS (
    SELECT Category
    FROM (
        SELECT Category FROM KPI.Definition
            WHERE Category IS NOT NULL AND LTRIM(RTRIM(Category)) <> ''
        UNION
        SELECT Category FROM KPI.CategoryWeight
            WHERE Category IS NOT NULL AND LTRIM(RTRIM(Category)) <> ''
    ) AS u
    GROUP BY Category
),
alpha AS (
    SELECT
        Category,
        UPPER(LEFT(
            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                Category, ' ', ''), '/', ''), '\', ''), '-', ''), '_', ''), '.', ''), ',', ''),
                '(', ''), ')', ''), '&', ''), '''', ''),
            3)) AS BaseCode
    FROM src
),
ranked AS (
    SELECT
        Category,
        BaseCode,
        ROW_NUMBER() OVER (PARTITION BY BaseCode ORDER BY Category) AS Rn
    FROM alpha
)
INSERT INTO KPI.Category (Code, Name, Description, IsActive)
SELECT
    CASE WHEN ranked.Rn = 1 THEN ranked.BaseCode
         ELSE ranked.BaseCode + CAST(ranked.Rn AS NVARCHAR(5))
    END             AS Code,
    ranked.Category AS Name,
    NULL            AS Description,
    1               AS IsActive
FROM ranked
WHERE NOT EXISTS (SELECT 1 FROM KPI.Category c WHERE c.Name = ranked.Category);
GO

-- Edge case: empty schema → seed a default so the NOT NULL FK has a target.
IF NOT EXISTS (SELECT 1 FROM KPI.Category)
BEGIN
    INSERT INTO KPI.Category (Code, Name, Description, IsActive)
    VALUES ('GEN', 'General', 'Default category — created by KpiCategoryGlobal migration.', 1);
END;
GO


-- ─── 3. KPI.Definition: add FK column, backfill, drop legacy ──
IF COL_LENGTH('KPI.Definition', 'KpiCategoryId') IS NULL
    ALTER TABLE KPI.Definition ADD KpiCategoryId INT NULL;
GO

UPDATE d
SET KpiCategoryId = c.KpiCategoryId
FROM KPI.Definition AS d
JOIN KPI.Category   AS c ON c.Name = d.Category
WHERE d.KpiCategoryId IS NULL AND d.Category IS NOT NULL;
GO

-- Rows with NULL/empty Category get whichever category sorts first (typically General).
UPDATE KPI.Definition
SET KpiCategoryId = (SELECT TOP 1 KpiCategoryId FROM KPI.Category ORDER BY Name)
WHERE KpiCategoryId IS NULL;
GO

-- Drop dependent views BEFORE the column drop so they don't go into a "deferred
-- name resolution" broken state. CREATE OR ALTER doesn't re-bind columns that
-- were resolved at parse time, so we must drop-and-recreate the ones that
-- reference d.Category by name.
IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('KPI.Definition') AND name = 'IX_KpiDef_Category'
)
    DROP INDEX IX_KpiDef_Category ON KPI.Definition;
GO

IF COL_LENGTH('KPI.Definition', 'Category') IS NOT NULL
    ALTER TABLE KPI.Definition DROP COLUMN Category;
GO

IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('KPI.Definition')
      AND name = 'KpiCategoryId' AND is_nullable = 1
)
    ALTER TABLE KPI.Definition ALTER COLUMN KpiCategoryId INT NOT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_KpiDef_Category')
    ALTER TABLE KPI.Definition
        ADD CONSTRAINT FK_KpiDef_Category FOREIGN KEY (KpiCategoryId)
            REFERENCES KPI.Category (KpiCategoryId);
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('KPI.Definition') AND name = 'IX_KpiDef_KpiCategoryId'
)
    CREATE INDEX IX_KpiDef_KpiCategoryId ON KPI.Definition (KpiCategoryId);
GO


-- ─── 4. KPI.CategoryWeight: same treatment ───────────────────
IF COL_LENGTH('KPI.CategoryWeight', 'KpiCategoryId') IS NULL
    ALTER TABLE KPI.CategoryWeight ADD KpiCategoryId INT NULL;
GO

UPDATE cw
SET KpiCategoryId = c.KpiCategoryId
FROM KPI.CategoryWeight AS cw
JOIN KPI.Category       AS c ON c.Name = cw.Category
WHERE cw.KpiCategoryId IS NULL;
GO

-- Drop existing (AccountId, Category) UNIQUE before dropping the column.
IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UX_KpiCatWeight')
    ALTER TABLE KPI.CategoryWeight DROP CONSTRAINT UX_KpiCatWeight;
GO

IF COL_LENGTH('KPI.CategoryWeight', 'Category') IS NOT NULL
    ALTER TABLE KPI.CategoryWeight DROP COLUMN Category;
GO

IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('KPI.CategoryWeight')
      AND name = 'KpiCategoryId' AND is_nullable = 1
)
    ALTER TABLE KPI.CategoryWeight ALTER COLUMN KpiCategoryId INT NOT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_KpiCatWeight_Category')
    ALTER TABLE KPI.CategoryWeight
        ADD CONSTRAINT FK_KpiCatWeight_Category FOREIGN KEY (KpiCategoryId)
            REFERENCES KPI.Category (KpiCategoryId);
GO

IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UX_KpiCatWeight_AccountCategory')
    ALTER TABLE KPI.CategoryWeight
        ADD CONSTRAINT UX_KpiCatWeight_AccountCategory UNIQUE (AccountId, KpiCategoryId);
GO


-- ============================================================
-- 5. Rebuild views to JOIN KPI.Category and surface Code/Name
-- ============================================================
-- Each view that previously selected `d.Category` (text) now JOINs KPI.Category
-- and projects `c.Name AS Category` so existing Dapper queries that select
-- "Category" continue to work. New columns CategoryId + CategoryCode are added
-- alongside for FK-aware code paths.

CREATE OR ALTER VIEW App.vKpiPackageItems
AS
    SELECT
        pi.KpiPackageItemId, pi.KpiPackageId, pi.KpiId,
        d.KPICode  AS KpiCode,
        d.KPIName  AS KpiName,
        d.KpiCategoryId AS CategoryId,
        c.Code     AS CategoryCode,
        c.Name     AS Category,
        d.DataType,
        d.IsActive AS KpiIsActive
    FROM KPI.KpiPackageItem AS pi
    JOIN KPI.Definition     AS d ON d.KPIID         = pi.KpiId
    JOIN KPI.Category       AS c ON c.KpiCategoryId = d.KpiCategoryId;
GO


CREATE OR ALTER VIEW App.vKpiDefinitions
AS
    SELECT
        d.KPIID,
        d.ExternalId,
        d.KPICode,
        d.KPIName,
        d.KPIDescription,
        d.KpiCategoryId AS CategoryId,
        c.Code          AS CategoryCode,
        c.Name          AS Category,
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
        (
            SELECT STRING_AGG(CAST(t.TagId AS NVARCHAR(10)) + ':' + t.TagName, '|')
            FROM KPI.KpiTag  AS kt
            JOIN Dim.Tag     AS t  ON t.TagId = kt.TagId
            WHERE kt.KpiId = d.KPIID
        ) AS TagsRaw
    FROM KPI.Definition AS d
    JOIN KPI.Category   AS c ON c.KpiCategoryId = d.KpiCategoryId
    OUTER APPLY (
        SELECT COUNT(*) AS AssignmentCount
        FROM KPI.Assignment AS a
        WHERE a.KPIID    = d.KPIID
          AND a.IsActive = 1
    ) AS assignments;
GO


CREATE OR ALTER VIEW App.vKpiAssignmentTemplates
AS
    SELECT
        t.AssignmentTemplateID,
        t.ExternalId,
        d.KPICode,
        d.KPIName,
        d.KpiCategoryId AS CategoryId,
        c.Code          AS CategoryCode,
        c.Name          AS Category,
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
    JOIN KPI.Category           AS c    ON c.KpiCategoryId = d.KpiCategoryId
    LEFT JOIN KPI.PeriodSchedule AS sched ON sched.PeriodScheduleID = t.PeriodScheduleID
    JOIN Dim.Account            AS acct ON acct.AccountId = t.AccountId
    LEFT JOIN Dim.OrgUnit       AS ou   ON ou.OrgUnitId = t.OrgUnitId
    LEFT JOIN KPI.KpiPackage    AS pkg  ON pkg.KpiPackageId = t.KpiPackageId
    OUTER APPLY (
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


CREATE OR ALTER VIEW App.vKpiAssignments
AS
    SELECT
        a.AssignmentID,
        a.ExternalId,
        a.KPIID,
        d.KPICode,
        d.KPIName,
        d.KpiCategoryId AS CategoryId,
        c.Code          AS CategoryCode,
        c.Name          AS Category,
        d.DataType,
        d.CollectionType,
        a.AccountId,
        acct.AccountCode,
        acct.AccountName,
        a.OrgUnitId,
        ou.OrgUnitCode AS SiteCode,
        ou.OrgUnitName AS SiteName,
        ou.CountryCode,
        CASE WHEN a.OrgUnitId IS NULL THEN 1 ELSE 0 END AS IsAccountWide,
        a.PeriodID,
        p.PeriodScheduleID,
        sched.ScheduleName,
        p.PeriodLabel,
        p.PeriodYear,
        p.PeriodMonth,
        p.Status AS PeriodStatus,
        a.IsRequired,
        a.TargetValue,
        a.ThresholdGreen,
        a.ThresholdAmber,
        a.ThresholdRed,
        COALESCE(a.ThresholdDirection, d.ThresholdDirection) AS EffectiveThresholdDirection,
        a.SubmitterGuidance,
        a.AssignmentTemplateID,
        COALESCE(tmpl.CustomKpiName,        d.KPIName)        AS EffectiveKpiName,
        COALESCE(tmpl.CustomKpiDescription, d.KPIDescription) AS EffectiveKpiDescription,
        a.IsActive,
        a.CreatedOnUtc,
        a.ModifiedOnUtc,
        ISNULL(esc.ContactCount, 0) AS EscalationContactCount,
        a.AssignmentGroupName
    FROM KPI.Assignment AS a
    JOIN KPI.Definition              AS d     ON d.KPIID         = a.KPIID
    JOIN KPI.Category                AS c     ON c.KpiCategoryId = d.KpiCategoryId
    JOIN Dim.Account                 AS acct  ON acct.AccountId  = a.AccountId
    JOIN KPI.Period                  AS p     ON p.PeriodID      = a.PeriodID
    LEFT JOIN KPI.PeriodSchedule     AS sched ON sched.PeriodScheduleID = p.PeriodScheduleID
    LEFT JOIN Dim.OrgUnit            AS ou    ON ou.OrgUnitId    = a.OrgUnitId
    LEFT JOIN KPI.AssignmentTemplate AS tmpl  ON tmpl.AssignmentTemplateID = a.AssignmentTemplateID
    OUTER APPLY (
        SELECT COUNT(*) AS ContactCount
        FROM KPI.EscalationContact AS ec
        WHERE ec.OrgUnitId = a.OrgUnitId
          AND ec.PeriodID  = a.PeriodID
          AND ec.IsActive  = 1
    ) AS esc;
GO


CREATE OR ALTER VIEW App.vEffectiveKpiAssignments
AS
    SELECT
        a.AssignmentID,
        a.ExternalId,
        a.KPIID,
        d.KPICode,
        d.KPIName,
        d.KpiCategoryId AS CategoryId,
        c.Code          AS CategoryCode,
        c.Name          AS Category,
        d.DataType,
        d.CollectionType,
        a.AccountId,
        acct.AccountCode,
        acct.AccountName,
        ou.OrgUnitId,
        ou.OrgUnitCode  AS SiteCode,
        ou.OrgUnitName  AS SiteName,
        ou.CountryCode,
        CAST(0 AS BIT)  AS IsAccountWide,
        a.PeriodID,
        p.PeriodScheduleID,
        p.PeriodLabel,
        p.PeriodYear,
        p.PeriodMonth,
        p.Status AS PeriodStatus,
        a.IsRequired,
        a.TargetValue,
        a.ThresholdGreen,
        a.ThresholdAmber,
        a.ThresholdRed,
        COALESCE(a.ThresholdDirection, d.ThresholdDirection) AS EffectiveThresholdDirection,
        a.SubmitterGuidance,
        a.AssignmentTemplateID,
        COALESCE(tmpl.CustomKpiName,        d.KPIName)        AS EffectiveKpiName,
        COALESCE(tmpl.CustomKpiDescription, d.KPIDescription) AS EffectiveKpiDescription,
        a.IsActive,
        a.CreatedOnUtc,
        a.ModifiedOnUtc
    FROM KPI.Assignment              AS a
    JOIN KPI.Definition              AS d    ON d.KPIID         = a.KPIID
    JOIN KPI.Category                AS c    ON c.KpiCategoryId = d.KpiCategoryId
    JOIN Dim.Account                 AS acct ON acct.AccountId  = a.AccountId
    JOIN KPI.Period                  AS p    ON p.PeriodID      = a.PeriodID
    JOIN Dim.OrgUnit                 AS ou   ON ou.OrgUnitId    = a.OrgUnitId
    LEFT JOIN KPI.AssignmentTemplate AS tmpl ON tmpl.AssignmentTemplateID = a.AssignmentTemplateID
    WHERE a.OrgUnitId IS NOT NULL

    UNION ALL

    SELECT
        a.AssignmentID,
        a.ExternalId,
        a.KPIID,
        d.KPICode,
        d.KPIName,
        d.KpiCategoryId AS CategoryId,
        c.Code          AS CategoryCode,
        c.Name          AS Category,
        d.DataType,
        d.CollectionType,
        a.AccountId,
        acct.AccountCode,
        acct.AccountName,
        site.OrgUnitId,
        site.OrgUnitCode  AS SiteCode,
        site.OrgUnitName  AS SiteName,
        site.CountryCode,
        CAST(1 AS BIT)    AS IsAccountWide,
        a.PeriodID,
        p.PeriodScheduleID,
        p.PeriodLabel,
        p.PeriodYear,
        p.PeriodMonth,
        p.Status AS PeriodStatus,
        a.IsRequired,
        a.TargetValue,
        a.ThresholdGreen,
        a.ThresholdAmber,
        a.ThresholdRed,
        COALESCE(a.ThresholdDirection, d.ThresholdDirection) AS EffectiveThresholdDirection,
        a.SubmitterGuidance,
        a.AssignmentTemplateID,
        COALESCE(tmpl.CustomKpiName,        d.KPIName)        AS EffectiveKpiName,
        COALESCE(tmpl.CustomKpiDescription, d.KPIDescription) AS EffectiveKpiDescription,
        a.IsActive,
        a.CreatedOnUtc,
        a.ModifiedOnUtc
    FROM KPI.Assignment              AS a
    JOIN KPI.Definition              AS d    ON d.KPIID         = a.KPIID
    JOIN KPI.Category                AS c    ON c.KpiCategoryId = d.KpiCategoryId
    JOIN Dim.Account                 AS acct ON acct.AccountId  = a.AccountId
    JOIN KPI.Period                  AS p    ON p.PeriodID      = a.PeriodID
    JOIN Dim.OrgUnit                 AS site
        ON  site.AccountId   = a.AccountId
        AND site.OrgUnitType = 'Site'
        AND site.IsActive    = 1
    LEFT JOIN KPI.AssignmentTemplate AS tmpl ON tmpl.AssignmentTemplateID = a.AssignmentTemplateID
    WHERE a.OrgUnitId IS NULL
      AND NOT EXISTS (
            SELECT 1
            FROM   KPI.Assignment AS sa
            WHERE  sa.KPIID     = a.KPIID
              AND  sa.OrgUnitId = site.OrgUnitId
              AND  sa.PeriodID  = a.PeriodID
              AND  sa.IsActive  = 1
      );
GO


CREATE OR ALTER VIEW App.vKpiSubmissions
AS
    SELECT
        sub.SubmissionID,
        sub.ExternalId,
        sub.AssignmentID,
        d.KPICode,
        d.KPIName,
        d.KpiCategoryId AS CategoryId,
        c.Code          AS CategoryCode,
        c.Name          AS Category,
        d.DataType,
        d.Unit,
        p.PeriodLabel,
        p.PeriodYear,
        p.PeriodMonth,
        p.Status AS PeriodStatus,
        site.OrgUnitId   AS SiteOrgUnitId,
        site.OrgUnitCode AS SiteCode,
        site.OrgUnitName AS SiteName,
        site.CountryCode,
        acct.AccountCode,
        acct.AccountName,
        COALESCE(sub.SubmittedTargetValue,    a.TargetValue)    AS TargetValue,
        COALESCE(sub.SubmittedThresholdGreen, a.ThresholdGreen) AS ThresholdGreen,
        COALESCE(sub.SubmittedThresholdAmber, a.ThresholdAmber) AS ThresholdAmber,
        COALESCE(sub.SubmittedThresholdRed,   a.ThresholdRed)   AS ThresholdRed,
        COALESCE(sub.SubmittedThresholdDirection, a.ThresholdDirection, d.ThresholdDirection) AS EffectiveThresholdDirection,
        sub.SubmissionValue,
        sub.SubmissionText,
        sub.SubmissionBoolean,
        sub.SubmissionNotes,
        sub.SourceType,
        submitter.UPN AS SubmittedByUPN,
        sub.SubmittedAt,
        sub.LockState,
        sub.LockedAt,
        locker.UPN AS LockedByUPN,
        sub.IsValid,
        sub.ValidationNotes,
        CASE
            WHEN d.DataType NOT IN ('Numeric','Percentage','Currency','Time') THEN NULL
            WHEN sub.SubmissionValue IS NULL                                  THEN NULL
            WHEN COALESCE(sub.SubmittedThresholdGreen, a.ThresholdGreen) IS NULL THEN NULL
            WHEN COALESCE(sub.SubmittedThresholdDirection, a.ThresholdDirection, d.ThresholdDirection) = 'Higher'
            THEN
                CASE
                    WHEN sub.SubmissionValue >= COALESCE(sub.SubmittedThresholdGreen, a.ThresholdGreen) THEN 'Green'
                    WHEN sub.SubmissionValue >= COALESCE(sub.SubmittedThresholdAmber, a.ThresholdAmber) THEN 'Amber'
                    ELSE 'Red'
                END
            WHEN COALESCE(sub.SubmittedThresholdDirection, a.ThresholdDirection, d.ThresholdDirection) = 'Lower'
            THEN
                CASE
                    WHEN sub.SubmissionValue <= COALESCE(sub.SubmittedThresholdGreen, a.ThresholdGreen) THEN 'Green'
                    WHEN sub.SubmissionValue <= COALESCE(sub.SubmittedThresholdAmber, a.ThresholdAmber) THEN 'Amber'
                    ELSE 'Red'
                END
            ELSE NULL
        END AS RAGStatus,
        sub.CreatedOnUtc,
        sub.ModifiedOnUtc
    FROM KPI.Submission AS sub
    JOIN KPI.Assignment AS a    ON a.AssignmentID    = sub.AssignmentID
    JOIN KPI.Definition AS d    ON d.KPIID           = a.KPIID
    JOIN KPI.Category   AS c    ON c.KpiCategoryId   = d.KpiCategoryId
    JOIN KPI.Period     AS p    ON p.PeriodID        = a.PeriodID
    JOIN Dim.OrgUnit    AS site ON site.OrgUnitId    = a.OrgUnitId
    JOIN Dim.Account    AS acct ON acct.AccountId    = a.AccountId
    LEFT JOIN Sec.[User] AS submitter ON submitter.UserId = sub.SubmittedByPrincipalId
    LEFT JOIN Sec.[User] AS locker    ON locker.UserId    = sub.LockedByPrincipalId;
GO


-- vKpiSubmissionScores: same shape as previous version but JOIN through KPI.Category.
-- The score CASE expression below is intentionally unchanged from
-- KpiScoringCategoryWeightTemplate.Up.sql.
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
    d.KpiCategoryId AS CategoryId,
    c.Code          AS CategoryCode,
    c.Name          AS Category,
    d.DataType,
    COALESCE(sub.SubmittedKpiWeight,            a.KpiWeight)              AS KpiWeight,
    COALESCE(sub.SubmittedPenaliseMissingOnScore, a.PenaliseMissingOnScore) AS PenaliseMissingOnScore,
    COALESCE(a.CategoryWeightSnapshot, 1.0)                                AS CategoryWeight,
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
JOIN KPI.Definition AS d ON d.KPIID         = a.KPIID
JOIN KPI.Category   AS c ON c.KpiCategoryId = d.KpiCategoryId
LEFT JOIN KPI.Submission AS sub ON sub.AssignmentID = a.AssignmentID
OUTER APPLY (
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
                (SELECT TOP 1 ISNULL(p.points, 0)
                 FROM OPENJSON(COALESCE(sub.SubmittedDropDownOptionPoints, '[]'))
                    WITH (value NVARCHAR(200) '$.value', points DECIMAL(9,4) '$.points') AS p
                 WHERE p.value = sub.SubmissionText)
        END AS Points
) AS dd
OUTER APPLY (
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
        d.KpiCategoryId                                         AS CategoryId,
        c.Code                                                  AS CategoryCode,
        c.Name                                                  AS Category,
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
       AND (
             (st.AssignmentGroupName IS NULL AND asgn.AssignmentGroupName IS NULL)
             OR asgn.AssignmentGroupName = st.AssignmentGroupName
           )
    JOIN KPI.Definition              AS d ON d.KPIID         = asgn.KPIID
    JOIN KPI.Category                AS c ON c.KpiCategoryId = d.KpiCategoryId
    LEFT JOIN KPI.AssignmentTemplate AS t ON t.AssignmentTemplateID = asgn.AssignmentTemplateID
    LEFT JOIN KPI.Submission         AS sub ON sub.AssignmentID = asgn.AssignmentID;
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
        d.KpiCategoryId                                          AS CategoryId,
        c.Code                                                   AS CategoryCode,
        c.Name                                                   AS Category,
        d.DataType,
        CAST(asgn.IsRequired AS bit)                             AS IsRequired,
        COALESCE(sub.SubmittedTargetValue,        asgn.TargetValue)    AS TargetValue,
        COALESCE(sub.SubmittedThresholdGreen,     asgn.ThresholdGreen) AS ThresholdGreen,
        COALESCE(sub.SubmittedThresholdAmber,     asgn.ThresholdAmber) AS ThresholdAmber,
        COALESCE(sub.SubmittedThresholdRed,       asgn.ThresholdRed)   AS ThresholdRed,
        COALESCE(sub.SubmittedThresholdDirection, asgn.ThresholdDirection, d.ThresholdDirection) AS EffectiveThresholdDirection,
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
            WHEN d.DataType NOT IN ('Numeric','Percentage','Currency','Time') THEN NULL
            WHEN sub.SubmissionValue IS NULL                                  THEN NULL
            WHEN COALESCE(sub.SubmittedThresholdGreen, asgn.ThresholdGreen) IS NULL THEN NULL
            WHEN COALESCE(sub.SubmittedThresholdDirection, asgn.ThresholdDirection, d.ThresholdDirection) = 'Higher'
            THEN CASE
                WHEN sub.SubmissionValue >= COALESCE(sub.SubmittedThresholdGreen, asgn.ThresholdGreen) THEN 'Green'
                WHEN sub.SubmissionValue >= COALESCE(sub.SubmittedThresholdAmber, asgn.ThresholdAmber) THEN 'Amber'
                ELSE 'Red'
            END
            WHEN COALESCE(sub.SubmittedThresholdDirection, asgn.ThresholdDirection, d.ThresholdDirection) = 'Lower'
            THEN CASE
                WHEN sub.SubmissionValue <= COALESCE(sub.SubmittedThresholdGreen, asgn.ThresholdGreen) THEN 'Green'
                WHEN sub.SubmissionValue <= COALESCE(sub.SubmittedThresholdAmber, asgn.ThresholdAmber) THEN 'Amber'
                ELSE 'Red'
            END
            ELSE NULL
        END                                                      AS RagStatus,
        asgn.AssignmentGroupName
    FROM KPI.Assignment AS asgn
    JOIN KPI.Definition              AS d ON d.KPIID         = asgn.KPIID
    JOIN KPI.Category                AS c ON c.KpiCategoryId = d.KpiCategoryId
    LEFT JOIN KPI.AssignmentTemplate AS t ON t.AssignmentTemplateID = asgn.AssignmentTemplateID
    LEFT JOIN KPI.Submission         AS sub ON sub.AssignmentID = asgn.AssignmentID
    LEFT JOIN Sec.[User]             AS u   ON u.UserId        = sub.SubmittedByPrincipalId
    WHERE asgn.OrgUnitId IS NOT NULL
      AND asgn.IsActive  = 1;
GO


CREATE OR ALTER VIEW App.vSiteCompositeScore
AS
WITH per_category AS (
    SELECT
        s.AccountId,
        s.SiteOrgUnitId,
        s.PeriodID,
        s.CategoryId,
        s.CategoryCode,
        s.Category,
        AVG(s.CategoryWeight) AS CategoryWeight,
        SUM(CASE WHEN s.Score IS NULL THEN 0 ELSE s.Score * s.KpiWeight END) AS WeightedScore,
        SUM(CASE WHEN s.Score IS NULL THEN 0 ELSE s.KpiWeight END)           AS WeightSum,
        SUM(CASE WHEN s.Score IS NOT NULL THEN 1 ELSE 0 END)                  AS ScoredCount,
        COUNT(*)                                                              AS TotalCount
    FROM App.vKpiSubmissionScores AS s
    WHERE s.SiteOrgUnitId IS NOT NULL
    GROUP BY s.AccountId, s.SiteOrgUnitId, s.PeriodID, s.CategoryId, s.CategoryCode, s.Category
),
weighted AS (
    SELECT
        pc.AccountId, pc.SiteOrgUnitId, pc.PeriodID,
        pc.CategoryId, pc.CategoryCode, pc.Category,
        pc.ScoredCount, pc.TotalCount,
        CASE WHEN pc.WeightSum = 0 THEN NULL
             ELSE pc.WeightedScore / pc.WeightSum
        END                                AS CategoryScore,
        pc.CategoryWeight                  AS CategoryWeight,
        CAST(1 AS BIT)                     AS CategoryActive
    FROM per_category AS pc
)
SELECT
    w.AccountId,
    w.SiteOrgUnitId,
    w.PeriodID,
    w.CategoryId,
    w.CategoryCode,
    w.Category,
    w.CategoryScore,
    w.CategoryWeight,
    w.CategoryActive,
    w.ScoredCount,
    w.TotalCount,
    SUM(CASE WHEN w.CategoryScore IS NULL
             THEN 0 ELSE w.CategoryScore * w.CategoryWeight END)
        OVER (PARTITION BY w.AccountId, w.SiteOrgUnitId, w.PeriodID)
    /
    NULLIF(SUM(CASE WHEN w.CategoryScore IS NULL
                    THEN 0 ELSE w.CategoryWeight END)
        OVER (PARTITION BY w.AccountId, w.SiteOrgUnitId, w.PeriodID), 0)
        AS CompositeScore
FROM weighted AS w;
GO


CREATE OR ALTER VIEW Reporting.vw_PBIKPIDefinition
AS
    SELECT
        d.KPIID,
        d.ExternalId            AS KPIDefinitionKey,
        d.KPICode,
        d.KPIName,
        d.KPIDescription,
        d.KpiCategoryId         AS KPICategoryId,
        c.Code                  AS KPICategoryCode,
        c.Name                  AS KPICategory,
        d.Unit                  AS KPIUnit,
        d.DataType,
        d.CollectionType,
        d.ThresholdDirection    AS DefaultThresholdDirection,
        d.IsActive
    FROM KPI.Definition AS d
    JOIN KPI.Category   AS c ON c.KpiCategoryId = d.KpiCategoryId
    WHERE d.IsActive = 1;
GO


CREATE OR ALTER VIEW Reporting.vw_PBIAssignment
AS
    SELECT
        asgn.AssignmentID,
        asgn.ExternalId                                         AS AssignmentKey,
        d.ExternalId                                            AS KPIDefinitionKey,
        d.KPICode,
        COALESCE(tmpl.CustomKpiName, d.KPIName)                 AS KPIName,
        d.KPIName                                               AS LibraryKPIName,
        d.KpiCategoryId                                         AS KPICategoryId,
        c.Code                                                  AS KPICategoryCode,
        c.Name                                                  AS KPICategory,
        d.Unit                                                  AS KPIUnit,
        d.DataType,
        d.CollectionType,
        per.ExternalId                                          AS PeriodKey,
        per.PeriodLabel,
        per.PeriodYear,
        per.PeriodMonth,
        per.Status                                              AS PeriodStatus,
        per.PeriodScheduleID,
        ps.ScheduleName,
        asgn.AccountId,
        acct.AccountCode,
        acct.AccountName,
        asgn.OrgUnitId                                          AS SiteId,
        ou.OrgUnitCode                                          AS SiteCode,
        ou.OrgUnitName                                          AS SiteName,
        CAST(CASE WHEN asgn.OrgUnitId IS NULL THEN 1 ELSE 0 END AS BIT) AS IsAccountWide,
        asgn.IsRequired,
        asgn.TargetValue,
        asgn.ThresholdGreen,
        asgn.ThresholdAmber,
        asgn.ThresholdRed,
        COALESCE(asgn.ThresholdDirection, d.ThresholdDirection) AS EffectiveThresholdDirection,
        asgn.SubmitterGuidance
    FROM KPI.Assignment              AS asgn
    JOIN KPI.Definition              AS d    ON d.KPIID              = asgn.KPIID
    JOIN KPI.Category                AS c    ON c.KpiCategoryId      = d.KpiCategoryId
    JOIN KPI.Period                  AS per  ON per.PeriodID         = asgn.PeriodID
    JOIN KPI.PeriodSchedule          AS ps   ON ps.PeriodScheduleID  = per.PeriodScheduleID
    JOIN Dim.Account                 AS acct ON acct.AccountId       = asgn.AccountId
    LEFT JOIN Dim.OrgUnit            AS ou   ON ou.OrgUnitId         = asgn.OrgUnitId
    LEFT JOIN KPI.AssignmentTemplate AS tmpl ON tmpl.AssignmentTemplateID = asgn.AssignmentTemplateID
    WHERE asgn.IsActive = 1;
GO


CREATE OR ALTER VIEW Reporting.vw_PBIKPIFact
AS
    SELECT
        s.ExternalId                                            AS SubmissionKey,
        asgn.ExternalId                                         AS AssignmentKey,
        d.ExternalId                                            AS KPIDefinitionKey,
        per.ExternalId                                          AS PeriodKey,
        per.PeriodLabel,
        per.PeriodYear,
        per.PeriodMonth,
        per.PeriodYear * 100 + per.PeriodMonth                  AS PeriodSortKey,
        per.Status                                              AS PeriodStatus,
        d.KPICode,
        COALESCE(tmpl.CustomKpiName, d.KPIName)                 AS KPIName,
        d.KpiCategoryId                                         AS KPICategoryId,
        c.Code                                                  AS KPICategoryCode,
        c.Name                                                  AS KPICategory,
        d.Unit                                                  AS KPIUnit,
        d.DataType,
        d.CollectionType,
        per.PeriodScheduleID,
        ps.ScheduleName,
        asgn.AccountId,
        acct.AccountCode,
        acct.AccountName,
        asgn.OrgUnitId                                          AS SiteId,
        ou.OrgUnitCode                                          AS SiteCode,
        ou.OrgUnitName                                          AS SiteName,
        CAST(CASE WHEN asgn.OrgUnitId IS NULL THEN 1 ELSE 0 END AS BIT) AS IsAccountWide,
        asgn.IsRequired,
        COALESCE(s.SubmittedTargetValue,        asgn.TargetValue)    AS TargetValue,
        COALESCE(s.SubmittedThresholdGreen,     asgn.ThresholdGreen) AS ThresholdGreen,
        COALESCE(s.SubmittedThresholdAmber,     asgn.ThresholdAmber) AS ThresholdAmber,
        COALESCE(s.SubmittedThresholdRed,       asgn.ThresholdRed)   AS ThresholdRed,
        COALESCE(s.SubmittedThresholdDirection, asgn.ThresholdDirection, d.ThresholdDirection) AS EffectiveThresholdDirection,
        s.SubmissionValue,
        s.SubmissionText,
        s.SubmissionNotes,
        s.SourceType,
        s.LockState,
        s.SubmittedAt,
        s.IsValid,
        s.ValidationNotes,
        s.CreatedOnUtc                                          AS SubmissionCreatedAt,
        CASE
            WHEN s.SubmissionValue IS NULL
                THEN 'NoData'
            WHEN COALESCE(s.SubmittedThresholdGreen, asgn.ThresholdGreen) IS NULL
                THEN 'NoThreshold'
            WHEN COALESCE(s.SubmittedThresholdDirection, asgn.ThresholdDirection, d.ThresholdDirection) = 'Higher'
                THEN CASE
                    WHEN s.SubmissionValue >= COALESCE(s.SubmittedThresholdGreen, asgn.ThresholdGreen)                                                                        THEN 'Green'
                    WHEN COALESCE(s.SubmittedThresholdAmber, asgn.ThresholdAmber) IS NOT NULL AND s.SubmissionValue >= COALESCE(s.SubmittedThresholdAmber, asgn.ThresholdAmber) THEN 'Amber'
                    ELSE 'Red'
                END
            WHEN COALESCE(s.SubmittedThresholdDirection, asgn.ThresholdDirection, d.ThresholdDirection) = 'Lower'
                THEN CASE
                    WHEN s.SubmissionValue <= COALESCE(s.SubmittedThresholdGreen, asgn.ThresholdGreen)                                                                        THEN 'Green'
                    WHEN COALESCE(s.SubmittedThresholdAmber, asgn.ThresholdAmber) IS NOT NULL AND s.SubmissionValue <= COALESCE(s.SubmittedThresholdAmber, asgn.ThresholdAmber) THEN 'Amber'
                    ELSE 'Red'
                END
            ELSE 'NoThreshold'
        END AS RAGStatus,
        CASE
            WHEN s.SubmissionValue IS NULL
                THEN 4
            WHEN COALESCE(s.SubmittedThresholdGreen, asgn.ThresholdGreen) IS NULL
                THEN 5
            WHEN COALESCE(s.SubmittedThresholdDirection, asgn.ThresholdDirection, d.ThresholdDirection) = 'Higher'
                THEN CASE
                    WHEN s.SubmissionValue >= COALESCE(s.SubmittedThresholdGreen, asgn.ThresholdGreen)                                                                        THEN 3
                    WHEN COALESCE(s.SubmittedThresholdAmber, asgn.ThresholdAmber) IS NOT NULL AND s.SubmissionValue >= COALESCE(s.SubmittedThresholdAmber, asgn.ThresholdAmber) THEN 2
                    ELSE 1
                END
            WHEN COALESCE(s.SubmittedThresholdDirection, asgn.ThresholdDirection, d.ThresholdDirection) = 'Lower'
                THEN CASE
                    WHEN s.SubmissionValue <= COALESCE(s.SubmittedThresholdGreen, asgn.ThresholdGreen)                                                                        THEN 3
                    WHEN COALESCE(s.SubmittedThresholdAmber, asgn.ThresholdAmber) IS NOT NULL AND s.SubmissionValue <= COALESCE(s.SubmittedThresholdAmber, asgn.ThresholdAmber) THEN 2
                    ELSE 1
                END
            ELSE 5
        END AS RAGSortOrder
    FROM KPI.Submission              AS s
    JOIN KPI.Assignment              AS asgn ON asgn.AssignmentID      = s.AssignmentID
                                            AND asgn.IsActive          = 1
    JOIN KPI.Definition              AS d    ON d.KPIID                = asgn.KPIID
    JOIN KPI.Category                AS c    ON c.KpiCategoryId        = d.KpiCategoryId
    JOIN KPI.Period                  AS per  ON per.PeriodID           = asgn.PeriodID
    JOIN KPI.PeriodSchedule          AS ps   ON ps.PeriodScheduleID    = per.PeriodScheduleID
    JOIN Dim.Account                 AS acct ON acct.AccountId         = asgn.AccountId
    LEFT JOIN Dim.OrgUnit            AS ou   ON ou.OrgUnitId           = asgn.OrgUnitId
    LEFT JOIN KPI.AssignmentTemplate AS tmpl ON tmpl.AssignmentTemplateID = asgn.AssignmentTemplateID;
GO


CREATE OR ALTER VIEW Reporting.vw_PBIAssignmentStatus
AS
    SELECT
        asgn.ExternalId                                         AS AssignmentKey,
        d.ExternalId                                            AS KPIDefinitionKey,
        per.ExternalId                                          AS PeriodKey,
        per.PeriodLabel,
        per.PeriodYear,
        per.PeriodMonth,
        per.PeriodYear * 100 + per.PeriodMonth                  AS PeriodSortKey,
        per.Status                                              AS PeriodStatus,
        d.KPICode,
        COALESCE(tmpl.CustomKpiName, d.KPIName)                 AS KPIName,
        d.KpiCategoryId                                         AS KPICategoryId,
        c.Code                                                  AS KPICategoryCode,
        c.Name                                                  AS KPICategory,
        d.Unit                                                  AS KPIUnit,
        d.DataType,
        d.CollectionType,
        per.PeriodScheduleID,
        ps.ScheduleName,
        asgn.AccountId,
        acct.AccountCode,
        acct.AccountName,
        asgn.OrgUnitId                                          AS SiteId,
        ou.OrgUnitCode                                          AS SiteCode,
        ou.OrgUnitName                                          AS SiteName,
        CAST(CASE WHEN asgn.OrgUnitId IS NULL THEN 1 ELSE 0 END AS BIT) AS IsAccountWide,
        asgn.IsRequired,
        COALESCE(s.SubmittedTargetValue,        asgn.TargetValue)    AS TargetValue,
        COALESCE(s.SubmittedThresholdGreen,     asgn.ThresholdGreen) AS ThresholdGreen,
        COALESCE(s.SubmittedThresholdAmber,     asgn.ThresholdAmber) AS ThresholdAmber,
        COALESCE(s.SubmittedThresholdRed,       asgn.ThresholdRed)   AS ThresholdRed,
        COALESCE(s.SubmittedThresholdDirection, asgn.ThresholdDirection, d.ThresholdDirection) AS EffectiveThresholdDirection,
        s.ExternalId                                            AS SubmissionKey,
        s.SubmissionValue,
        s.SubmissionText,
        s.SourceType,
        s.LockState,
        s.SubmittedAt,
        s.IsValid,
        CAST(CASE WHEN s.SubmissionID IS NOT NULL THEN 1 ELSE 0 END AS BIT)             AS IsSubmitted,
        CAST(CASE WHEN s.LockState NOT IN ('Unlocked') AND s.SubmissionID IS NOT NULL
                  THEN 1 ELSE 0 END AS BIT)                                             AS IsLocked,
        CASE
            WHEN s.SubmissionValue IS NULL
                THEN 'NoData'
            WHEN COALESCE(s.SubmittedThresholdGreen, asgn.ThresholdGreen) IS NULL
                THEN 'NoThreshold'
            WHEN COALESCE(s.SubmittedThresholdDirection, asgn.ThresholdDirection, d.ThresholdDirection) = 'Higher'
                THEN CASE
                    WHEN s.SubmissionValue >= COALESCE(s.SubmittedThresholdGreen, asgn.ThresholdGreen)                                                                        THEN 'Green'
                    WHEN COALESCE(s.SubmittedThresholdAmber, asgn.ThresholdAmber) IS NOT NULL AND s.SubmissionValue >= COALESCE(s.SubmittedThresholdAmber, asgn.ThresholdAmber) THEN 'Amber'
                    ELSE 'Red'
                END
            WHEN COALESCE(s.SubmittedThresholdDirection, asgn.ThresholdDirection, d.ThresholdDirection) = 'Lower'
                THEN CASE
                    WHEN s.SubmissionValue <= COALESCE(s.SubmittedThresholdGreen, asgn.ThresholdGreen)                                                                        THEN 'Green'
                    WHEN COALESCE(s.SubmittedThresholdAmber, asgn.ThresholdAmber) IS NOT NULL AND s.SubmissionValue <= COALESCE(s.SubmittedThresholdAmber, asgn.ThresholdAmber) THEN 'Amber'
                    ELSE 'Red'
                END
            ELSE 'NoThreshold'
        END AS RAGStatus
    FROM KPI.Assignment              AS asgn
    JOIN KPI.Definition              AS d    ON d.KPIID                = asgn.KPIID
    JOIN KPI.Category                AS c    ON c.KpiCategoryId        = d.KpiCategoryId
    JOIN KPI.Period                  AS per  ON per.PeriodID           = asgn.PeriodID
    JOIN KPI.PeriodSchedule          AS ps   ON ps.PeriodScheduleID    = per.PeriodScheduleID
    JOIN Dim.Account                 AS acct ON acct.AccountId         = asgn.AccountId
    LEFT JOIN Dim.OrgUnit            AS ou   ON ou.OrgUnitId           = asgn.OrgUnitId
    LEFT JOIN KPI.AssignmentTemplate AS tmpl ON tmpl.AssignmentTemplateID = asgn.AssignmentTemplateID
    LEFT JOIN KPI.Submission         AS s    ON s.AssignmentID         = asgn.AssignmentID
    WHERE asgn.IsActive = 1;
GO


-- ============================================================
-- 6. Rebuild stored procs that referenced d.Category / cw.Category
-- ============================================================

-- ─── usp_UpsertKpiDefinition: takes @KpiCategoryId, auto-generates KPICode ─
CREATE OR ALTER PROCEDURE App.usp_UpsertKpiDefinition
    @KPICode                NVARCHAR(50)   = NULL,   -- NULL/empty on INSERT triggers auto-gen
    @KPIName                NVARCHAR(200),
    @KPIDescription         NVARCHAR(1000) = NULL,
    @KpiCategoryId          INT,                      -- required FK to KPI.Category
    @Unit                   NVARCHAR(50)   = NULL,
    @DataType               NVARCHAR(20)   = 'Numeric',
    @AllowMultiValue        BIT            = 0,
    @CollectionType         NVARCHAR(20)   = 'Manual',
    @ThresholdDirection     NVARCHAR(10)   = NULL,
    @SourceSystemRef        NVARCHAR(200)  = NULL,
    @IsActive               BIT            = 1,
    @DropDownOptionsPipe    NVARCHAR(MAX)  = NULL,
    @ActorUPN               NVARCHAR(320)  = NULL,
    @KPIID                  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM KPI.Category WHERE KpiCategoryId = @KpiCategoryId)
        THROW 50300, 'KpiCategoryId not found.', 1;

    -- Look up by code only when one was supplied; empty/NULL means INSERT path with auto-gen.
    SET @KPIID = CASE
        WHEN @KPICode IS NULL OR LTRIM(RTRIM(@KPICode)) = '' THEN NULL
        ELSE (SELECT KPIID FROM KPI.Definition WHERE KPICode = @KPICode)
    END;

    IF @KPIID IS NULL
    BEGIN
        -- Auto-generate {CategoryCode}-NNN when caller didn't supply a code.
        IF @KPICode IS NULL OR LTRIM(RTRIM(@KPICode)) = ''
        BEGIN
            DECLARE @CatCode NVARCHAR(20) =
                (SELECT Code FROM KPI.Category WHERE KpiCategoryId = @KpiCategoryId);

            -- Find max numeric suffix used so far for this category prefix.
            DECLARE @Prefix NVARCHAR(25) = @CatCode + '-';
            DECLARE @MaxN INT = ISNULL((
                SELECT MAX(TRY_CAST(SUBSTRING(KPICode, LEN(@Prefix) + 1, 10) AS INT))
                FROM KPI.Definition
                WHERE KPICode LIKE @Prefix + '%'
                  AND TRY_CAST(SUBSTRING(KPICode, LEN(@Prefix) + 1, 10) AS INT) IS NOT NULL
            ), 0);

            DECLARE @NextN INT = @MaxN + 1;
            SET @KPICode = @Prefix +
                CASE WHEN @NextN < 1000
                     THEN RIGHT('000' + CAST(@NextN AS NVARCHAR(4)), 3)
                     ELSE CAST(@NextN AS NVARCHAR(10))
                END;
        END
        ELSE
        BEGIN
            -- Caller supplied an explicit code: normalise to upper.
            SET @KPICode = UPPER(@KPICode);
        END

        INSERT INTO KPI.Definition
            (KPICode, KPIName, KPIDescription, KpiCategoryId, Unit,
             DataType, AllowMultiValue, CollectionType, ThresholdDirection, SourceSystemRef, IsActive)
        VALUES
            (@KPICode, @KPIName, @KPIDescription, @KpiCategoryId, @Unit,
             @DataType, @AllowMultiValue, @CollectionType, @ThresholdDirection, @SourceSystemRef, @IsActive);

        SET @KPIID = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        -- KPICode is immutable on UPDATE; only category and other attributes change.
        UPDATE KPI.Definition
        SET KPIName            = @KPIName,
            KPIDescription     = @KPIDescription,
            KpiCategoryId      = @KpiCategoryId,
            Unit               = @Unit,
            DataType           = @DataType,
            AllowMultiValue    = @AllowMultiValue,
            CollectionType     = @CollectionType,
            ThresholdDirection = @ThresholdDirection,
            SourceSystemRef    = @SourceSystemRef,
            IsActive           = @IsActive,
            ModifiedOnUtc      = SYSUTCDATETIME(),
            ModifiedBy         = COALESCE(@ActorUPN, SESSION_USER)
        WHERE KPIID = @KPIID;
    END

    -- Sync drop-down options when provided (NULL = don't touch, '' = clear all)
    IF @DropDownOptionsPipe IS NOT NULL
    BEGIN
        DELETE FROM KPI.DropDownOption WHERE KPIID = @KPIID;

        IF LEN(@DropDownOptionsPipe) > 0
        BEGIN
            INSERT INTO KPI.DropDownOption (KPIID, OptionValue, SortOrder)
            SELECT
                @KPIID,
                LTRIM(RTRIM(value)),
                ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1
            FROM STRING_SPLIT(@DropDownOptionsPipe, '|')
            WHERE LEN(LTRIM(RTRIM(value))) > 0
              AND LTRIM(RTRIM(value)) NOT IN (
                  SELECT OptionValue FROM KPI.DropDownOption WHERE KPIID = @KPIID
              );
        END
    END
END;
GO


-- ─── usp_UpsertCategoryWeights: input keyed by KpiCategoryId ─
-- WeightsJson: [{"kpiCategoryId":1,"weight":1.5,"isActive":true}, ...]
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

    -- Each input row may carry kpiCategoryId (FK) OR categoryCode (resolved here).
    -- Front-end UI sends kpiCategoryId; seed scripts find categoryCode more readable.
    ;WITH input AS (
        SELECT
            COALESCE(
                TRY_CAST(JSON_VALUE(j.[value], '$.kpiCategoryId') AS INT),
                (SELECT KpiCategoryId FROM KPI.Category
                 WHERE Code = UPPER(LTRIM(RTRIM(JSON_VALUE(j.[value], '$.categoryCode')))))
            )                                                                AS KpiCategoryId,
            TRY_CAST(JSON_VALUE(j.[value], '$.weight')        AS DECIMAL(9,4)) AS Weight,
            TRY_CAST(JSON_VALUE(j.[value], '$.isActive')      AS BIT)         AS IsActive
        FROM OPENJSON(@WeightsJson) AS j
    )
    MERGE KPI.CategoryWeight AS tgt
    USING input AS src
       ON tgt.AccountId = @AccountId AND tgt.KpiCategoryId = src.KpiCategoryId
    WHEN MATCHED THEN
        UPDATE SET Weight        = ISNULL(src.Weight, tgt.Weight),
                   IsActive      = ISNULL(src.IsActive, tgt.IsActive),
                   ModifiedOnUtc = SYSUTCDATETIME(),
                   ModifiedBy    = @Actor
    WHEN NOT MATCHED BY TARGET AND src.KpiCategoryId IS NOT NULL THEN
        INSERT (AccountId, KpiCategoryId, Weight, IsActive, CreatedBy, ModifiedBy)
        VALUES (@AccountId, src.KpiCategoryId, ISNULL(src.Weight, 1.0), ISNULL(src.IsActive, 1), @Actor, @Actor);
END;
GO


-- ─── usp_RefreshTemplateCategoryWeights: filter by @KpiCategoryId ─
CREATE OR ALTER PROCEDURE App.usp_RefreshTemplateCategoryWeights
    @AccountCode    NVARCHAR(50),
    @KpiCategoryId  INT            = NULL,
    @ActorUPN       NVARCHAR(320)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @AccountId INT = (SELECT AccountId FROM Dim.Account WHERE AccountCode = @AccountCode AND IsActive = 1);
    IF @AccountId IS NULL
        THROW 50260, 'Account not found or inactive.', 1;

    DECLARE @Actor NVARCHAR(128) = COALESCE(@ActorUPN, SESSION_USER);

    UPDATE t
    SET CategoryWeightSnapshot = ISNULL(cw.Weight, 1.0),
        ModifiedOnUtc          = SYSUTCDATETIME(),
        ModifiedBy             = @Actor
    FROM KPI.AssignmentTemplate  AS t
    JOIN KPI.Definition          AS d  ON d.KPIID = t.KPIID
    LEFT JOIN KPI.CategoryWeight AS cw ON cw.AccountId = t.AccountId AND cw.KpiCategoryId = d.KpiCategoryId
    WHERE t.AccountId = @AccountId
      AND (@KpiCategoryId IS NULL OR d.KpiCategoryId = @KpiCategoryId);

    DECLARE @TemplatesUpdated INT = @@ROWCOUNT;

    DECLARE @TemplateId INT;
    DECLARE @AssignmentsUpdated INT = 0;

    DECLARE template_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT t.AssignmentTemplateID
        FROM KPI.AssignmentTemplate AS t
        JOIN KPI.Definition         AS d ON d.KPIID = t.KPIID
        WHERE t.AccountId = @AccountId
          AND (@KpiCategoryId IS NULL OR d.KpiCategoryId = @KpiCategoryId);

    OPEN template_cursor;
    FETCH NEXT FROM template_cursor INTO @TemplateId;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @CascadeCount INT = (
            SELECT COUNT(*)
            FROM KPI.Assignment AS a
            WHERE a.AssignmentTemplateID = @TemplateId
              AND NOT EXISTS (SELECT 1 FROM KPI.Submission s WHERE s.AssignmentID = a.AssignmentID)
        );

        EXEC App.usp_CascadeAssignmentTemplateThresholds
            @AssignmentTemplateID = @TemplateId,
            @ActorUPN             = @ActorUPN;

        SET @AssignmentsUpdated = @AssignmentsUpdated + @CascadeCount;
        FETCH NEXT FROM template_cursor INTO @TemplateId;
    END

    CLOSE template_cursor;
    DEALLOCATE template_cursor;

    SELECT @TemplatesUpdated AS TemplatesUpdated, @AssignmentsUpdated AS AssignmentsUpdated;
END;
GO


-- ─── usp_AssignKpi: cw join now uses KpiCategoryId ─
-- (Body unchanged except for the cw join and the DefinitionSnapshot's category source.)
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

    IF @CategoryWeightSnapshot IS NULL
    BEGIN
        SELECT @CategoryWeightSnapshot = ISNULL(cw.Weight, 1.0)
        FROM KPI.Definition AS d
        LEFT JOIN KPI.CategoryWeight AS cw
            ON cw.AccountId = @AccountId AND cw.KpiCategoryId = d.KpiCategoryId
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
             CategoryWeightSnapshot)
        VALUES
            (@KPIID, @AccountId, @OrgUnitId, @PeriodID, @AssignmentTemplateID, @IsRequired,
             @TargetValue, @ThresholdGreen, @ThresholdAmber, @ThresholdRed,
             @ThresholdDirection, @SubmitterGuidance, @ActorPrincipalId, @AssignmentGroupName,
             @KpiWeight, @ScoringMode, @BandPointsGreen, @BandPointsAmber, @BandPointsRed,
             @BooleanYesPoints, @BooleanNoPoints, @MultiSelectScoreRule, @PenaliseMissingOnScore,
             @CategoryWeightSnapshot);

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


-- ─── usp_UpsertKpiAssignmentTemplate: cw join uses KpiCategoryId ─
-- (Same body as KpiScoringCategoryWeightTemplate.Up.sql, only the snapshot lookup
-- differs — JOIN on KpiCategoryId instead of Category text.)
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
            ON cw.AccountId = @AccountId AND cw.KpiCategoryId = d.KpiCategoryId
        WHERE d.KPIID = @KPIID;

        INSERT INTO KPI.AssignmentTemplate
            (KPIID, PeriodScheduleID, AccountId, OrgUnitId, StartPeriodYear, StartPeriodMonth, EndPeriodYear, EndPeriodMonth,
             IsRequired, TargetValue, ThresholdGreen, ThresholdAmber, ThresholdRed, ThresholdDirection, SubmitterGuidance,
             CustomKpiName, CustomKpiDescription, KpiPackageId, AssignmentGroupName,
             KpiWeight, ScoringMode, BandPointsGreen, BandPointsAmber, BandPointsRed,
             BooleanYesPoints, BooleanNoPoints, MultiSelectScoreRule, PenaliseMissingOnScore,
             CategoryWeightSnapshot)
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
             COALESCE(@PenaliseMissingOnScore, @IsRequired),
             @SnapCategoryWeight);

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


-- ─── 7. New CRUD procs for KPI.Category ─────────────────────
CREATE OR ALTER PROCEDURE App.usp_UpsertKpiCategory
    @KpiCategoryId INT             = NULL,  -- NULL = INSERT, non-NULL = UPDATE
    @Code          NVARCHAR(20),             -- only used on INSERT; locked on UPDATE
    @Name          NVARCHAR(100),
    @Description   NVARCHAR(500)   = NULL,
    @IsActive      BIT             = 1,
    @ActorUPN      NVARCHAR(320)   = NULL,
    @KpiCategoryIdOut INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Actor NVARCHAR(128) = COALESCE(@ActorUPN, SESSION_USER);
    DECLARE @NormalisedCode NVARCHAR(20) = UPPER(LTRIM(RTRIM(@Code)));

    IF @KpiCategoryId IS NULL
    BEGIN
        -- INSERT
        IF @NormalisedCode IS NULL OR @NormalisedCode = ''
            THROW 50301, 'Category Code is required when creating a new category.', 1;

        IF EXISTS (SELECT 1 FROM KPI.Category WHERE Code = @NormalisedCode)
            THROW 50302, 'A category with this Code already exists.', 1;

        INSERT INTO KPI.Category (Code, Name, Description, IsActive, CreatedBy, ModifiedBy)
        VALUES (@NormalisedCode, @Name, @Description, @IsActive, @Actor, @Actor);

        SET @KpiCategoryIdOut = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        -- UPDATE: Code is immutable.
        IF NOT EXISTS (SELECT 1 FROM KPI.Category WHERE KpiCategoryId = @KpiCategoryId)
            THROW 50303, 'KpiCategoryId not found.', 1;

        UPDATE KPI.Category
        SET Name          = @Name,
            Description   = @Description,
            IsActive      = @IsActive,
            ModifiedOnUtc = SYSUTCDATETIME(),
            ModifiedBy    = @Actor
        WHERE KpiCategoryId = @KpiCategoryId;

        SET @KpiCategoryIdOut = @KpiCategoryId;
    END
END;
GO


CREATE OR ALTER PROCEDURE App.usp_SetKpiCategoryActive
    @KpiCategoryId INT,
    @IsActive      BIT,
    @ActorUPN      NVARCHAR(320) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE KPI.Category
    SET IsActive      = @IsActive,
        ModifiedOnUtc = SYSUTCDATETIME(),
        ModifiedBy    = COALESCE(@ActorUPN, SESSION_USER)
    WHERE KpiCategoryId = @KpiCategoryId;
END;
GO


-- ─── usp_SubmitKpi: DefinitionSnapshot now joins KPI.Category for the name ─
-- Body is identical to the previous version except the snapshot SELECT JOINs
-- KPI.Category and projects c.Name AS Category instead of d.Category.
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

    SELECT @PeriodStatus = Status, @CloseDate = SubmissionCloseDate
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
            d.KpiCategoryId AS CategoryId,
            c.Code          AS CategoryCode,
            c.Name          AS Category,
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
        JOIN KPI.Definition AS d ON d.KPIID         = a.KPIID
        JOIN KPI.Category   AS c ON c.KpiCategoryId = d.KpiCategoryId
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


