# Setup guide

## Requirements

| Requirement | When needed |
|---|---|
| Python 3.11 or later | Always |
| Git | Clone the repository or read packages from Git |
| VS Code and GitHub Copilot | Optional AI-assisted review |
| ODBC Driver for SQL Server 17+ | Read packages or schedules from SQL Server |
| Azure CLI | Deploy to ADF with a developer identity |
| SQL Server 2022 and `sqlcmd` | Run the customer transaction-risk demo |

## Install

```powershell
git clone https://github.com/tyrrestrup/ssis_adf_agent.git
cd ssis_adf_agent

python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -e .
python scripts\verify_install.py
```

For development:

```powershell
pip install -e ".[dev]"
```

Optional features:

```powershell
pip install -e ".[llm]"   # Azure OpenAI Script Task drafts
pip install -e ".[mcp]"   # MCP compatibility adapter
```

## Run the customer demo

The demo is the fastest way to see the intended customer experience.

```powershell
.\samples\customer_transaction_risk\tools\setup_demo.ps1 -MaterializeExpectedOutput
.\samples\customer_transaction_risk\tools\run_checks.ps1
```

The first command creates and verifies the SQL Server baseline. The second verifies generated
sample files and creates a migration workspace.

See the [demo README](samples/customer_transaction_risk/README.md) for SQL Server, SSDT, and
reconciliation details.

## Run against your packages

```powershell
ssis-adf migrate `
  --source D:\Customer\SSIS `
  --workspace work\customer-migration
```

Then open:

```text
work/customer-migration/migration_report.md
work/customer-migration/02_assessment/ai_review_queue.json
```

Continue with the [operator guide](docs/OPERATOR_GUIDE.md).

## Azure authentication

For local development, run:

```powershell
az login
```

For a service principal in CI/CD:

```powershell
$env:AZURE_TENANT_ID = "<tenant-id>"
$env:AZURE_CLIENT_ID = "<application-id>"
$env:AZURE_CLIENT_SECRET = "<secret>"
```

Never commit these values.

## Optional Azure OpenAI configuration

```powershell
$env:AZURE_OPENAI_ENDPOINT = "https://<resource>.openai.azure.com/"
$env:AZURE_OPENAI_API_KEY = "<key>"
$env:AZURE_OPENAI_DEPLOYMENT = "<deployment>"
```

Script Task translation produces a draft. Infrastructure calls and unsupported behavior remain
explicit manual work.

## Troubleshooting

| Problem | Resolution |
|---|---|
| `ssis-adf` is not found | Activate the virtual environment and rerun `pip install -e .` |
| Package import fails | Run `python scripts\verify_install.py` and confirm Python 3.11+ |
| SQL Server connection fails | Install the ODBC driver, verify the instance name, and confirm Windows authentication access |
| Deployment requests authentication | Run `az login` or configure the service-principal variables |
| Encrypted SSIS values are missing | Re-export with an appropriate protection level or map secrets manually |
| Validation is blocked | Resolve open review items and record G1 assessment evidence first |
| Reconciliation is blocked | Record successful G3 test evidence before G4 reconciliation |
