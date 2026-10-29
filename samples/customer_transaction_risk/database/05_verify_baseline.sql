:setvar DatabaseName "SsisAdfCustomerDemo"
:setvar BusinessDate "2026-01-14"

USE [$(DatabaseName)];
GO

DECLARE @BusinessDate date = CONVERT(date, '$(BusinessDate)');

DECLARE @InputCount int =
(
    SELECT COUNT(*)
    FROM src.CustomerTransaction
    WHERE BusinessDate = @BusinessDate AND Status = N'POSTED'
);
DECLARE @ClassifiedCount int =
(
    SELECT COUNT(*)
    FROM ssisout.TransactionRiskClassified
    WHERE BusinessDate = @BusinessDate
);
DECLARE @ExceptionCount int =
(
    SELECT COUNT(*)
    FROM ssisout.TransactionRiskException
    WHERE BusinessDate = @BusinessDate
);
DECLARE @InputAmount decimal(19,2) =
(
    SELECT SUM(Amount)
    FROM src.CustomerTransaction
    WHERE BusinessDate = @BusinessDate AND Status = N'POSTED'
);
DECLARE @ClassifiedAmount decimal(19,2) =
(
    SELECT SUM(Amount)
    FROM ssisout.TransactionRiskClassified
    WHERE BusinessDate = @BusinessDate
);
DECLARE @ExceptionAmount decimal(19,2) =
(
    SELECT SUM(Amount)
    FROM ssisout.TransactionRiskException
    WHERE BusinessDate = @BusinessDate
);

SELECT
    @InputCount AS InputTransactionCount,
    @ClassifiedCount AS ClassifiedTransactionCount,
    @ExceptionCount AS ExceptionTransactionCount,
    @InputAmount AS InputAmount,
    @ClassifiedAmount AS ClassifiedAmount,
    @ExceptionAmount AS ExceptionAmount;

SELECT RiskClass, COUNT(*) AS TransactionCount, SUM(Amount) AS TotalAmount
FROM ssisout.TransactionRiskClassified
WHERE BusinessDate = @BusinessDate
GROUP BY RiskClass
ORDER BY RiskClass;

SELECT TransactionId
FROM ssisout.TransactionRiskException
WHERE BusinessDate = @BusinessDate
ORDER BY TransactionId;

SELECT CustomerId, RiskClass, TransactionCount, TotalAmount
FROM ssisout.DailyCustomerRiskSummary
WHERE BusinessDate = @BusinessDate
ORDER BY CustomerId, RiskClass;

IF @InputCount <> 8
   OR @ClassifiedCount <> 7
   OR @ExceptionCount <> 1
   OR @InputAmount <> 51250.00
   OR @ClassifiedAmount <> 50050.00
   OR @ExceptionAmount <> 1200.00
    THROW 51010, 'Baseline totals do not match expected/customer baseline.json.', 1;

IF EXISTS
(
    SELECT Expected.TransactionId
    FROM (VALUES (1002), (1004), (1005)) Expected(TransactionId)
    EXCEPT
    SELECT TransactionId
    FROM ssisout.TransactionRiskClassified
    WHERE BusinessDate = @BusinessDate AND RiskClass = N'HIGH'
)
OR EXISTS
(
    SELECT TransactionId
    FROM ssisout.TransactionRiskClassified
    WHERE BusinessDate = @BusinessDate AND RiskClass = N'HIGH'
    EXCEPT
    SELECT Expected.TransactionId
    FROM (VALUES (1002), (1004), (1005)) Expected(TransactionId)
)
    THROW 51011, 'High-risk transaction set does not match the baseline.', 1;

IF NOT EXISTS
(
    SELECT 1
    FROM ssisout.TransactionRiskException
    WHERE BusinessDate = @BusinessDate
      AND TransactionId = 1006
      AND ExceptionReason = N'COUNTRY_RISK_NOT_FOUND'
)
    THROW 51012, 'Lookup no-match transaction 1006 was not preserved.', 1;

PRINT N'PASS: SSIS output matches the fixed customer baseline.';
GO
