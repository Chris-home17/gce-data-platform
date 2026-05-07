-- ============================================================
-- Migration: AddTimeKpiDataType — Down
-- Removes 'Time' from the KPI.Definition.DataType CHECK constraint.
-- Any rows with DataType = 'Time' must be migrated away before
-- rolling back, otherwise the re-added constraint will fail.
-- ============================================================

IF EXISTS (SELECT 1 FROM KPI.Definition WHERE DataType = 'Time')
    THROW 50000,
        N'Cannot roll back AddTimeKpiDataType: KPI.Definition rows with DataType = ''Time'' still exist. Migrate or delete them before running Down.',
        1;
GO

IF EXISTS (
    SELECT 1
    FROM sys.check_constraints
    WHERE name = 'CK_KpiDef_DataType'
      AND parent_object_id = OBJECT_ID(N'KPI.Definition')
)
    ALTER TABLE KPI.Definition DROP CONSTRAINT CK_KpiDef_DataType;
GO

ALTER TABLE KPI.Definition
    ADD CONSTRAINT CK_KpiDef_DataType
        CHECK (DataType IN ('Numeric','Percentage','Boolean','Text','Currency','DropDown'));
GO
