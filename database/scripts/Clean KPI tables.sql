/*
================================================================================
Clean KPI Data Only
Description:
  - Deletes KPI / workflow operational data
  - Keeps schemas, tables, views, procedures, accounts, org units, users, roles
  - Safe to re-run
================================================================================
*/
SET NOCOUNT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    -- Workflow / token / submission state first --------------------------------
    DELETE FROM Workflow.NotificationLog;
    DELETE FROM Workflow.ReminderState;

    DELETE FROM KPI.SubmissionAudit;
    DELETE FROM KPI.SubmissionToken;
    DELETE FROM KPI.Submission;
    DELETE FROM KPI.EscalationContact;

    -- Generated / materialized KPI rows ----------------------------------------
    DELETE FROM KPI.Assignment;
    DELETE FROM KPI.AssignmentTemplateDropDownOption;
    DELETE FROM KPI.AssignmentTemplate;

    -- Period calendar -----------------------------------------------------------
    DELETE FROM KPI.Period;
    DELETE FROM KPI.PeriodSchedule;

    -- KPI library ---------------------------------------------------------------
    DELETE FROM KPI.DropDownOption;
    DELETE FROM KPI.Definition;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
