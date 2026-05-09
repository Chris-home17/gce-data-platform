-- ============================================================
-- Migration: KpiScoringCategoryWeightTemplate — Down
-- Restores live-read category weights: drops the new proc, reverts
-- the four affected procs + three views to their pre-snapshot bodies,
-- then drops the CategoryWeightSnapshot columns.
-- ============================================================

IF OBJECT_ID('App.usp_RefreshTemplateCategoryWeights', 'P') IS NOT NULL
    DROP PROCEDURE App.usp_RefreshTemplateCategoryWeights;
GO

-- Restore vSiteCompositeScore to the LEFT JOIN KPI.CategoryWeight version.
CREATE OR ALTER VIEW App.vSiteCompositeScore
AS
WITH per_category AS (
    SELECT
        s.AccountId, s.SiteOrgUnitId, s.PeriodID, s.Category,
        SUM(CASE WHEN s.Score IS NULL THEN 0 ELSE s.Score * s.KpiWeight END) AS WeightedScore,
        SUM(CASE WHEN s.Score IS NULL THEN 0 ELSE s.KpiWeight END)           AS WeightSum,
        SUM(CASE WHEN s.Score IS NOT NULL THEN 1 ELSE 0 END)                  AS ScoredCount,
        COUNT(*)                                                              AS TotalCount
    FROM App.vKpiSubmissionScores AS s
    WHERE s.SiteOrgUnitId IS NOT NULL
    GROUP BY s.AccountId, s.SiteOrgUnitId, s.PeriodID, s.Category
),
weighted AS (
    SELECT
        pc.AccountId, pc.SiteOrgUnitId, pc.PeriodID, pc.Category,
        pc.ScoredCount, pc.TotalCount,
        CASE WHEN pc.WeightSum = 0 THEN NULL
             ELSE pc.WeightedScore / pc.WeightSum
        END                                AS CategoryScore,
        ISNULL(cw.Weight, 1.0)             AS CategoryWeight,
        CAST(ISNULL(cw.IsActive, 1) AS BIT) AS CategoryActive
    FROM per_category AS pc
    LEFT JOIN KPI.CategoryWeight AS cw
      ON cw.AccountId = pc.AccountId AND cw.Category = pc.Category
)
SELECT
    w.AccountId, w.SiteOrgUnitId, w.PeriodID, w.Category,
    w.CategoryScore, w.CategoryWeight, w.CategoryActive,
    w.ScoredCount, w.TotalCount,
    SUM(CASE WHEN w.CategoryScore IS NULL OR w.CategoryActive = 0
             THEN 0 ELSE w.CategoryScore * w.CategoryWeight END)
        OVER (PARTITION BY w.AccountId, w.SiteOrgUnitId, w.PeriodID)
    /
    NULLIF(SUM(CASE WHEN w.CategoryScore IS NULL OR w.CategoryActive = 0
                    THEN 0 ELSE w.CategoryWeight END)
        OVER (PARTITION BY w.AccountId, w.SiteOrgUnitId, w.PeriodID), 0)
        AS CompositeScore
FROM weighted AS w;
GO

-- Restore vKpiSubmissionScores without CategoryWeight column.
CREATE OR ALTER VIEW App.vKpiSubmissionScores
AS
SELECT
    a.AssignmentID, a.AccountId, a.OrgUnitId AS SiteOrgUnitId, a.PeriodID, a.IsRequired,
    sub.SubmissionID, sub.LockState,
    d.KPIID, d.KPICode, d.KPIName, d.Category, d.DataType,
    COALESCE(sub.SubmittedKpiWeight,            a.KpiWeight)              AS KpiWeight,
    COALESCE(sub.SubmittedPenaliseMissingOnScore, a.PenaliseMissingOnScore) AS PenaliseMissingOnScore,
    CASE
        WHEN d.DataType = 'Text' THEN NULL
        WHEN sub.SubmissionID IS NULL THEN
            CASE WHEN COALESCE(sub.SubmittedPenaliseMissingOnScore, a.PenaliseMissingOnScore) = 1
                  AND a.IsRequired = 1 THEN 0 ELSE NULL END
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

