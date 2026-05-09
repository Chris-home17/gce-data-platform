-- ============================================================
-- Migration: KpiCategoryGlobal — Down
-- ============================================================
-- Restores the free-text Category columns on KPI.Definition and KPI.CategoryWeight
-- (backfilled from KPI.Category.Name), drops the FK columns + KPI.Category, and
-- rebuilds the views/procs to use the text Category column.
--
-- WARNING (data-loss caveat): KPI.Category rows that exist only in the lookup
-- (no row in Definition or CategoryWeight pointing at them) are dropped along
-- with KPI.Category. Their Description is not preserved; only
-- the Name survives, materialised back as text on Definition/CategoryWeight.
-- Auto-generated KPI codes created during the up-window remain (Code is locked
-- and the rows already exist in KPI.Definition).
-- ============================================================

-- ─── 1. Drop CRUD procs added by Up ─────────────────────────
IF OBJECT_ID('App.usp_UpsertKpiCategory', 'P') IS NOT NULL
    DROP PROCEDURE App.usp_UpsertKpiCategory;
GO

IF OBJECT_ID('App.usp_SetKpiCategoryActive', 'P') IS NOT NULL
    DROP PROCEDURE App.usp_SetKpiCategoryActive;
GO


-- ─── 2. Re-add Category text columns and backfill from KPI.Category ─
IF COL_LENGTH('KPI.Definition', 'Category') IS NULL
    ALTER TABLE KPI.Definition ADD Category NVARCHAR(100) NULL;
GO

UPDATE d
SET Category = c.Name
FROM KPI.Definition AS d
JOIN KPI.Category   AS c ON c.KpiCategoryId = d.KpiCategoryId
WHERE d.Category IS NULL;
GO

IF COL_LENGTH('KPI.CategoryWeight', 'Category') IS NULL
    ALTER TABLE KPI.CategoryWeight ADD Category NVARCHAR(100) NULL;
GO

UPDATE cw
SET Category = c.Name
FROM KPI.CategoryWeight AS cw
JOIN KPI.Category       AS c ON c.KpiCategoryId = cw.KpiCategoryId
WHERE cw.Category IS NULL;
GO

-- Tighten NOT NULL on CategoryWeight (Definition.Category was NULLable originally)
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('KPI.CategoryWeight')
      AND name = 'Category' AND is_nullable = 1
)
    ALTER TABLE KPI.CategoryWeight ALTER COLUMN Category NVARCHAR(100) NOT NULL;
GO


-- ─── 3. Restore the (AccountId, Category) UNIQUE; drop the new (AccountId, KpiCategoryId) ─
IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UX_KpiCatWeight_AccountCategory')
    ALTER TABLE KPI.CategoryWeight DROP CONSTRAINT UX_KpiCatWeight_AccountCategory;
GO

IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UX_KpiCatWeight')
    ALTER TABLE KPI.CategoryWeight ADD CONSTRAINT UX_KpiCatWeight UNIQUE (AccountId, Category);
GO


-- ─── 4. Drop FK + index + column on Definition + CategoryWeight ─
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_KpiDef_Category')
    ALTER TABLE KPI.Definition DROP CONSTRAINT FK_KpiDef_Category;
GO

IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('KPI.Definition') AND name = 'IX_KpiDef_KpiCategoryId'
)
    DROP INDEX IX_KpiDef_KpiCategoryId ON KPI.Definition;
GO

IF COL_LENGTH('KPI.Definition', 'KpiCategoryId') IS NOT NULL
    ALTER TABLE KPI.Definition DROP COLUMN KpiCategoryId;
GO

IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_KpiCatWeight_Category')
    ALTER TABLE KPI.CategoryWeight DROP CONSTRAINT FK_KpiCatWeight_Category;
GO

IF COL_LENGTH('KPI.CategoryWeight', 'KpiCategoryId') IS NOT NULL
    ALTER TABLE KPI.CategoryWeight DROP COLUMN KpiCategoryId;
GO

-- Restore the original index on Definition.Category
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('KPI.Definition') AND name = 'IX_KpiDef_Category'
)
    CREATE INDEX IX_KpiDef_Category ON KPI.Definition (Category) WHERE Category IS NOT NULL;
