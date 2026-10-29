:setvar DatabaseName "SsisAdfCustomerDemo"

USE [$(DatabaseName)];
GO

MERGE ref.CountryRisk AS target
USING (VALUES
    (N'US', N'United States', 5, N'LOW', 1),
    (N'CA', N'Canada', 10, N'LOW', 1),
    (N'GB', N'United Kingdom', 15, N'MEDIUM', 1),
    (N'IR', N'Iran', 80, N'HIGH', 1)
) AS source (CountryCode, CountryName, CountryRiskScore, RiskTier, IsActive)
ON target.CountryCode = source.CountryCode
WHEN MATCHED THEN UPDATE SET
    CountryName = source.CountryName,
    CountryRiskScore = source.CountryRiskScore,
    RiskTier = source.RiskTier,
    IsActive = source.IsActive
WHEN NOT MATCHED THEN INSERT
    (CountryCode, CountryName, CountryRiskScore, RiskTier, IsActive)
VALUES
    (source.CountryCode, source.CountryName, source.CountryRiskScore,
     source.RiskTier, source.IsActive);
GO

MERGE src.Customer AS target
USING (VALUES
    (1, N'Alice Carter', 10, 0, 1),
    (2, N'Bob Singh', 20, 1, 1),
    (3, N'Carol Diaz', 35, 0, 1),
    (4, N'Diego Morgan', 15, 0, 1)
) AS source
    (CustomerId, CustomerName, CustomerRiskScore, RequiresManualReview, IsActive)
ON target.CustomerId = source.CustomerId
WHEN MATCHED THEN UPDATE SET
    CustomerName = source.CustomerName,
    CustomerRiskScore = source.CustomerRiskScore,
    RequiresManualReview = source.RequiresManualReview,
    IsActive = source.IsActive
WHEN NOT MATCHED THEN INSERT
    (CustomerId, CustomerName, CustomerRiskScore, RequiresManualReview, IsActive)
VALUES
    (source.CustomerId, source.CustomerName, source.CustomerRiskScore,
     source.RequiresManualReview, source.IsActive);
GO

MERGE src.Account AS target
USING (VALUES
    (101, 1, N'CHK-000101'),
    (102, 2, N'CHK-000102'),
    (103, 3, N'CHK-000103'),
    (104, 4, N'CHK-000104')
) AS source (AccountId, CustomerId, AccountNumber)
ON target.AccountId = source.AccountId
WHEN MATCHED THEN UPDATE SET
    CustomerId = source.CustomerId,
    AccountNumber = source.AccountNumber
WHEN NOT MATCHED THEN INSERT (AccountId, CustomerId, AccountNumber)
VALUES (source.AccountId, source.CustomerId, source.AccountNumber);
GO
