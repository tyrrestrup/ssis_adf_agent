[CmdletBinding()]
param(
    [string]$Server = "localhost",
    [string]$Database = "SsisAdfCustomerDemo",
    [switch]$MaterializeExpectedOutput
)

$ErrorActionPreference = "Stop"
$demoRoot = Split-Path -Parent $PSScriptRoot
$databaseDir = Join-Path $demoRoot "database"

if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    throw "sqlcmd is required. Install SQL Server command-line tools or use SSMS to run database/*.sql."
}

$scripts = @(
    "00_create_database.sql",
    "01_create_schema.sql",
    "02_seed_reference_data.sql",
    "03_seed_daily_transactions.sql",
    "04_reset_demo.sql"
)

foreach ($script in $scripts) {
    $path = Join-Path $databaseDir $script
    Write-Host "Running $script"
    & sqlcmd -S $Server -E -b -v "DatabaseName=$Database" -i $path
    if ($LASTEXITCODE -ne 0) {
        throw "sqlcmd failed for $script with exit code $LASTEXITCODE"
    }

}

if ($MaterializeExpectedOutput) {
    $referenceScript = Join-Path $databaseDir "05_materialize_expected_output.sql"
    Write-Host "Running 05_materialize_expected_output.sql"
    & sqlcmd -S $Server -E -b -v "DatabaseName=$Database" -i $referenceScript
    if ($LASTEXITCODE -ne 0) {
        throw "sqlcmd failed for reference output with exit code $LASTEXITCODE"
    }

    $verifyScript = Join-Path $databaseDir "05_verify_baseline.sql"
    Write-Host "Running 05_verify_baseline.sql"
    & sqlcmd -S $Server -E -b -v "DatabaseName=$Database" -i $verifyScript
    if ($LASTEXITCODE -ne 0) {
        throw "sqlcmd failed for baseline verification with exit code $LASTEXITCODE"
    }
}

Write-Host ""
Write-Host "Demo database is ready."
Write-Host "Server:   $Server"
Write-Host "Database: $Database"
if ($MaterializeExpectedOutput) {
    Write-Host "Expected SSIS output: materialized for demo-only validation"
}
