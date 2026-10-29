:setvar DatabaseName "SsisAdfCustomerDemo"

USE [$(DatabaseName)];
GO

MERGE src.CustomerTransaction AS target
USING (VALUES
    (1001, 101, CONVERT(date, '2026-01-14'),  250.00, N'USD', N'US', N'CARD', N'POSTED'),
    (1002, 101, CONVERT(date, '2026-01-14'), 15000.00, N'USD', N'US', N'WIRE', N'POSTED'),
    (1003, 102, CONVERT(date, '2026-01-14'), 4000.00, N'USD', N'GB', N'ACH', N'POSTED'),
    (1004, 103, CONVERT(date, '2026-01-14'), 7000.00, N'USD', N'IR', N'WIRE', N'POSTED'),
    (1005, 103, CONVERT(date, '2026-01-14'), 20000.00, N'USD', N'IR', N'WIRE', N'POSTED'),
    (1006, 104, CONVERT(date, '2026-01-14'), 1200.00, N'USD', N'ZZ', N'ACH', N'POSTED'),
    (1007, 102, CONVERT(date, '2026-01-14'),  800.00, N'USD', N'US', N'CARD', N'POSTED'),
    (1008, 101, CONVERT(date, '2026-01-14'), 3000.00, N'USD', N'CA', N'ACH', N'POSTED'),
    (1009, 101, CONVERT(date, '2026-01-13'), 9999.00, N'USD', N'US', N'WIRE', N'POSTED'),
    (1010, 101, CONVERT(date, '2026-01-14'), 5000.00, N'USD', N'US', N'WIRE', N'REVERSED')
) AS source
    (TransactionId, AccountId, BusinessDate, Amount, CurrencyCode,
     OriginCountryCode, TransactionType, Status)
ON target.TransactionId = source.TransactionId
WHEN MATCHED THEN UPDATE SET
    AccountId = source.AccountId,
    BusinessDate = source.BusinessDate,
    Amount = source.Amount,
    CurrencyCode = source.CurrencyCode,
    OriginCountryCode = source.OriginCountryCode,
    TransactionType = source.TransactionType,
    Status = source.Status
WHEN NOT MATCHED THEN INSERT
    (TransactionId, AccountId, BusinessDate, Amount, CurrencyCode,
     OriginCountryCode, TransactionType, Status)
VALUES
    (source.TransactionId, source.AccountId, source.BusinessDate, source.Amount,
     source.CurrencyCode, source.OriginCountryCode, source.TransactionType,
     source.Status);
GO
