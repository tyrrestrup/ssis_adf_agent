:setvar DatabaseName "SsisAdfCustomerDemo"
:setvar BusinessDate "2026-01-14"

USE [$(DatabaseName)];
GO

DECLARE @BusinessDate date = CONVERT(date, '$(BusinessDate)');
DECLARE @BatchId bigint;

EXEC audit.usp_StartPackageRun
    @PackageName = N'CRM_DailyTransaction_Risk_REFERENCE_SQL',
    @BusinessDate = @BusinessDate,
    @ExecutionId = NULL,
    @BatchId = @BatchId OUTPUT;

EXEC audit.usp_ResetPackageOutputs @BusinessDate = @BusinessDate;

WITH Enriched AS
(
    SELECT
        t.TransactionId,
        t.AccountId,
        a.CustomerId,
        t.BusinessDate,
        t.Amount,
        t.CurrencyCode,
        t.OriginCountryCode,
        t.TransactionType,
        c.CustomerRiskScore,
        c.RequiresManualReview,
        cr.CountryRiskScore,
        cr.RiskTier AS CountryRiskTier,
        CASE WHEN t.Amount >= 10000 THEN 50
             WHEN t.Amount >= 5000 THEN 20
             ELSE 0 END AS AmountRiskScore
    FROM src.CustomerTransaction t
    JOIN src.Account a ON a.AccountId = t.AccountId
    JOIN src.Customer c ON c.CustomerId = a.CustomerId
    LEFT JOIN ref.CountryRisk cr
      ON cr.CountryCode = t.OriginCountryCode
     AND cr.IsActive = 1
    WHERE t.BusinessDate = @BusinessDate
      AND t.Status = N'POSTED'
)
INSERT ssisout.TransactionRiskClassified
(
    TransactionId, AccountId, CustomerId, BusinessDate, Amount, CurrencyCode,
    OriginCountryCode, TransactionType, CustomerRiskScore, RequiresManualReview,
    CountryRiskScore, CountryRiskTier, AmountRiskScore, CombinedRiskScore,
    BatchId, LoadUtc, RiskClass
)
SELECT
    TransactionId, AccountId, CustomerId, BusinessDate, Amount, CurrencyCode,
    OriginCountryCode, TransactionType, CustomerRiskScore, RequiresManualReview,
    CountryRiskScore, CountryRiskTier, AmountRiskScore,
    CustomerRiskScore + CountryRiskScore + AmountRiskScore,
    @BatchId, SYSUTCDATETIME(),
    CASE
        WHEN Amount >= 10000
          OR CountryRiskScore >= 70
          OR CustomerRiskScore + CountryRiskScore + AmountRiskScore >= 100
            THEN N'HIGH'
        WHEN RequiresManualReview = 1
          OR CustomerRiskScore + CountryRiskScore + AmountRiskScore >= 50
            THEN N'MANUAL_REVIEW'
        ELSE N'STANDARD'
    END
FROM Enriched
WHERE CountryRiskScore IS NOT NULL;

INSERT ssisout.TransactionRiskException
(
    TransactionId, AccountId, CustomerId, BusinessDate, Amount, CurrencyCode,
    OriginCountryCode, TransactionType, CustomerRiskScore, RequiresManualReview,
    ExceptionReason, BatchId, LoadUtc
)
SELECT
    t.TransactionId, t.AccountId, a.CustomerId, t.BusinessDate, t.Amount,
    t.CurrencyCode, t.OriginCountryCode, t.TransactionType,
    c.CustomerRiskScore, c.RequiresManualReview,
    N'COUNTRY_RISK_NOT_FOUND', @BatchId, SYSUTCDATETIME()
FROM src.CustomerTransaction t
JOIN src.Account a ON a.AccountId = t.AccountId
JOIN src.Customer c ON c.CustomerId = a.CustomerId
LEFT JOIN ref.CountryRisk cr
  ON cr.CountryCode = t.OriginCountryCode
 AND cr.IsActive = 1
WHERE t.BusinessDate = @BusinessDate
  AND t.Status = N'POSTED'
  AND cr.CountryCode IS NULL;

INSERT ssisout.CustomerRiskDailyStage
    (CustomerId, BusinessDate, RiskClass, TransactionCount, TotalAmount)
SELECT CustomerId, BusinessDate, RiskClass, COUNT_BIG(*), SUM(Amount)
FROM ssisout.TransactionRiskClassified
WHERE BusinessDate = @BusinessDate
GROUP BY CustomerId, BusinessDate, RiskClass;

EXEC ssisout.usp_MergeDailyCustomerRiskSummary
    @BusinessDate = @BusinessDate,
    @BatchId = @BatchId;

EXEC audit.usp_CompletePackageRun
    @BatchId = @BatchId,
    @RowsExtracted = 8,
    @RowsLoaded = 7,
    @RowsRejected = 1;

PRINT N'Expected SSIS output was materialized from the documented reference rules.';
PRINT N'This is a demo aid, not evidence that the SSIS runtime executed the package.';
GO
