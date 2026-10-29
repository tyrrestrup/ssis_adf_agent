:setvar DatabaseName "SsisAdfCustomerDemo"

USE [$(DatabaseName)];
GO

IF SCHEMA_ID(N'src') IS NULL EXEC(N'CREATE SCHEMA src AUTHORIZATION dbo');
IF SCHEMA_ID(N'ref') IS NULL EXEC(N'CREATE SCHEMA ref AUTHORIZATION dbo');
IF SCHEMA_ID(N'ssisout') IS NULL EXEC(N'CREATE SCHEMA ssisout AUTHORIZATION dbo');
IF SCHEMA_ID(N'adfout') IS NULL EXEC(N'CREATE SCHEMA adfout AUTHORIZATION dbo');
IF SCHEMA_ID(N'audit') IS NULL EXEC(N'CREATE SCHEMA audit AUTHORIZATION dbo');
GO

IF OBJECT_ID(N'src.Customer', N'U') IS NULL
CREATE TABLE src.Customer
(
    CustomerId bigint NOT NULL CONSTRAINT PK_src_Customer PRIMARY KEY,
    CustomerName nvarchar(100) NOT NULL,
    CustomerRiskScore int NOT NULL,
    RequiresManualReview bit NOT NULL,
    IsActive bit NOT NULL CONSTRAINT DF_src_Customer_IsActive DEFAULT (1)
);
GO

IF OBJECT_ID(N'src.Account', N'U') IS NULL
CREATE TABLE src.Account
(
    AccountId bigint NOT NULL CONSTRAINT PK_src_Account PRIMARY KEY,
    CustomerId bigint NOT NULL,
    AccountNumber nvarchar(20) NOT NULL,
    CONSTRAINT FK_src_Account_Customer
        FOREIGN KEY (CustomerId) REFERENCES src.Customer(CustomerId)
);
GO

IF OBJECT_ID(N'src.CustomerTransaction', N'U') IS NULL
CREATE TABLE src.CustomerTransaction
(
    TransactionId bigint NOT NULL CONSTRAINT PK_src_CustomerTransaction PRIMARY KEY,
    AccountId bigint NOT NULL,
    BusinessDate date NOT NULL,
    Amount decimal(19,2) NOT NULL,
    CurrencyCode nchar(3) NOT NULL,
    OriginCountryCode nchar(2) NOT NULL,
    TransactionType nvarchar(20) NOT NULL,
    Status nvarchar(20) NOT NULL,
    CONSTRAINT FK_src_CustomerTransaction_Account
        FOREIGN KEY (AccountId) REFERENCES src.Account(AccountId)
);
GO

IF OBJECT_ID(N'ref.CountryRisk', N'U') IS NULL
CREATE TABLE ref.CountryRisk
(
    CountryCode nchar(2) NOT NULL CONSTRAINT PK_ref_CountryRisk PRIMARY KEY,
    CountryName nvarchar(100) NOT NULL,
    CountryRiskScore int NOT NULL,
    RiskTier nvarchar(20) NOT NULL,
    IsActive bit NOT NULL CONSTRAINT DF_ref_CountryRisk_IsActive DEFAULT (1)
);
GO

IF OBJECT_ID(N'audit.PackageRun', N'U') IS NULL
CREATE TABLE audit.PackageRun
(
    BatchId bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_audit_PackageRun PRIMARY KEY,
    PackageName nvarchar(128) NOT NULL,
    BusinessDate date NOT NULL,
    ExecutionId bigint NULL,
    Status nvarchar(20) NOT NULL,
    RowsExtracted int NULL,
    RowsLoaded int NULL,
    RowsRejected int NULL,
    StartedUtc datetime2(3) NOT NULL,
    CompletedUtc datetime2(3) NULL
);
GO

IF OBJECT_ID(N'audit.PackageError', N'U') IS NULL
CREATE TABLE audit.PackageError
(
    PackageErrorId bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_audit_PackageError PRIMARY KEY,
    BatchId bigint NULL,
    PackageName nvarchar(128) NOT NULL,
    SourceName nvarchar(128) NULL,
    ErrorCode int NULL,
    ErrorDescription nvarchar(4000) NULL,
    LoggedUtc datetime2(3) NOT NULL
);
GO