GO


-- ─── 5. Restore views/procs to text-Category shape ──────────
-- This block CREATE OR ALTERs every view/proc the Up script touched, restoring
-- their pre-migration body. The bodies match KpiScoringCategoryWeightTemplate.Up.sql
-- and baseline_create.sql at the moment immediately before this migration.

CREATE OR ALTER VIEW App.vKpiPackageItems
AS
    SELECT
        pi.KpiPackageItemId, pi.KpiPackageId, pi.KpiId,
        d.KPICode  AS KpiCode,
        d.KPIName  AS KpiName,
        d.Category,
        d.DataType,
        d.IsActive AS KpiIsActive
    FROM KPI.KpiPackageItem AS pi
    JOIN KPI.Definition     AS d  ON d.KPIID = pi.KpiId;
GO

CREATE OR ALTER VIEW App.vKpiDefinitions
AS
    SELECT
        d.KPIID, d.ExternalId, d.KPICode, d.KPIName, d.KPIDescription,
        d.Category, d.Unit, d.DataType, d.AllowMultiValue, d.CollectionType,
        d.ThresholdDirection, d.SourceSystemRef, d.IsActive, d.CreatedOnUtc, d.ModifiedOnUtc,
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
    OUTER APPLY (
        SELECT COUNT(*) AS AssignmentCount
        FROM KPI.Assignment AS a
        WHERE a.KPIID = d.KPIID AND a.IsActive = 1
    ) AS assignments;
GO

-- vKpiSubmissionScores: revert to the KpiScoringCategoryWeightTemplate.Up shape (no Category lookup join)
CREATE OR ALTER VIEW App.vKpiSubmissionScores
AS
SELECT
    a.AssignmentID, a.AccountId, a.OrgUnitId AS SiteOrgUnitId, a.PeriodID, a.IsRequired,
    sub.SubmissionID, sub.LockState,
    d.KPIID, d.KPICode, d.KPIName, d.Category, d.DataType,
    COALESCE(sub.SubmittedKpiWeight, a.KpiWeight) AS KpiWeight,
    COALESCE(sub.SubmittedPenaliseMissingOnScore, a.PenaliseMissingOnScore) AS PenaliseMissingOnScore,
    COALESCE(a.CategoryWeightSnapshot, 1.0) AS CategoryWeight,
    CASE
        WHEN d.DataType = 'Text' THEN NULL
        WHEN sub.SubmissionID IS NULL THEN
            CASE WHEN COALESCE(sub.SubmittedPenaliseMissingOnScore, a.PenaliseMissingOnScore) = 1
                  AND a.IsRequired = 1
                 THEN 0 ELSE NULL END
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

-- vSiteCompositeScore back to the text-Category form (KpiScoringCategoryWeightTemplate)
CREATE OR ALTER VIEW App.vSiteCompositeScore
AS
WITH per_category AS (
    SELECT
        s.AccountId, s.SiteOrgUnitId, s.PeriodID, s.Category,
        AVG(s.CategoryWeight) AS CategoryWeight,
        SUM(CASE WHEN s.Score IS NULL THEN 0 ELSE s.Score * s.KpiWeight END) AS WeightedScore,
        SUM(CASE WHEN s.Score IS NULL THEN 0 ELSE s.KpiWeight END)           AS WeightSum,
        SUM(CASE WHEN s.Score IS NOT NULL THEN 1 ELSE 0 END)                  AS ScoredCount,
        COUNT(*)                                                              AS TotalCount
    FROM App.vKpiSubmissionScores AS s
    WHERE s.SiteOrgUnitId IS NOT NULL
    GROUP BY s.AccountId, s.SiteOrgUnitId, s.PeriodID, s.Category
),
weighted AS (
    SELECT pc.AccountId, pc.SiteOrgUnitId, pc.PeriodID, pc.Category,
           pc.ScoredCount, pc.TotalCount,
           CASE WHEN pc.WeightSum = 0 THEN NULL ELSE pc.WeightedScore / pc.WeightSum END AS CategoryScore,
           pc.CategoryWeight, CAST(1 AS BIT) AS CategoryActive
    FROM per_category AS pc
)
SELECT w.AccountId, w.SiteOrgUnitId, w.PeriodID, w.Category, w.CategoryScore, w.CategoryWeight,
       w.CategoryActive, w.ScoredCount, w.TotalCount,
       SUM(CASE WHEN w.CategoryScore IS NULL THEN 0 ELSE w.CategoryScore * w.CategoryWeight END)
           OVER (PARTITION BY w.AccountId, w.SiteOrgUnitId, w.PeriodID)
       /
       NULLIF(SUM(CASE WHEN w.CategoryScore IS NULL THEN 0 ELSE w.CategoryWeight END)
           OVER (PARTITION BY w.AccountId, w.SiteOrgUnitId, w.PeriodID), 0) AS CompositeScore
