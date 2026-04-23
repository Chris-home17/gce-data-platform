-- ============================================================
-- Migration: SchemaHygiene — Down
-- Reverses the additive hygiene changes. NOT NULL reversions keep
-- the defaults in place so existing rows remain valid; columns
-- revert to NULL-able for symmetry with the prior baseline.
-- ============================================================

-- 5. Drop DelegatorPrincipalId index -----------------------------------------
IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('Sec.PrincipalDelegation')
      AND name = 'IX_PrincipalDelegation_Delegator'
)
    DROP INDEX IX_PrincipalDelegation_Delegator ON Sec.PrincipalDelegation;
GO

-- 4. Drop LockedBy_Principal index -------------------------------------------
IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('KPI.Submission')
      AND name = 'IX_KpiSub_LockedBy_Principal'
)
    DROP INDEX IX_KpiSub_LockedBy_Principal ON KPI.Submission;
GO

-- 3. Drop UX_Tag_Name --------------------------------------------------------
IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('Dim.Tag')
      AND name = 'UX_Tag_Name'
)
    DROP INDEX UX_Tag_Name ON Dim.Tag;
GO

-- 2. KPI.AssignmentTemplate — revert Modified* defaults + nullability --------
IF EXISTS (
    SELECT 1 FROM sys.default_constraints
    WHERE parent_object_id = OBJECT_ID('KPI.AssignmentTemplate')
      AND name = 'DF_KpiAssignmentTemplate_ModifiedBy'
)
    ALTER TABLE KPI.AssignmentTemplate DROP CONSTRAINT DF_KpiAssignmentTemplate_ModifiedBy;
GO

IF EXISTS (
    SELECT 1 FROM sys.default_constraints
    WHERE parent_object_id = OBJECT_ID('KPI.AssignmentTemplate')
      AND name = 'DF_KpiAssignmentTemplate_ModifiedOn'
)
    ALTER TABLE KPI.AssignmentTemplate DROP CONSTRAINT DF_KpiAssignmentTemplate_ModifiedOn;
GO

IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('KPI.AssignmentTemplate')
      AND name = 'ModifiedBy'
      AND is_nullable = 0
)
    ALTER TABLE KPI.AssignmentTemplate ALTER COLUMN ModifiedBy NVARCHAR(128) NULL;
GO

IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('KPI.AssignmentTemplate')
      AND name = 'ModifiedOnUtc'
      AND is_nullable = 0
)
    ALTER TABLE KPI.AssignmentTemplate ALTER COLUMN ModifiedOnUtc DATETIME2(3) NULL;
GO

IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('KPI.AssignmentTemplate')
      AND name = 'CreatedBy'
      AND is_nullable = 0
)
    ALTER TABLE KPI.AssignmentTemplate ALTER COLUMN CreatedBy NVARCHAR(128) NULL;
GO

-- 1. KPI.PeriodSchedule — revert Modified* defaults + nullability ------------
IF EXISTS (
    SELECT 1 FROM sys.default_constraints
    WHERE parent_object_id = OBJECT_ID('KPI.PeriodSchedule')
      AND name = 'DF_KpiPeriodSchedule_ModifiedBy'
)
    ALTER TABLE KPI.PeriodSchedule DROP CONSTRAINT DF_KpiPeriodSchedule_ModifiedBy;
GO

IF EXISTS (
    SELECT 1 FROM sys.default_constraints
    WHERE parent_object_id = OBJECT_ID('KPI.PeriodSchedule')
      AND name = 'DF_KpiPeriodSchedule_ModifiedOn'
)
    ALTER TABLE KPI.PeriodSchedule DROP CONSTRAINT DF_KpiPeriodSchedule_ModifiedOn;
GO

IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('KPI.PeriodSchedule')
      AND name = 'ModifiedBy'
      AND is_nullable = 0
)
    ALTER TABLE KPI.PeriodSchedule ALTER COLUMN ModifiedBy NVARCHAR(128) NULL;
GO

IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('KPI.PeriodSchedule')
      AND name = 'ModifiedOnUtc'
      AND is_nullable = 0
)
    ALTER TABLE KPI.PeriodSchedule ALTER COLUMN ModifiedOnUtc DATETIME2(3) NULL;
GO

IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('KPI.PeriodSchedule')
      AND name = 'CreatedBy'
      AND is_nullable = 0
)
    ALTER TABLE KPI.PeriodSchedule ALTER COLUMN CreatedBy NVARCHAR(128) NULL;
GO
