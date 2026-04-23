-- ============================================================
-- Migration: SchemaHygiene — Up
-- Cleans up schema inconsistencies surfaced by the review:
--   1. Audit columns on KPI.PeriodSchedule made NOT NULL + defaulted
--   2. Audit columns on KPI.AssignmentTemplate made NOT NULL + defaulted
--   3. Dim.Tag.TagName — UNIQUE index (name uniqueness was only enforced
--      procedurally inside App.usp_UpsertTag)
--   4. KPI.Submission.LockedByPrincipalId — supporting index for lock queries
--   5. Sec.PrincipalDelegation.DelegatorPrincipalId — index for the
--      "delegations I have granted" lookup path
--
-- Safe to re-run: all statements are idempotent.
-- ============================================================

-- 1. KPI.PeriodSchedule audit columns ----------------------------------------
UPDATE KPI.PeriodSchedule
    SET CreatedBy = SESSION_USER
    WHERE CreatedBy IS NULL;

UPDATE KPI.PeriodSchedule
    SET ModifiedOnUtc = CreatedOnUtc
    WHERE ModifiedOnUtc IS NULL;

UPDATE KPI.PeriodSchedule
    SET ModifiedBy = COALESCE(CreatedBy, SESSION_USER)
    WHERE ModifiedBy IS NULL;

IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('KPI.PeriodSchedule')
      AND name = 'CreatedBy'
      AND is_nullable = 1
)
    ALTER TABLE KPI.PeriodSchedule ALTER COLUMN CreatedBy NVARCHAR(128) NOT NULL;
GO

IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('KPI.PeriodSchedule')
      AND name = 'ModifiedOnUtc'
      AND is_nullable = 1
)
    ALTER TABLE KPI.PeriodSchedule ALTER COLUMN ModifiedOnUtc DATETIME2(3) NOT NULL;
GO

IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('KPI.PeriodSchedule')
      AND name = 'ModifiedBy'
      AND is_nullable = 1
)
    ALTER TABLE KPI.PeriodSchedule ALTER COLUMN ModifiedBy NVARCHAR(128) NOT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.default_constraints
    WHERE parent_object_id = OBJECT_ID('KPI.PeriodSchedule')
      AND name = 'DF_KpiPeriodSchedule_CreatedBy'
)
    ALTER TABLE KPI.PeriodSchedule
        ADD CONSTRAINT DF_KpiPeriodSchedule_CreatedBy
        DEFAULT SESSION_USER FOR CreatedBy;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.default_constraints
    WHERE parent_object_id = OBJECT_ID('KPI.PeriodSchedule')
      AND name = 'DF_KpiPeriodSchedule_ModifiedOn'
)
    ALTER TABLE KPI.PeriodSchedule
        ADD CONSTRAINT DF_KpiPeriodSchedule_ModifiedOn
        DEFAULT SYSUTCDATETIME() FOR ModifiedOnUtc;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.default_constraints
    WHERE parent_object_id = OBJECT_ID('KPI.PeriodSchedule')
      AND name = 'DF_KpiPeriodSchedule_ModifiedBy'
)
    ALTER TABLE KPI.PeriodSchedule
        ADD CONSTRAINT DF_KpiPeriodSchedule_ModifiedBy
        DEFAULT SESSION_USER FOR ModifiedBy;
GO

-- 2. KPI.AssignmentTemplate audit columns ------------------------------------
UPDATE KPI.AssignmentTemplate
    SET CreatedBy = SESSION_USER
    WHERE CreatedBy IS NULL;

UPDATE KPI.AssignmentTemplate
    SET ModifiedOnUtc = CreatedOnUtc
    WHERE ModifiedOnUtc IS NULL;

UPDATE KPI.AssignmentTemplate
    SET ModifiedBy = COALESCE(CreatedBy, SESSION_USER)
    WHERE ModifiedBy IS NULL;

IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('KPI.AssignmentTemplate')
      AND name = 'CreatedBy'
      AND is_nullable = 1
)
    ALTER TABLE KPI.AssignmentTemplate ALTER COLUMN CreatedBy NVARCHAR(128) NOT NULL;
GO

IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('KPI.AssignmentTemplate')
      AND name = 'ModifiedOnUtc'
      AND is_nullable = 1
)
    ALTER TABLE KPI.AssignmentTemplate ALTER COLUMN ModifiedOnUtc DATETIME2(3) NOT NULL;
GO

IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('KPI.AssignmentTemplate')
      AND name = 'ModifiedBy'
      AND is_nullable = 1
)
    ALTER TABLE KPI.AssignmentTemplate ALTER COLUMN ModifiedBy NVARCHAR(128) NOT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.default_constraints
    WHERE parent_object_id = OBJECT_ID('KPI.AssignmentTemplate')
      AND name = 'DF_KpiAssignmentTemplate_CreatedBy'
)
    ALTER TABLE KPI.AssignmentTemplate
        ADD CONSTRAINT DF_KpiAssignmentTemplate_CreatedBy
        DEFAULT SESSION_USER FOR CreatedBy;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.default_constraints
    WHERE parent_object_id = OBJECT_ID('KPI.AssignmentTemplate')
      AND name = 'DF_KpiAssignmentTemplate_ModifiedOn'
)
    ALTER TABLE KPI.AssignmentTemplate
        ADD CONSTRAINT DF_KpiAssignmentTemplate_ModifiedOn
        DEFAULT SYSUTCDATETIME() FOR ModifiedOnUtc;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.default_constraints
    WHERE parent_object_id = OBJECT_ID('KPI.AssignmentTemplate')
      AND name = 'DF_KpiAssignmentTemplate_ModifiedBy'
)
    ALTER TABLE KPI.AssignmentTemplate
        ADD CONSTRAINT DF_KpiAssignmentTemplate_ModifiedBy
        DEFAULT SESSION_USER FOR ModifiedBy;
GO

-- 3. UNIQUE index on Dim.Tag.TagName -----------------------------------------
-- Intentionally not filtered: both active and inactive tags must have unique
-- display names (a deactivated tag blocks reuse of the name until it is
-- renamed or its row is deleted). If duplicates already exist, this CREATE
-- INDEX will fail loudly — that is the right signal.
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('Dim.Tag')
      AND name = 'UX_Tag_Name'
)
    CREATE UNIQUE INDEX UX_Tag_Name ON Dim.Tag (TagName);
GO

-- 4. KPI.Submission.LockedByPrincipalId index --------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('KPI.Submission')
      AND name = 'IX_KpiSub_LockedBy_Principal'
)
    CREATE INDEX IX_KpiSub_LockedBy_Principal
        ON KPI.Submission (LockedByPrincipalId)
        WHERE LockedByPrincipalId IS NOT NULL;
GO

-- 5. Sec.PrincipalDelegation.DelegatorPrincipalId index ----------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('Sec.PrincipalDelegation')
      AND name = 'IX_PrincipalDelegation_Delegator'
)
    CREATE INDEX IX_PrincipalDelegation_Delegator
        ON Sec.PrincipalDelegation (DelegatorPrincipalId, IsActive);
GO