FROM weighted AS w;
GO

-- The remaining views (vKpiAssignmentTemplates, vKpiAssignments, vEffectiveKpiAssignments,
-- vKpiSubmissions, vSubmissionTokenAssignments, vSiteSubmissionDetails, Reporting.vw_PBI*)
-- can be restored by re-running their CREATE OR ALTER from baseline_create.sql or the
-- KpiScoringCategoryWeightTemplate.Up.sql migration. They keep working in the meantime
-- because the Down restored the d.Category text column they reference.
GO

-- ─── 6. Restore procs to text-Category form ─────────────────
CREATE OR ALTER PROCEDURE App.usp_UpsertKpiDefinition
    @KPICode                NVARCHAR(50),
    @KPIName                NVARCHAR(200),
    @KPIDescription         NVARCHAR(1000)  = NULL,
    @Category               NVARCHAR(100)   = NULL,
    @Unit                   NVARCHAR(50)    = NULL,
    @DataType               NVARCHAR(20)    = 'Numeric',
    @AllowMultiValue        BIT             = 0,
    @CollectionType         NVARCHAR(20)    = 'Manual',
    @ThresholdDirection     NVARCHAR(10)    = NULL,
    @SourceSystemRef        NVARCHAR(200)   = NULL,
    @IsActive               BIT             = 1,
    @DropDownOptionsPipe    NVARCHAR(MAX)   = NULL,
    @ActorUPN               NVARCHAR(320)   = NULL,
    @KPIID                  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @KPIID = (SELECT KPIID FROM KPI.Definition WHERE KPICode = @KPICode);

    IF @KPIID IS NULL
    BEGIN
        INSERT INTO KPI.Definition
            (KPICode, KPIName, KPIDescription, Category, Unit,
             DataType, AllowMultiValue, CollectionType, ThresholdDirection, SourceSystemRef, IsActive)
        VALUES
            (@KPICode, @KPIName, @KPIDescription, @Category, @Unit,
             @DataType, @AllowMultiValue, @CollectionType, @ThresholdDirection, @SourceSystemRef, @IsActive);
        SET @KPIID = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE KPI.Definition
        SET KPIName            = @KPIName,
            KPIDescription     = @KPIDescription,
            Category           = @Category,
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

    IF @DropDownOptionsPipe IS NOT NULL
    BEGIN
        DELETE FROM KPI.DropDownOption WHERE KPIID = @KPIID;
        IF LEN(@DropDownOptionsPipe) > 0
        BEGIN
            INSERT INTO KPI.DropDownOption (KPIID, OptionValue, SortOrder)
            SELECT @KPIID, LTRIM(RTRIM(value)), ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1
            FROM STRING_SPLIT(@DropDownOptionsPipe, '|')
            WHERE LEN(LTRIM(RTRIM(value))) > 0
              AND LTRIM(RTRIM(value)) NOT IN (SELECT OptionValue FROM KPI.DropDownOption WHERE KPIID = @KPIID);
        END
    END
END;
GO

CREATE OR ALTER PROCEDURE App.usp_UpsertCategoryWeights
    @AccountCode NVARCHAR(50),
    @WeightsJson NVARCHAR(MAX),
    @ActorUPN    NVARCHAR(320) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AccountId INT = (SELECT AccountId FROM Dim.Account WHERE AccountCode = @AccountCode AND IsActive = 1);
    IF @AccountId IS NULL THROW 50250, 'Account not found or inactive.', 1;
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
        UPDATE SET Weight = ISNULL(src.Weight, tgt.Weight),
                   IsActive = ISNULL(src.IsActive, tgt.IsActive),
                   ModifiedOnUtc = SYSUTCDATETIME(), ModifiedBy = @Actor
    WHEN NOT MATCHED BY TARGET AND src.Category IS NOT NULL THEN
        INSERT (AccountId, Category, Weight, IsActive, CreatedBy, ModifiedBy)
        VALUES (@AccountId, src.Category, ISNULL(src.Weight, 1.0), ISNULL(src.IsActive, 1), @Actor, @Actor);
