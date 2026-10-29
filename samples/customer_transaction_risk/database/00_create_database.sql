:setvar DatabaseName "SsisAdfCustomerDemo"

USE [master];
GO

IF DB_ID(N'$(DatabaseName)') IS NULL
BEGIN
    PRINT N'Creating database $(DatabaseName)';
    EXEC(N'CREATE DATABASE [' + '$(DatabaseName)' + N']');
END
ELSE
BEGIN
    PRINT N'Database $(DatabaseName) already exists';
END;
GO

ALTER DATABASE [$(DatabaseName)] SET RECOVERY SIMPLE;
GO