IF OBJECT_ID(N'ssisout.TransactionRiskClassified', N'U') IS NULL
CREATE TABLE ssisout.TransactionRiskClassified
(
    TransactionId bigint NOT NULL,
    AccountId bigint NOT NULL,
    CustomerId bigint NOT NULL,
    BusinessDate date NOT NULL,
    Amount decimal(19,2) NOT NULL,
    CurrencyCode nchar(3) NOT NULL,
    OriginCountryCode nchar(2) NOT NULL,
    TransactionType nvarchar(20) NOT NULL,
    CustomerRiskScore int NOT NULL,
    RequiresManualReview bit NOT NULL,
    CountryRiskScore int NOT NULL,
    CountryRiskTier nvarchar(20) NOT NULL,
    AmountRiskScore int NOT NULL,
    CombinedRiskScore int NOT NULL,
    BatchId bigint NOT NULL,
    LoadUtc datetime2(3) NOT NULL,
    RiskClass nvarchar(20) NOT NULL,
    CONSTRAINT PK_ssisout_TransactionRiskClassified
        PRIMARY KEY (BusinessDate, TransactionId)
);
GO

IF OBJECT_ID(N'ssisout.TransactionRiskException', N'U') IS NULL
CREATE TABLE ssisout.TransactionRiskException
(
    TransactionId bigint NOT NULL,
    AccountId bigint NOT NULL,
    CustomerId bigint NOT NULL,
    BusinessDate date NOT NULL,
    Amount decimal(19,2) NOT NULL,
    CurrencyCode nchar(3) NOT NULL,
    OriginCountryCode nchar(2) NOT NULL,
    TransactionType nvarchar(20) NOT NULL,
    CustomerRiskScore int NOT NULL,
    RequiresManualReview bit NOT NULL,
    ExceptionReason nvarchar(50) NOT NULL,
    BatchId bigint NOT NULL,
    LoadUtc datetime2(3) NOT NULL,
    CONSTRAINT PK_ssisout_TransactionRiskException
        PRIMARY KEY (BusinessDate, TransactionId)
);
GO

IF OBJECT_ID(N'ssisout.CustomerRiskDailyStage', N'U') IS NULL
CREATE TABLE ssisout.CustomerRiskDailyStage
(
    CustomerId bigint NOT NULL,
    BusinessDate date NOT NULL,
    RiskClass nvarchar(20) NOT NULL,
    TransactionCount bigint NOT NULL,
    TotalAmount decimal(19,2) NOT NULL
);
GO

IF OBJECT_ID(N'ssisout.DailyCustomerRiskSummary', N'U') IS NULL
CREATE TABLE ssisout.DailyCustomerRiskSummary
(
    CustomerId bigint NOT NULL,
    BusinessDate date NOT NULL,
    RiskClass nvarchar(20) NOT NULL,
    TransactionCount bigint NOT NULL,
    TotalAmount decimal(19,2) NOT NULL,
    BatchId bigint NOT NULL,
    ModifiedUtc datetime2(3) NOT NULL,
    CONSTRAINT PK_ssisout_DailyCustomerRiskSummary
        PRIMARY KEY (CustomerId, BusinessDate, RiskClass)
);
GO

IF OBJECT_ID(N'adfout.TransactionRiskClassified', N'U') IS NULL
SELECT TOP (0) * INTO adfout.TransactionRiskClassified
FROM ssisout.TransactionRiskClassified;
GO

IF OBJECT_ID(N'adfout.TransactionRiskException', N'U') IS NULL
SELECT TOP (0) * INTO adfout.TransactionRiskException
FROM ssisout.TransactionRiskException;
GO

IF OBJECT_ID(N'adfout.DailyCustomerRiskSummary', N'U') IS NULL
SELECT TOP (0) * INTO adfout.DailyCustomerRiskSummary
FROM ssisout.DailyCustomerRiskSummary;
GO