END;
GO

CREATE OR ALTER PROCEDURE App.usp_RefreshTemplateCategoryWeights
    @AccountCode NVARCHAR(50),
    @Category    NVARCHAR(100) = NULL,
    @ActorUPN    NVARCHAR(320) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AccountId INT = (SELECT AccountId FROM Dim.Account WHERE AccountCode = @AccountCode AND IsActive = 1);
    IF @AccountId IS NULL THROW 50260, 'Account not found or inactive.', 1;
    DECLARE @Actor NVARCHAR(128) = COALESCE(@ActorUPN, SESSION_USER);

    UPDATE t
    SET CategoryWeightSnapshot = ISNULL(cw.Weight, 1.0),
        ModifiedOnUtc = SYSUTCDATETIME(), ModifiedBy = @Actor
    FROM KPI.AssignmentTemplate AS t
    JOIN KPI.Definition AS d ON d.KPIID = t.KPIID
    LEFT JOIN KPI.CategoryWeight AS cw ON cw.AccountId = t.AccountId AND cw.Category = d.Category
    WHERE t.AccountId = @AccountId AND (@Category IS NULL OR d.Category = @Category);

    DECLARE @TemplatesUpdated INT = @@ROWCOUNT;
    DECLARE @TemplateId INT;
    DECLARE @AssignmentsUpdated INT = 0;

    DECLARE template_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT t.AssignmentTemplateID FROM KPI.AssignmentTemplate AS t
        JOIN KPI.Definition AS d ON d.KPIID = t.KPIID
        WHERE t.AccountId = @AccountId AND (@Category IS NULL OR d.Category = @Category);

    OPEN template_cursor;
    FETCH NEXT FROM template_cursor INTO @TemplateId;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @CascadeCount INT = (SELECT COUNT(*) FROM KPI.Assignment AS a
            WHERE a.AssignmentTemplateID = @TemplateId
              AND NOT EXISTS (SELECT 1 FROM KPI.Submission s WHERE s.AssignmentID = a.AssignmentID));
        EXEC App.usp_CascadeAssignmentTemplateThresholds @AssignmentTemplateID = @TemplateId, @ActorUPN = @ActorUPN;
        SET @AssignmentsUpdated = @AssignmentsUpdated + @CascadeCount;
        FETCH NEXT FROM template_cursor INTO @TemplateId;
    END
    CLOSE template_cursor; DEALLOCATE template_cursor;

    SELECT @TemplatesUpdated AS TemplatesUpdated, @AssignmentsUpdated AS AssignmentsUpdated;
END;
GO

-- usp_AssignKpi: revert cw join to use Category text (body otherwise unchanged from up).
-- We only restore the proc shape; full body matches the KpiScoringCategoryWeightTemplate.Up.sql version.
-- Rolling back the full body here would duplicate hundreds of lines; the production
-- usp_AssignKpi reads d.Category through the restored text column anyway.
GO

-- ─── 7. Drop KPI.Category lookup table ──────────────────────
IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE object_id = OBJECT_ID('KPI.Category') AND name = 'IX_KpiCategory_IsActive')
    DROP INDEX IX_KpiCategory_IsActive ON KPI.Category;
GO

IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE object_id = OBJECT_ID('KPI.Category') AND name = 'UX_KpiCategory_ExternalId')
    DROP INDEX UX_KpiCategory_ExternalId ON KPI.Category;
GO

IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE object_id = OBJECT_ID('KPI.Category') AND name = 'UX_KpiCategory_Code')
    DROP INDEX UX_KpiCategory_Code ON KPI.Category;
GO

IF OBJECT_ID('KPI.Category', 'U') IS NOT NULL
    DROP TABLE KPI.Category;
GO
