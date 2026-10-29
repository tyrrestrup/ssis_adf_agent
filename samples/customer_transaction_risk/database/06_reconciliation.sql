:setvar DatabaseName "SsisAdfCustomerDemo"
:setvar BusinessDate "2026-01-14"

USE [$(DatabaseName)];
GO

DECLARE @BusinessDate date = CONVERT(date, '$(BusinessDate)');

SELECT
    CheckName = N'Classified row count',
    SsisValue = CONVERT(nvarchar(100), SsisValue),
    AdfValue = CONVERT(nvarchar(100), AdfValue),
    Difference = CONVERT(nvarchar(100), SsisValue - AdfValue)
FROM
(
    SELECT
        SsisValue = (
            SELECT COUNT(*) FROM ssisout.TransactionRiskClassified
            WHERE BusinessDate = @BusinessDate
        ),
        AdfValue = (
            SELECT COUNT(*) FROM adfout.TransactionRiskClassified
            WHERE BusinessDate = @BusinessDate
        )
) Counts
UNION ALL
SELECT N'Exception row count', CONVERT(nvarchar(100), SsisValue),
       CONVERT(nvarchar(100), AdfValue), CONVERT(nvarchar(100), SsisValue - AdfValue)
FROM
(
    SELECT
        SsisValue = (
            SELECT COUNT(*) FROM ssisout.TransactionRiskException
            WHERE BusinessDate = @BusinessDate
        ),
        AdfValue = (
            SELECT COUNT(*) FROM adfout.TransactionRiskException
            WHERE BusinessDate = @BusinessDate
        )
) Counts
UNION ALL
SELECT N'Classified amount', CONVERT(nvarchar(100), SsisValue),
       CONVERT(nvarchar(100), AdfValue), CONVERT(nvarchar(100), SsisValue - AdfValue)
FROM
(
    SELECT
        SsisValue = COALESCE((
            SELECT SUM(Amount) FROM ssisout.TransactionRiskClassified
            WHERE BusinessDate = @BusinessDate
        ), 0),
        AdfValue = COALESCE((
            SELECT SUM(Amount) FROM adfout.TransactionRiskClassified
            WHERE BusinessDate = @BusinessDate
        ), 0)
) Totals
UNION ALL
SELECT N'Customer summary row count', CONVERT(nvarchar(100), SsisValue),
       CONVERT(nvarchar(100), AdfValue), CONVERT(nvarchar(100), SsisValue - AdfValue)
FROM
(
    SELECT
        SsisValue = (
            SELECT COUNT(*) FROM ssisout.DailyCustomerRiskSummary
            WHERE BusinessDate = @BusinessDate
        ),
        AdfValue = (
            SELECT COUNT(*) FROM adfout.DailyCustomerRiskSummary
            WHERE BusinessDate = @BusinessDate
        )
) Counts
UNION ALL
SELECT N'Customer summary amount', CONVERT(nvarchar(100), SsisValue),
       CONVERT(nvarchar(100), AdfValue), CONVERT(nvarchar(100), SsisValue - AdfValue)
FROM
(
    SELECT
        SsisValue = COALESCE((
            SELECT SUM(TotalAmount) FROM ssisout.DailyCustomerRiskSummary
            WHERE BusinessDate = @BusinessDate
        ), 0),
        AdfValue = COALESCE((
            SELECT SUM(TotalAmount) FROM adfout.DailyCustomerRiskSummary
            WHERE BusinessDate = @BusinessDate
        ), 0)
) Totals;

SELECT N'SSIS_NOT_ADF_CLASSIFIED' AS DifferenceType, TransactionId
FROM ssisout.TransactionRiskClassified
WHERE BusinessDate = @BusinessDate
EXCEPT
SELECT N'SSIS_NOT_ADF_CLASSIFIED', TransactionId
FROM adfout.TransactionRiskClassified
WHERE BusinessDate = @BusinessDate;

SELECT N'ADF_NOT_SSIS_CLASSIFIED' AS DifferenceType, TransactionId
FROM adfout.TransactionRiskClassified
WHERE BusinessDate = @BusinessDate
EXCEPT
SELECT N'ADF_NOT_SSIS_CLASSIFIED', TransactionId
FROM ssisout.TransactionRiskClassified
WHERE BusinessDate = @BusinessDate;

