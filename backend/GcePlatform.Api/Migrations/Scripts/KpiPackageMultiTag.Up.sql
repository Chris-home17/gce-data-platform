-- ============================================================
-- Migration: KpiPackageMultiTag — Up
-- Adds:
--   1. KPI.KpiPackageTag — many-to-many Package ↔ Tag junction
--   2. Migrates existing TagId data to the new table
--   3. Drops TagId column from KPI.KpiPackage
--   4. Updates App.vKpiPackages to include TagsRaw (pipe-delimited)
--   5. App.usp_SetKpiPackageTags stored procedure
--   6. Updates App.usp_UpsertKpiPackage (removes @TagId param)
-- Safe to re-run: all DDL uses idempotent guards.
-- ============================================================
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. KPI.KpiPackageTag (many-to-many: Package ↔ Tag)
-- ─────────────────────────────────────────────────────────────────────────────
IF OBJECT_ID('KPI.KpiPackageTag', 'U') IS NULL
BEGIN
    CREATE TABLE KPI.KpiPackageTag
    (
        KpiPackageTagId INT NOT NULL IDENTITY(1,1) PRIMARY KEY,
        KpiPackageId    INT NOT NULL REFERENCES KPI.KpiPackage(KpiPackageId) ON DELETE CASCADE,
        TagId           INT NOT NULL REFERENCES Dim.Tag(TagId),
        CONSTRAINT UX_KpiPackageTag UNIQUE (KpiPackageId, TagId)
    );

    CREATE INDEX IX_KpiPackageTag_TagId ON KPI.KpiPackageTag (TagId);
END;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Migrate existing single TagId values to the junction table
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO KPI.KpiPackageTag (KpiPackageId, TagId)
SELECT KpiPackageId, TagId
FROM KPI.KpiPackage
WHERE TagId IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM KPI.KpiPackageTag pt
      WHERE pt.KpiPackageId = KpiPackage.KpiPackageId
        AND pt.TagId = KpiPackage.TagId
  );
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Drop TagId FK constraint and column from KPI.KpiPackage
-- ─────────────────────────────────────────────────────────────────────────────
DECLARE @fkName NVARCHAR(200);
SELECT @fkName = fk.name
FROM sys.foreign_keys AS fk
JOIN sys.foreign_key_columns AS fkc ON fkc.constraint_object_id = fk.object_id
JOIN sys.columns AS c ON c.object_id = fkc.parent_object_id AND c.column_id = fkc.parent_column_id
WHERE fk.parent_object_id = OBJECT_ID('KPI.KpiPackage')
  AND c.name = 'TagId';

IF @fkName IS NOT NULL
    EXEC ('ALTER TABLE KPI.KpiPackage DROP CONSTRAINT ' + @fkName);
GO

IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('KPI.KpiPackage') AND name = 'TagId'
)
BEGIN
    ALTER TABLE KPI.KpiPackage DROP COLUMN TagId;
END;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Update App.vKpiPackages — replace single tag columns with TagsRaw
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER VIEW App.vKpiPackages
AS
    SELECT
        p.KpiPackageId,
        p.PackageCode,
        p.PackageName,
        p.IsActive,
        ISNULL(items.KpiCount, 0) AS KpiCount,
        -- Pipe-delimited "TagId:TagName" pairs for efficient frontend parsing
        (
            SELECT STRING_AGG(CAST(t.TagId AS NVARCHAR(10)) + ':' + t.TagName, '|')
            FROM KPI.KpiPackageTag AS pt
            JOIN Dim.Tag AS t ON t.TagId = pt.TagId
            WHERE pt.KpiPackageId = p.KpiPackageId
        ) AS TagsRaw
    FROM KPI.KpiPackage AS p
    OUTER APPLY
    (
        SELECT COUNT(*) AS KpiCount
        FROM KPI.KpiPackageItem AS pi
        WHERE pi.KpiPackageId = p.KpiPackageId
    ) AS items;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. App.usp_SetKpiPackageTags (replace-all: deletes existing, inserts new)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE App.usp_SetKpiPackageTags
    @KpiPackageId INT,
    @TagIds       NVARCHAR(MAX),  -- comma-separated tag IDs, e.g. '1,3,7' (empty string = clear all)
    @ActorUPN     NVARCHAR(320) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM KPI.KpiPackage WHERE KpiPackageId = @KpiPackageId)
        THROW 50320, 'KPI Package not found.', 1;

    DELETE FROM KPI.KpiPackageTag WHERE KpiPackageId = @KpiPackageId;

    IF @TagIds IS NOT NULL AND LEN(LTRIM(RTRIM(@TagIds))) > 0
    BEGIN
        INSERT INTO KPI.KpiPackageTag (KpiPackageId, TagId)
        SELECT DISTINCT @KpiPackageId, CAST(LTRIM(RTRIM(value)) AS INT)
        FROM STRING_SPLIT(@TagIds, ',')
        WHERE LEN(LTRIM(RTRIM(value))) > 0
          AND ISNUMERIC(LTRIM(RTRIM(value))) = 1;

        IF EXISTS (
            SELECT 1
            FROM KPI.KpiPackageTag AS pt
            WHERE pt.KpiPackageId = @KpiPackageId
              AND NOT EXISTS (SELECT 1 FROM Dim.Tag WHERE TagId = pt.TagId AND IsActive = 1)
        )
            THROW 50321, 'One or more TagIds are invalid or inactive.', 1;
    END

    UPDATE KPI.KpiPackage
    SET ModifiedOnUtc = SYSUTCDATETIME(),
        ModifiedBy    = COALESCE(@ActorUPN, SESSION_USER)
    WHERE KpiPackageId = @KpiPackageId;
END;
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Update App.usp_UpsertKpiPackage — remove @TagId param, tags handled separately
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE App.usp_UpsertKpiPackage
    @PackageCode  NVARCHAR(50),
    @PackageName  NVARCHAR(200),
    @ActorUPN     NVARCHAR(320) = NULL,
    @KpiPackageId INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @KpiPackageId = (SELECT KpiPackageId FROM KPI.KpiPackage WHERE PackageCode = @PackageCode);

    IF @KpiPackageId IS NULL
    BEGIN
        INSERT INTO KPI.KpiPackage (PackageCode, PackageName, IsActive, CreatedBy, ModifiedBy)
        VALUES (@PackageCode, @PackageName, 1,
                COALESCE(@ActorUPN, SESSION_USER),
                COALESCE(@ActorUPN, SESSION_USER));

        SET @KpiPackageId = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE KPI.KpiPackage
        SET PackageName   = @PackageName,
            ModifiedOnUtc = SYSUTCDATETIME(),
            ModifiedBy    = COALESCE(@ActorUPN, SESSION_USER)
        WHERE KpiPackageId = @KpiPackageId;
    END
END;
GO