-- Restore vKpiAssignmentTemplates without CategoryWeightSnapshot column.
CREATE OR ALTER VIEW App.vKpiAssignmentTemplates
AS
    SELECT
        t.AssignmentTemplateID, t.ExternalId, d.KPICode, d.KPIName, d.Category, d.DataType,
        sched.PeriodScheduleID, sched.ScheduleName, sched.FrequencyType, sched.FrequencyInterval,
        acct.AccountId, acct.AccountCode, acct.AccountName,
        t.OrgUnitId, ou.OrgUnitCode AS SiteCode, ou.OrgUnitName AS SiteName,
        CASE WHEN t.OrgUnitId IS NULL THEN 1 ELSE 0 END AS IsAccountWide,
        t.StartPeriodYear, t.StartPeriodMonth, t.EndPeriodYear, t.EndPeriodMonth,
        t.IsRequired, t.TargetValue, t.ThresholdGreen, t.ThresholdAmber, t.ThresholdRed,
        COALESCE(t.ThresholdDirection, d.ThresholdDirection) AS EffectiveThresholdDirection,
        t.SubmitterGuidance, t.CustomKpiName, t.CustomKpiDescription,
        COALESCE(t.CustomKpiName,        d.KPIName)        AS EffectiveKpiName,
        COALESCE(t.CustomKpiDescription, d.KPIDescription) AS EffectiveKpiDescription,
        t.IsActive, ISNULL(instances.GeneratedAssignmentCount, 0) AS GeneratedAssignmentCount,
        t.KpiPackageId, pkg.PackageName AS KpiPackageName, t.AssignmentGroupName,
        t.KpiWeight, t.ScoringMode,
        t.BandPointsGreen, t.BandPointsAmber, t.BandPointsRed,
        t.BooleanYesPoints, t.BooleanNoPoints,
        t.MultiSelectScoreRule, t.PenaliseMissingOnScore,
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
    LEFT JOIN KPI.PeriodSchedule AS sched ON sched.PeriodScheduleID = t.PeriodScheduleID
    JOIN Dim.Account            AS acct ON acct.AccountId = t.AccountId
    LEFT JOIN Dim.OrgUnit       AS ou   ON ou.OrgUnitId = t.OrgUnitId
    LEFT JOIN KPI.KpiPackage    AS pkg  ON pkg.KpiPackageId = t.KpiPackageId
    OUTER APPLY
    (
        SELECT COUNT(*) AS GeneratedAssignmentCount
        FROM KPI.Assignment AS a
        JOIN KPI.Period     AS p ON p.PeriodID = a.PeriodID
        WHERE a.KPIID = t.KPIID AND a.AccountId = t.AccountId
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

-- Restore usp_CascadeAssignmentTemplateThresholds without CategoryWeightSnapshot.
CREATE OR ALTER PROCEDURE App.usp_CascadeAssignmentTemplateThresholds
    @AssignmentTemplateID INT,
    @ActorUPN             NVARCHAR(320) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE a
    SET IsRequired             = t.IsRequired,
        TargetValue            = t.TargetValue,
        ThresholdGreen         = t.ThresholdGreen,
        ThresholdAmber         = t.ThresholdAmber,
        ThresholdRed           = t.ThresholdRed,
        ThresholdDirection     = t.ThresholdDirection,
        SubmitterGuidance      = t.SubmitterGuidance,
        KpiWeight              = t.KpiWeight,
        ScoringMode            = t.ScoringMode,
        BandPointsGreen        = t.BandPointsGreen,
        BandPointsAmber        = t.BandPointsAmber,
        BandPointsRed          = t.BandPointsRed,
        BooleanYesPoints       = t.BooleanYesPoints,
        BooleanNoPoints        = t.BooleanNoPoints,
        MultiSelectScoreRule   = t.MultiSelectScoreRule,
        PenaliseMissingOnScore = t.PenaliseMissingOnScore,
        ModifiedOnUtc          = SYSUTCDATETIME(),
        ModifiedBy             = COALESCE(@ActorUPN, SESSION_USER)
    FROM KPI.Assignment         AS a
    JOIN KPI.AssignmentTemplate AS t ON t.AssignmentTemplateID = a.AssignmentTemplateID
    WHERE t.AssignmentTemplateID = @AssignmentTemplateID
      AND NOT EXISTS (SELECT 1 FROM KPI.Submission s WHERE s.AssignmentID = a.AssignmentID);
END;
GO

-- Restore usp_AssignKpi without the CategoryWeightSnapshot param/column.
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
    DECLARE @PeriodID INT = (SELECT PeriodID FROM KPI.Period WHERE PeriodScheduleID = @PeriodScheduleID AND PeriodYear = @PeriodYear AND PeriodMonth = @PeriodMonth);
    IF @PeriodID IS NULL THROW 50113, 'Period not found for this schedule/year/month. Create the period first using App.usp_UpsertKpiPeriod.', 1;
    DECLARE @ActorPrincipalId INT = NULL;
    IF @ActorUPN IS NOT NULL SELECT @ActorPrincipalId = UserId FROM Sec.[User] WHERE UPN = @ActorUPN;
    IF @OrgUnitId IS NULL
        SET @AssignmentID = (SELECT AssignmentID FROM KPI.Assignment
            WHERE KPIID = @KPIID AND AccountId = @AccountId AND OrgUnitId IS NULL AND PeriodID = @PeriodID
              AND ((@AssignmentGroupName IS NULL AND AssignmentGroupName IS NULL) OR AssignmentGroupName = @AssignmentGroupName));
    ELSE
        SET @AssignmentID = (SELECT AssignmentID FROM KPI.Assignment
            WHERE KPIID = @KPIID AND OrgUnitId = @OrgUnitId AND PeriodID = @PeriodID
              AND ((@AssignmentGroupName IS NULL AND AssignmentGroupName IS NULL) OR AssignmentGroupName = @AssignmentGroupName));

    IF @AssignmentID IS NULL
    BEGIN
        INSERT INTO KPI.Assignment
            (KPIID, AccountId, OrgUnitId, PeriodID, AssignmentTemplateID, IsRequired,
             TargetValue, ThresholdGreen, ThresholdAmber, ThresholdRed,
             ThresholdDirection, SubmitterGuidance, AssignedByPrincipalId, AssignmentGroupName,
             KpiWeight, ScoringMode, BandPointsGreen, BandPointsAmber, BandPointsRed,
             BooleanYesPoints, BooleanNoPoints, MultiSelectScoreRule, PenaliseMissingOnScore)
        VALUES
            (@KPIID, @AccountId, @OrgUnitId, @PeriodID, @AssignmentTemplateID, @IsRequired,
             @TargetValue, @ThresholdGreen, @ThresholdAmber, @ThresholdRed,
             @ThresholdDirection, @SubmitterGuidance, @ActorPrincipalId, @AssignmentGroupName,
             @KpiWeight, @ScoringMode, @BandPointsGreen, @BandPointsAmber, @BandPointsRed,
             @BooleanYesPoints, @BooleanNoPoints, @MultiSelectScoreRule, @PenaliseMissingOnScore);
        SET @AssignmentID = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE KPI.Assignment
        SET IsRequired = @IsRequired, TargetValue = @TargetValue,
            ThresholdGreen = @ThresholdGreen, ThresholdAmber = @ThresholdAmber, ThresholdRed = @ThresholdRed,
            ThresholdDirection = @ThresholdDirection, SubmitterGuidance = @SubmitterGuidance,
            KpiWeight = @KpiWeight, ScoringMode = @ScoringMode,
            BandPointsGreen = @BandPointsGreen, BandPointsAmber = @BandPointsAmber, BandPointsRed = @BandPointsRed,
            BooleanYesPoints = @BooleanYesPoints, BooleanNoPoints = @BooleanNoPoints,
            MultiSelectScoreRule = @MultiSelectScoreRule, PenaliseMissingOnScore = @PenaliseMissingOnScore,
            IsActive = 1, ModifiedOnUtc = SYSUTCDATETIME(), ModifiedBy = COALESCE(@ActorUPN, SESSION_USER)
        WHERE AssignmentID = @AssignmentID;
    END
END;
GO

-- Restore usp_UpsertKpiAssignmentTemplate without CategoryWeightSnapshot snippet.
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
    BEGIN SET @StartPeriodYear = YEAR(@ScheduleStartDate); SET @StartPeriodMonth = MONTH(@ScheduleStartDate); END
    IF @EndPeriodYear IS NULL AND @EndPeriodMonth IS NULL AND @ScheduleEndDate IS NOT NULL
    BEGIN SET @EndPeriodYear = YEAR(@ScheduleEndDate); SET @EndPeriodMonth = MONTH(@ScheduleEndDate); END
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
        INSERT INTO KPI.AssignmentTemplate
            (KPIID, PeriodScheduleID, AccountId, OrgUnitId, StartPeriodYear, StartPeriodMonth, EndPeriodYear, EndPeriodMonth,
             IsRequired, TargetValue, ThresholdGreen, ThresholdAmber, ThresholdRed, ThresholdDirection, SubmitterGuidance,
             CustomKpiName, CustomKpiDescription, KpiPackageId, AssignmentGroupName,
             KpiWeight, ScoringMode, BandPointsGreen, BandPointsAmber, BandPointsRed,
             BooleanYesPoints, BooleanNoPoints, MultiSelectScoreRule, PenaliseMissingOnScore)
        VALUES
            (@KPIID, @PeriodScheduleID, @AccountId, @OrgUnitId, @StartPeriodYear, @StartPeriodMonth, @EndPeriodYear, @EndPeriodMonth,
             @IsRequired, @TargetValue, @ThresholdGreen, @ThresholdAmber, @ThresholdRed, @ThresholdDirection, @SubmitterGuidance,
             @CustomKpiName, @CustomKpiDescription, @KpiPackageId, @AssignmentGroupName,
             COALESCE(@KpiWeight, 1.0), COALESCE(@ScoringMode, 'Band'),
             COALESCE(@BandPointsGreen, 100), COALESCE(@BandPointsAmber, 50), COALESCE(@BandPointsRed, 0),
             @BooleanYesPoints, @BooleanNoPoints, @MultiSelectScoreRule,
             COALESCE(@PenaliseMissingOnScore, @IsRequired));
        SET @AssignmentTemplateID = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE KPI.AssignmentTemplate
        SET PeriodScheduleID = @PeriodScheduleID,
            StartPeriodYear = @StartPeriodYear, StartPeriodMonth = @StartPeriodMonth,
            EndPeriodYear = @EndPeriodYear, EndPeriodMonth = @EndPeriodMonth,
            IsRequired = @IsRequired, TargetValue = @TargetValue,
            ThresholdGreen = @ThresholdGreen, ThresholdAmber = @ThresholdAmber, ThresholdRed = @ThresholdRed,
            ThresholdDirection = @ThresholdDirection, SubmitterGuidance = @SubmitterGuidance,
            CustomKpiName = @CustomKpiName, CustomKpiDescription = @CustomKpiDescription, KpiPackageId = @KpiPackageId,
            KpiWeight = COALESCE(@KpiWeight, KpiWeight),
            ScoringMode = COALESCE(@ScoringMode, ScoringMode),
            BandPointsGreen = COALESCE(@BandPointsGreen, BandPointsGreen),
            BandPointsAmber = COALESCE(@BandPointsAmber, BandPointsAmber),
            BandPointsRed = COALESCE(@BandPointsRed, BandPointsRed),
            BooleanYesPoints = @BooleanYesPoints, BooleanNoPoints = @BooleanNoPoints,
            MultiSelectScoreRule = @MultiSelectScoreRule,
            PenaliseMissingOnScore = COALESCE(@PenaliseMissingOnScore, PenaliseMissingOnScore),
            IsActive = 1, ModifiedOnUtc = SYSUTCDATETIME(), ModifiedBy = COALESCE(@ActorUPN, SESSION_USER)
        WHERE AssignmentTemplateID = @AssignmentTemplateID;
    END

    IF @OptionPoints IS NOT NULL
    BEGIN
        DELETE FROM KPI.AssignmentTemplateDropDownOption WHERE AssignmentTemplateID = @AssignmentTemplateID;
        INSERT INTO KPI.AssignmentTemplateDropDownOption (AssignmentTemplateID, OptionValue, SortOrder, Points)
        SELECT @AssignmentTemplateID,
            JSON_VALUE(j.[value], '$.value'),
            ISNULL(TRY_CAST(JSON_VALUE(j.[value], '$.sortOrder') AS INT), CAST(j.[key] AS INT)),
            ISNULL(TRY_CAST(JSON_VALUE(j.[value], '$.points')    AS DECIMAL(9,4)), 0)
        FROM OPENJSON(@OptionPoints) AS j
        WHERE JSON_VALUE(j.[value], '$.value') IS NOT NULL;
    END
END;
GO

-- Restore usp_MaterializeKpiAssignmentTemplates without CategoryWeightSnapshot.
CREATE OR ALTER PROCEDURE App.usp_MaterializeKpiAssignmentTemplates
    @AssignmentTemplateID   INT           = NULL,
    @PeriodScheduleIDFilter INT           = NULL,
    @ActorUPN               NVARCHAR(320) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE
        @CurrentTemplateId INT, @TemplateKpiCode NVARCHAR(50), @TemplateScheduleId INT,
        @TemplateScheduleStartDate DATE, @TemplateScheduleEndDate DATE,
        @TemplateAccountCode NVARCHAR(50), @TemplateOrgUnitCode NVARCHAR(50),
        @TemplateOrgUnitType NVARCHAR(20),
        @TemplateStartYear SMALLINT, @TemplateStartMonth TINYINT,
        @TemplateEndYear SMALLINT, @TemplateEndMonth TINYINT,
        @TemplateIsRequired BIT, @TemplateTargetValue DECIMAL(18,4),
        @TemplateThresholdGreen DECIMAL(18,4), @TemplateThresholdAmber DECIMAL(18,4), @TemplateThresholdRed DECIMAL(18,4),
        @TemplateThresholdDirection NVARCHAR(10), @TemplateSubmitterGuidance NVARCHAR(1000), @TemplateGroupName NVARCHAR(100),
        @TemplateKpiWeight DECIMAL(9,4), @TemplateScoringMode NVARCHAR(10),
        @TemplateBandG DECIMAL(9,4), @TemplateBandA DECIMAL(9,4), @TemplateBandR DECIMAL(9,4),
        @TemplateBoolY DECIMAL(9,4), @TemplateBoolN DECIMAL(9,4),
        @TemplateMSRule NVARCHAR(10), @TemplatePenaliseMissing BIT,
        @SiteOrgUnitCode NVARCHAR(50);

    DECLARE template_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT t.AssignmentTemplateID, d.KPICode, t.PeriodScheduleID, sched.StartDate, sched.EndDate,
               acct.AccountCode, ou.OrgUnitCode, COALESCE(ou.OrgUnitType, 'Site'),
               t.StartPeriodYear, t.StartPeriodMonth, t.EndPeriodYear, t.EndPeriodMonth,
               t.IsRequired, t.TargetValue, t.ThresholdGreen, t.ThresholdAmber, t.ThresholdRed,
               t.ThresholdDirection, t.SubmitterGuidance, t.AssignmentGroupName,
               t.KpiWeight, t.ScoringMode, t.BandPointsGreen, t.BandPointsAmber, t.BandPointsRed,
               t.BooleanYesPoints, t.BooleanNoPoints, t.MultiSelectScoreRule, t.PenaliseMissingOnScore
        FROM KPI.AssignmentTemplate AS t
        JOIN KPI.Definition         AS d     ON d.KPIID              = t.KPIID
        JOIN KPI.PeriodSchedule     AS sched ON sched.PeriodScheduleID = t.PeriodScheduleID
        JOIN Dim.Account            AS acct  ON acct.AccountId       = t.AccountId
        LEFT JOIN Dim.OrgUnit       AS ou    ON ou.OrgUnitId         = t.OrgUnitId
        WHERE t.IsActive = 1 AND sched.IsActive = 1
          AND (@AssignmentTemplateID   IS NULL OR t.AssignmentTemplateID = @AssignmentTemplateID)
          AND (@PeriodScheduleIDFilter IS NULL OR t.PeriodScheduleID    = @PeriodScheduleIDFilter)
        ORDER BY t.AssignmentTemplateID;

    OPEN template_cursor;
    FETCH NEXT FROM template_cursor INTO
        @CurrentTemplateId, @TemplateKpiCode, @TemplateScheduleId, @TemplateScheduleStartDate, @TemplateScheduleEndDate,
        @TemplateAccountCode, @TemplateOrgUnitCode, @TemplateOrgUnitType,
        @TemplateStartYear, @TemplateStartMonth, @TemplateEndYear, @TemplateEndMonth, @TemplateIsRequired,
        @TemplateTargetValue, @TemplateThresholdGreen, @TemplateThresholdAmber, @TemplateThresholdRed,
        @TemplateThresholdDirection, @TemplateSubmitterGuidance, @TemplateGroupName,
        @TemplateKpiWeight, @TemplateScoringMode, @TemplateBandG, @TemplateBandA, @TemplateBandR,
        @TemplateBoolY, @TemplateBoolN, @TemplateMSRule, @TemplatePenaliseMissing;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @CurrentPeriodYear SMALLINT, @CurrentPeriodMonth TINYINT;
        DECLARE period_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT PeriodYear, PeriodMonth FROM KPI.Period
            WHERE PeriodScheduleID = @TemplateScheduleId
              AND (PeriodYear * 100 + PeriodMonth) >= (
                    COALESCE(@TemplateStartYear, YEAR(@TemplateScheduleStartDate)) * 100
                    + COALESCE(@TemplateStartMonth, MONTH(@TemplateScheduleStartDate)))
              AND (@TemplateEndYear IS NULL
                   OR (PeriodYear * 100 + PeriodMonth) <= (@TemplateEndYear * 100 + @TemplateEndMonth))
            ORDER BY PeriodYear, PeriodMonth;
        OPEN period_cursor;
        FETCH NEXT FROM period_cursor INTO @CurrentPeriodYear, @CurrentPeriodMonth;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            DECLARE @GeneratedAssignmentId INT;
            IF @TemplateOrgUnitCode IS NULL
            BEGIN
                DECLARE site_cursor CURSOR LOCAL FAST_FORWARD FOR
                    SELECT ou.OrgUnitCode FROM Dim.OrgUnit AS ou
                    JOIN Dim.Account AS acct ON acct.AccountId = ou.AccountId
                    WHERE acct.AccountCode = @TemplateAccountCode AND ou.OrgUnitType = 'Site' AND ou.IsActive = 1;
                OPEN site_cursor;
                FETCH NEXT FROM site_cursor INTO @SiteOrgUnitCode;
                WHILE @@FETCH_STATUS = 0
                BEGIN
                    SET @GeneratedAssignmentId = NULL;
                    EXEC App.usp_AssignKpi
                        @KPICode = @TemplateKpiCode, @AccountCode = @TemplateAccountCode,
                        @OrgUnitCode = @SiteOrgUnitCode, @OrgUnitType = 'Site',
                        @PeriodScheduleID = @TemplateScheduleId,
                        @PeriodYear = @CurrentPeriodYear, @PeriodMonth = @CurrentPeriodMonth,
                        @AssignmentTemplateID = @CurrentTemplateId,
                        @IsRequired = @TemplateIsRequired, @TargetValue = @TemplateTargetValue,
                        @ThresholdGreen = @TemplateThresholdGreen, @ThresholdAmber = @TemplateThresholdAmber,
                        @ThresholdRed = @TemplateThresholdRed, @ThresholdDirection = @TemplateThresholdDirection,
                        @SubmitterGuidance = @TemplateSubmitterGuidance, @AssignmentGroupName = @TemplateGroupName,
                        @KpiWeight = @TemplateKpiWeight, @ScoringMode = @TemplateScoringMode,
                        @BandPointsGreen = @TemplateBandG, @BandPointsAmber = @TemplateBandA, @BandPointsRed = @TemplateBandR,
                        @BooleanYesPoints = @TemplateBoolY, @BooleanNoPoints = @TemplateBoolN,
                        @MultiSelectScoreRule = @TemplateMSRule, @PenaliseMissingOnScore = @TemplatePenaliseMissing,
                        @ActorUPN = @ActorUPN, @AssignmentID = @GeneratedAssignmentId OUTPUT;
                    FETCH NEXT FROM site_cursor INTO @SiteOrgUnitCode;
                END
                CLOSE site_cursor; DEALLOCATE site_cursor;
            END
            ELSE
            BEGIN
                SET @GeneratedAssignmentId = NULL;
                EXEC App.usp_AssignKpi
                    @KPICode = @TemplateKpiCode, @AccountCode = @TemplateAccountCode,
                    @OrgUnitCode = @TemplateOrgUnitCode, @OrgUnitType = @TemplateOrgUnitType,
                    @PeriodScheduleID = @TemplateScheduleId,
                    @PeriodYear = @CurrentPeriodYear, @PeriodMonth = @CurrentPeriodMonth,
                    @AssignmentTemplateID = @CurrentTemplateId,
                    @IsRequired = @TemplateIsRequired, @TargetValue = @TemplateTargetValue,
                    @ThresholdGreen = @TemplateThresholdGreen, @ThresholdAmber = @TemplateThresholdAmber,
                    @ThresholdRed = @TemplateThresholdRed, @ThresholdDirection = @TemplateThresholdDirection,
                    @SubmitterGuidance = @TemplateSubmitterGuidance, @AssignmentGroupName = @TemplateGroupName,
                    @KpiWeight = @TemplateKpiWeight, @ScoringMode = @TemplateScoringMode,
                    @BandPointsGreen = @TemplateBandG, @BandPointsAmber = @TemplateBandA, @BandPointsRed = @TemplateBandR,
                    @BooleanYesPoints = @TemplateBoolY, @BooleanNoPoints = @TemplateBoolN,
                    @MultiSelectScoreRule = @TemplateMSRule, @PenaliseMissingOnScore = @TemplatePenaliseMissing,
                    @ActorUPN = @ActorUPN, @AssignmentID = @GeneratedAssignmentId OUTPUT;
            END
            FETCH NEXT FROM period_cursor INTO @CurrentPeriodYear, @CurrentPeriodMonth;
        END
        CLOSE period_cursor; DEALLOCATE period_cursor;
        FETCH NEXT FROM template_cursor INTO
            @CurrentTemplateId, @TemplateKpiCode, @TemplateScheduleId, @TemplateScheduleStartDate, @TemplateScheduleEndDate,
            @TemplateAccountCode, @TemplateOrgUnitCode, @TemplateOrgUnitType,
            @TemplateStartYear, @TemplateStartMonth, @TemplateEndYear, @TemplateEndMonth, @TemplateIsRequired,
            @TemplateTargetValue, @TemplateThresholdGreen, @TemplateThresholdAmber, @TemplateThresholdRed,
            @TemplateThresholdDirection, @TemplateSubmitterGuidance, @TemplateGroupName,
            @TemplateKpiWeight, @TemplateScoringMode, @TemplateBandG, @TemplateBandA, @TemplateBandR,
            @TemplateBoolY, @TemplateBoolN, @TemplateMSRule, @TemplatePenaliseMissing;
    END
    CLOSE template_cursor; DEALLOCATE template_cursor;
END;
GO

IF COL_LENGTH('KPI.Assignment', 'CategoryWeightSnapshot') IS NOT NULL
    ALTER TABLE KPI.Assignment DROP COLUMN CategoryWeightSnapshot;
GO

IF COL_LENGTH('KPI.AssignmentTemplate', 'CategoryWeightSnapshot') IS NOT NULL
    ALTER TABLE KPI.AssignmentTemplate DROP COLUMN CategoryWeightSnapshot;
GO

IF COL_LENGTH('KPI.Assignment', 'CategoryWeightSnapshot') IS NOT NULL
    ALTER TABLE KPI.Assignment DROP COLUMN CategoryWeightSnapshot;
GO

IF COL_LENGTH('KPI.AssignmentTemplate', 'CategoryWeightSnapshot') IS NOT NULL
    ALTER TABLE KPI.AssignmentTemplate DROP COLUMN CategoryWeightSnapshot;
GO