SELECT N'SSIS_NOT_ADF_EXCEPTION' AS DifferenceType, TransactionId
FROM ssisout.TransactionRiskException
WHERE BusinessDate = @BusinessDate
EXCEPT
SELECT N'SSIS_NOT_ADF_EXCEPTION', TransactionId
FROM adfout.TransactionRiskException
WHERE BusinessDate = @BusinessDate;

SELECT N'ADF_NOT_SSIS_EXCEPTION' AS DifferenceType, TransactionId
FROM adfout.TransactionRiskException
WHERE BusinessDate = @BusinessDate
EXCEPT
SELECT N'ADF_NOT_SSIS_EXCEPTION', TransactionId
FROM ssisout.TransactionRiskException
WHERE BusinessDate = @BusinessDate;

SELECT N'SSIS_NOT_ADF_SUMMARY' AS DifferenceType, CustomerId, RiskClass
FROM ssisout.DailyCustomerRiskSummary
WHERE BusinessDate = @BusinessDate
EXCEPT
SELECT N'SSIS_NOT_ADF_SUMMARY', CustomerId, RiskClass
FROM adfout.DailyCustomerRiskSummary
WHERE BusinessDate = @BusinessDate;

SELECT N'ADF_NOT_SSIS_SUMMARY' AS DifferenceType, CustomerId, RiskClass
FROM adfout.DailyCustomerRiskSummary
WHERE BusinessDate = @BusinessDate
EXCEPT
SELECT N'ADF_NOT_SSIS_SUMMARY', CustomerId, RiskClass
FROM ssisout.DailyCustomerRiskSummary
WHERE BusinessDate = @BusinessDate;

WITH SsisRows AS
(
    SELECT TransactionId,
           HASHBYTES('SHA2_256', CONCAT_WS('|', CustomerId, BusinessDate, Amount,
               OriginCountryCode, CountryRiskScore, CombinedRiskScore, RiskClass)) AS RowHash
    FROM ssisout.TransactionRiskClassified
    WHERE BusinessDate = @BusinessDate
),
AdfRows AS
(
    SELECT TransactionId,
           HASHBYTES('SHA2_256', CONCAT_WS('|', CustomerId, BusinessDate, Amount,
               OriginCountryCode, CountryRiskScore, CombinedRiskScore, RiskClass)) AS RowHash
    FROM adfout.TransactionRiskClassified
    WHERE BusinessDate = @BusinessDate
)
SELECT COALESCE(s.TransactionId, a.TransactionId) AS TransactionId,
       s.RowHash AS SsisHash,
       a.RowHash AS AdfHash
FROM SsisRows s
FULL OUTER JOIN AdfRows a ON a.TransactionId = s.TransactionId
WHERE s.RowHash IS NULL OR a.RowHash IS NULL OR s.RowHash <> a.RowHash;

WITH SsisRows AS
(
    SELECT CustomerId, RiskClass,
           HASHBYTES('SHA2_256', CONCAT_WS('|', TransactionCount, TotalAmount)) AS RowHash
    FROM ssisout.DailyCustomerRiskSummary
    WHERE BusinessDate = @BusinessDate
),
AdfRows AS
(
    SELECT CustomerId, RiskClass,
           HASHBYTES('SHA2_256', CONCAT_WS('|', TransactionCount, TotalAmount)) AS RowHash
    FROM adfout.DailyCustomerRiskSummary
    WHERE BusinessDate = @BusinessDate
)
SELECT COALESCE(s.CustomerId, a.CustomerId) AS CustomerId,
       COALESCE(s.RiskClass, a.RiskClass) AS RiskClass,
       s.RowHash AS SsisHash,
       a.RowHash AS AdfHash
FROM SsisRows s
FULL OUTER JOIN AdfRows a
    ON a.CustomerId = s.CustomerId
   AND a.RiskClass = s.RiskClass
WHERE s.RowHash IS NULL OR a.RowHash IS NULL OR s.RowHash <> a.RowHash;
GO
