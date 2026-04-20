-- ============================================================
-- Migration: KpiAssignmentGroups — Down
-- Reverts assignment group support.
-- ============================================================
GO

-- Restore views without AssignmentGroupName
CREATE OR ALTER VIEW App.vAssignmentGroups AS SELECT TOP 0 1 AS Placeholder;
GO
DROP VIEW IF EXISTS App.vAssignmentGroups;
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
        d.Category,
        d.DataType,
        CAST(d.AllowMultiValue AS bit)                          AS AllowMultiValue,
        CASE
            WHEN d.DataType = 'DropDown' THEN
                COALESCE(
                    CASE
                        WHEN asgn.AssignmentTemplateID IS NOT NULL
                         AND EXISTS (SELECT 1 FROM KPI.AssignmentTemplateDropDownOption AS x WHERE x.AssignmentTemplateID = asgn.AssignmentTemplateID)
                        THEN (SELECT STRING_AGG(opt.OptionValue, '||') WITHIN GROUP (ORDER BY opt.SortOrder) FROM KPI.AssignmentTemplateDropDownOption AS opt WHERE opt.AssignmentTemplateID = asgn.AssignmentTemplateID)
                    END,
                    (SELECT STRING_AGG(opt.OptionValue, '||') WITHIN GROUP (ORDER BY opt.SortOrder) FROM KPI.DropDownOption AS opt WHERE opt.KPIID = d.KPIID AND opt.IsActive = 1)
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
        CAST(CASE WHEN sub.SubmissionID IS NOT NULL THEN 1 ELSE 0 END AS bit) AS IsSubmitted
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
                AND NOT EXISTS (
                    SELECT 1 FROM KPI.Assignment AS sa
                    WHERE sa.KPIID = asgn.KPIID AND sa.OrgUnitId = st.SiteOrgUnitId AND sa.PeriodID = st.PeriodId AND sa.IsActive = 1
                )
            )
       )
    JOIN KPI.Definition AS d ON d.KPIID = asgn.KPIID
    LEFT JOIN KPI.AssignmentTemplate AS t ON t.AssignmentTemplateID = asgn.AssignmentTemplateID
    LEFT JOIN KPI.Submission AS sub ON sub.AssignmentID = asgn.AssignmentID;
GO

-- Restore SPs (remove @AssignmentGroupName param)
CREATE OR ALTER PROCEDURE App.usp_UpsertKpiAssignmentTemplate
    @KPICode            NVARCHAR(50),
    @PeriodScheduleID   INT,
    @AccountCode        NVARCHAR(50),
    @OrgUnitCode        NVARCHAR(50)    = NULL,
    @OrgUnitType        NVARCHAR(20)    = 'Site',
    @StartPeriodYear    SMALLINT        = NULL,
    @StartPeriodMonth   TINYINT         = NULL,
    @EndPeriodYear      SMALLINT        = NULL,
    @EndPeriodMonth     TINYINT         = NULL,
    @IsRequired         BIT             = 1,
    @TargetValue        DECIMAL(18,4)   = NULL,
    @ThresholdGreen     DECIMAL(18,4)   = NULL,
    @ThresholdAmber     DECIMAL(18,4)   = NULL,
    @ThresholdRed       DECIMAL(18,4)   = NULL,
    @ThresholdDirection NVARCHAR(10)    = NULL,
    @SubmitterGuidance    NVARCHAR(1000)  = NULL,
    @CustomKpiName        NVARCHAR(200)   = NULL,
    @CustomKpiDescription NVARCHAR(1000)  = NULL,
    @KpiPackageId         INT             = NULL,
    @ActorUPN             NVARCHAR(320)   = NULL,
    @AssignmentTemplateID INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    THROW 50000, 'Down migration: restore from baseline_create.sql', 1;
END;
GO

-- Restore uniqueness indexes on KPI.Assignment
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('KPI.Assignment') AND name = 'UX_KpiAsgn_SiteLevelNoGroup')
    DROP INDEX UX_KpiAsgn_SiteLevelNoGroup ON KPI.Assignment;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('KPI.Assignment') AND name = 'UX_KpiAsgn_SiteLevelWithGroup')
    DROP INDEX UX_KpiAsgn_SiteLevelWithGroup ON KPI.Assignment;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('KPI.Assignment') AND name = 'UX_KpiAsgn_AccountLevelNoGroup')
    DROP INDEX UX_KpiAsgn_AccountLevelNoGroup ON KPI.Assignment;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('KPI.Assignment') AND name = 'UX_KpiAsgn_AccountLevelWithGroup')
    DROP INDEX UX_KpiAsgn_AccountLevelWithGroup ON KPI.Assignment;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('KPI.Assignment') AND name = 'IX_KpiAsgn_GroupName')
    DROP INDEX IX_KpiAsgn_GroupName ON KPI.Assignment;
GO

CREATE UNIQUE INDEX UX_KpiAsgn_SiteLevel
    ON KPI.Assignment (KPIID, OrgUnitId, PeriodID)
    WHERE OrgUnitId IS NOT NULL;
GO
CREATE UNIQUE INDEX UX_KpiAsgn_AccountLevel
    ON KPI.Assignment (KPIID, AccountId, PeriodID)
    WHERE OrgUnitId IS NULL;
GO

-- Restore uniqueness index on KPI.AssignmentTemplate
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('KPI.AssignmentTemplate') AND name = 'UX_KpiAssignmentTemplate_ScopeNoGroup')
    DROP INDEX UX_KpiAssignmentTemplate_ScopeNoGroup ON KPI.AssignmentTemplate;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('KPI.AssignmentTemplate') AND name = 'UX_KpiAssignmentTemplate_ScopeWithGroup')
    DROP INDEX UX_KpiAssignmentTemplate_ScopeWithGroup ON KPI.AssignmentTemplate;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('KPI.AssignmentTemplate') AND name = 'IX_KpiAssignmentTemplate_GroupName')
    DROP INDEX IX_KpiAssignmentTemplate_GroupName ON KPI.AssignmentTemplate;
GO

CREATE UNIQUE INDEX UX_KpiAssignmentTemplate_Scope
    ON KPI.AssignmentTemplate (KPIID, PeriodScheduleID, AccountId, OrgUnitId);
GO

-- Drop columns
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('KPI.AssignmentTemplate') AND name = 'AssignmentGroupName')
    ALTER TABLE KPI.AssignmentTemplate DROP COLUMN AssignmentGroupName;
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('KPI.Assignment') AND name = 'AssignmentGroupName')
    ALTER TABLE KPI.Assignment DROP COLUMN AssignmentGroupName;
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('KPI.SubmissionToken') AND name = 'AssignmentGroupName')
    ALTER TABLE KPI.SubmissionToken DROP COLUMN AssignmentGroupName;
GO
