[CmdletBinding()]
param(
    [string]$Workspace = "work/customer-transaction-risk"
)

$ErrorActionPreference = "Stop"
$demoRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $demoRoot)
$source = Join-Path $demoRoot "customer-input\ssis"
$venvPython = Join-Path $repoRoot ".venv\Scripts\python.exe"
$python = if (Test-Path $venvPython) { $venvPython } else { "python" }

Push-Location $repoRoot
try {
    & $python samples\customer_transaction_risk\tools\generate_demo.py --check
    if ($LASTEXITCODE -ne 0) { throw "Generated demo files are stale." }

    & $python -m ssis_adf_agent.cli migrate --source $source --workspace $Workspace
    if ($LASTEXITCODE -ne 0) { throw "Migration kickoff failed." }

    & $python -m ssis_adf_agent.cli status --workspace $Workspace
    if ($LASTEXITCODE -ne 0) { throw "Unable to read migration status." }

    Write-Host ""
    Write-Host "Review:"
    Write-Host "  $Workspace\migration_report.md"
    Write-Host "  $Workspace\02_assessment\ai_review_queue.json"
}
finally {
    Pop-Location
}