CREATE OR ALTER PROCEDURE audit.usp_StartPackageRun
    @PackageName nvarchar(128),
    @BusinessDate date,
    @ExecutionId bigint = NULL,
    @BatchId bigint OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT audit.PackageRun
        (PackageName, BusinessDate, ExecutionId, Status, StartedUtc)
    VALUES
        (@PackageName, @BusinessDate, @ExecutionId, N'Running', SYSUTCDATETIME());

    SET @BatchId = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE audit.usp_ResetPackageOutputs
    @BusinessDate date
AS
BEGIN
    SET NOCOUNT ON;

    DELETE ssisout.TransactionRiskClassified WHERE BusinessDate = @BusinessDate;
    DELETE ssisout.TransactionRiskException WHERE BusinessDate = @BusinessDate;
    DELETE ssisout.CustomerRiskDailyStage WHERE BusinessDate = @BusinessDate;
    DELETE ssisout.DailyCustomerRiskSummary WHERE BusinessDate = @BusinessDate;
END;
GO

CREATE OR ALTER PROCEDURE ssisout.usp_MergeDailyCustomerRiskSummary
    @BusinessDate date,
    @BatchId bigint
AS
BEGIN
    SET NOCOUNT ON;

    MERGE ssisout.DailyCustomerRiskSummary AS target
    USING
    (
        SELECT CustomerId, BusinessDate, RiskClass, TransactionCount, TotalAmount
        FROM ssisout.CustomerRiskDailyStage
        WHERE BusinessDate = @BusinessDate
    ) AS source
       ON target.CustomerId = source.CustomerId
      AND target.BusinessDate = source.BusinessDate
      AND target.RiskClass = source.RiskClass
    WHEN MATCHED THEN UPDATE SET
        TransactionCount = source.TransactionCount,
        TotalAmount = source.TotalAmount,
        BatchId = @BatchId,
        ModifiedUtc = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN INSERT
        (CustomerId, BusinessDate, RiskClass, TransactionCount, TotalAmount,
         BatchId, ModifiedUtc)
    VALUES
        (source.CustomerId, source.BusinessDate, source.RiskClass,
         source.TransactionCount, source.TotalAmount, @BatchId, SYSUTCDATETIME())
    WHEN NOT MATCHED BY SOURCE AND target.BusinessDate = @BusinessDate THEN DELETE;
END;
GO

CREATE OR ALTER PROCEDURE audit.usp_ValidatePackageControlTotals
    @BusinessDate date,
    @RowsExtracted int,
    @RowsLoaded int,
    @RowsRejected int
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SourceRows int =
    (
        SELECT COUNT(*)
        FROM src.CustomerTransaction
        WHERE BusinessDate = @BusinessDate
          AND Status = N'POSTED'
    );
    DECLARE @ClassifiedRows int =
    (
        SELECT COUNT(*)
        FROM ssisout.TransactionRiskClassified
        WHERE BusinessDate = @BusinessDate
    );
    DECLARE @ExceptionRows int =
    (
        SELECT COUNT(*)
        FROM ssisout.TransactionRiskException
        WHERE BusinessDate = @BusinessDate
    );

    IF @RowsExtracted <> @SourceRows
       OR @RowsLoaded <> @ClassifiedRows
       OR @RowsRejected <> @ExceptionRows
       OR @SourceRows <> @ClassifiedRows + @ExceptionRows
    BEGIN
        THROW 51001, 'Transaction-risk control totals do not reconcile.', 1;
    END;
END;
GO

CREATE OR ALTER PROCEDURE audit.usp_CompletePackageRun
    @BatchId bigint,
    @RowsExtracted int,
    @RowsLoaded int,
    @RowsRejected int
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE audit.PackageRun
    SET Status = N'Succeeded',
        RowsExtracted = @RowsExtracted,
        RowsLoaded = @RowsLoaded,
        RowsRejected = @RowsRejected,
        CompletedUtc = SYSUTCDATETIME()
    WHERE BatchId = @BatchId;
END;
GO
