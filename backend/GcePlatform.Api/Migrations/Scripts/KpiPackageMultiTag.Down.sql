-- ============================================================
-- Migration: KpiPackageMultiTag — Down (rollback)
-- Reverses the multi-tag migration:
--   1. Re-add TagId column to KPI.KpiPackage
--   2. Restore single tag per package (uses first tag if multiple exist)
--   3. Drop KPI.KpiPackageTag
--   4. Restore App.vKpiPackages to single-tag version
--   5. Restore App.usp_UpsertKpiPackage with @TagId param
-- ============================================================
GO

-- 1. Re-add TagId column
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('KPI.KpiPackage') AND name = 'TagId'
)
BEGIN
    ALTER TABLE KPI.KpiPackage
        ADD TagId INT NULL REFERENCES Dim.Tag(TagId);
END;
GO

-- 2. Restore single tag per package (use MIN TagId if multiple tags exist)
UPDATE KPI.KpiPackage
SET TagId = (
    SELECT MIN(TagId)
    FROM KPI.KpiPackageTag
    WHERE KpiPackageId = KPI.KpiPackage.KpiPackageId
);
GO

-- 3. Drop the junction table
IF OBJECT_ID('KPI.KpiPackageTag', 'U') IS NOT NULL
    DROP TABLE KPI.KpiPackageTag;
GO

-- 4. Restore App.vKpiPackages to single-tag version
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

-- 5. Restore App.usp_UpsertKpiPackage with @TagId
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
