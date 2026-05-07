-- ============================================================
-- Migration: AddTimeKpiDataType — Up
-- Adds 'Time' to the KPI.Definition.DataType CHECK constraint
-- so KPIs like "Average response time" can be authored.
--
-- Storage convention: a Time-typed KPI stores its value in
-- KPI.Submission.SubmissionValue as total seconds (DECIMAL(18,4)),
-- and ThresholdGreen / Amber / Red are likewise expressed in seconds.
-- The existing RAG comparison logic (>=/<= on SubmissionValue)
-- works unchanged; only the UI parses/formats HH:MM:SS.
--
-- Safe to re-run: the constraint is dropped only if it exists.
-- ============================================================

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
        CHECK (DataType IN ('Numeric','Percentage','Boolean','Text','Currency','DropDown','Time'));
GO
