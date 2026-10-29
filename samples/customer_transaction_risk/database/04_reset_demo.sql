:setvar DatabaseName "SsisAdfCustomerDemo"
:setvar BusinessDate "2026-01-14"

USE [$(DatabaseName)];
GO

DECLARE @BusinessDate date = CONVERT(date, '$(BusinessDate)');

DELETE adfout.TransactionRiskClassified WHERE BusinessDate = @BusinessDate;
DELETE adfout.TransactionRiskException WHERE BusinessDate = @BusinessDate;
DELETE adfout.DailyCustomerRiskSummary WHERE BusinessDate = @BusinessDate;
DELETE ssisout.TransactionRiskClassified WHERE BusinessDate = @BusinessDate;
DELETE ssisout.TransactionRiskException WHERE BusinessDate = @BusinessDate;
DELETE ssisout.CustomerRiskDailyStage WHERE BusinessDate = @BusinessDate;
DELETE ssisout.DailyCustomerRiskSummary WHERE BusinessDate = @BusinessDate;
DELETE audit.PackageRun WHERE BusinessDate = @BusinessDate;
GO
