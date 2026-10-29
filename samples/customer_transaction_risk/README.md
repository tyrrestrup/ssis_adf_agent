# Customer demo: daily transaction risk

This folder is a complete, synthetic customer handoff for testing the SSIS-to-ADF migration
workflow. It contains a medium-complexity SSIS project, its SQL Server dependencies, fixed test
data, expected results, and reconciliation checks.

The customer scenario is:

> Process one day of posted customer transactions, enrich each row with customer and country
> risk, classify it as `HIGH`, `MANUAL_REVIEW`, or `STANDARD`, route missing country-risk
> reference data to an exception table, and create a daily customer summary.

All people, accounts, transactions, and business rules are fictional.

## What represents the customer input?

This is the exact folder to give to the migration workflow:

```text
customer-input/
  ssis/
    CustomerTransactionRisk/
      CustomerTransactionRisk.sln
      CustomerTransactionRisk.dtproj
      Project.params
      CRM_DailyTransaction_Risk.dtsx
```

Everything else in this sample is supporting setup or expected evidence, not part of the
customer's SSIS source.

## Package behavior

`CRM_DailyTransaction_Risk.dtsx` targets SQL Server 2022 and uses:

- a project connection parameter;
- a required package `BusinessDate` parameter;
- Execute SQL Tasks for audit, reset, merge, validation, and completion;
- an OLE DB Source with a parameterized date query;
- Row Count transformations;
- a Lookup against `ref.CountryRisk`;
- an explicit Lookup no-match exception output;
- Derived Column risk scoring;
- an ordered Conditional Split;
- Multicast and Union All branches;
- an Aggregate transformation;
- multiple OLE DB destinations;
- success precedence constraints across the control flow.

The fixed business date is `2026-01-14`.

## Why this is a useful migration test

Most activities have deterministic ADF mappings. The package also contains one deliberate
semantic risk:

> Transaction `1006` has origin country `ZZ`, which does not exist in `ref.CountryRisk`. SSIS
> routes it through the Lookup no-match output into
> `ssisout.TransactionRiskException`. A conversion that defaults the risk, drops the row, or
> sends it through normal classification is incorrect.

Conditional Split order also matters: the `HIGH` output is evaluated before
`MANUAL_REVIEW`. The migration must preserve that ordering.

## Prerequisites

### Required to prepare the database and use the migration CLI

- SQL Server 2022 Developer Edition or another compatible SQL Server.
- A local/default instance reachable as `localhost`, or another server name you provide.
- Windows authentication access with permission to create a database and objects.
- Microsoft OLE DB Driver for SQL Server (`MSOLEDBSQL`).
- `sqlcmd` or SQL Server Management Studio.
- Python 3.11+ and this repository installed with `pip install -e .`.

### Required only to execute or edit the SSIS package

- Windows.
- SQL Server Integration Services runtime.
- Visual Studio 2022 with SQL Server Data Tools.
- SQL Server Integration Services Projects 2022 extension.

Visual Studio is **not required** to give this package to `ssis-adf migrate`.

## Folder map

```text
database/   SQL Server create, seed, reset, baseline, and reconciliation scripts
config/     Example local connection configuration
customer-input/ssis/
            Customer-shaped SSIS solution and package
expected/   Deterministic package inventory, baseline, review expectations, hashes
tools/      Generation, SQL setup, and migration-check helpers
```

## 1. Generate or verify the SSIS project

The committed project is generated deterministically from `tools/generate_demo.py`.

```powershell
python samples\customer_transaction_risk\tools\generate_demo.py
```

Verify that committed generated files are current:

```powershell
python samples\customer_transaction_risk\tools\generate_demo.py --check
```

Regeneration produces the same package IDs and file content.

## 2. Prepare SQL Server

From the repository root:

```powershell
.\samples\customer_transaction_risk\tools\setup_demo.ps1
```

For a named or remote instance:

```powershell
.\samples\customer_transaction_risk\tools\setup_demo.ps1 `
  -Server "MACHINE\SQL2022" `
  -Database "SsisAdfCustomerDemo"
```

The scripts create and seed:

- `src.Customer`, `src.Account`, and `src.CustomerTransaction`;
- `ref.CountryRisk`;
- `ssisout` package output tables;
- matching empty `adfout` reconciliation tables;
- package audit and error tables;
- reset, merge, validation, and audit stored procedures.

Scripts are idempotent and can be rerun.

## 3. Configure the SSIS connection

The default `Project.params` connection is:

```text
Data Source=localhost;
Initial Catalog=SsisAdfCustomerDemo;
Provider=MSOLEDBSQL.1;
Integrated Security=SSPI;
TrustServerCertificate=True;
```

If your SQL Server is elsewhere, update the `DemoDbConnStr` project parameter in Visual Studio,
an SSIS environment, or a copy of `Project.params`. Do not add passwords to this sample.

## 4. Optional: open and run in SSDT

If an SSIS-capable machine is available:

1. Open `customer-input\ssis\CustomerTransactionRisk\CustomerTransactionRisk.sln`.
2. Confirm the project target is SQL Server 2022.
3. Check the `DemoDbConnStr` project parameter.
4. Set package parameter `BusinessDate` to `2026-01-14`.
5. Build the project.
6. Run `CRM_DailyTransaction_Risk.dtsx`.
7. Run `database\05_verify_baseline.sql` through `sqlcmd` or SSMS.

This repository environment does not have an SSIS runtime, so the package is structurally and
semantically tested here but runtime execution must be confirmed on an SSIS-capable machine.

## 5. Demo without Visual Studio

When no SSIS runtime is available, materialize the documented expected output:

```powershell
.\samples\customer_transaction_risk\tools\setup_demo.ps1 `
  -MaterializeExpectedOutput
```

The helper also runs the fixed baseline verification. To rerun that verification separately:

```powershell
sqlcmd -S localhost -E -b `
  -i samples\customer_transaction_risk\database\05_verify_baseline.sql
```

This reference SQL is useful for demonstrating reports and reconciliation. It is **not proof**
that SSIS executed the package.

## 6. Start the migration exactly as a customer would

```powershell
ssis-adf migrate `
  --source samples\customer_transaction_risk\customer-input\ssis `
  --workspace work\customer-transaction-risk
```

Read:

```text
work/customer-transaction-risk/migration_report.md
work/customer-transaction-risk/02_assessment/ai_review_queue.json
work/customer-transaction-risk/03_adf/CRM_DailyTransaction_Risk/
```

The deterministic engine should convert the obvious mappings without AI. The review queue
should focus Copilot on:

1. Lookup no-match routing;
2. Conditional Split ordering and default behavior;
3. Aggregate grouping semantics.

Run the included helper for generation plus migration kickoff:

```powershell
.\samples\customer_transaction_risk\tools\run_checks.ps1
```

## 7. Expected baseline

The source has eight posted transactions for `2026-01-14`:

| Output | Rows | Amount |
|---|---:|---:|
| High risk | 3 | 42,000.00 |
| Manual review | 2 | 4,800.00 |
| Standard | 2 | 3,250.00 |
| Country-risk exception | 1 | 1,200.00 |
| **Input total** | **8** | **51,250.00** |

Expected IDs:

- High risk: `1002`, `1004`, `1005`
- Manual review: `1003`, `1007`
- Standard: `1001`, `1008`
- Exception: `1006`

The machine-readable version is `expected/baseline.json`.

## 8. Reconcile SSIS and ADF

For a controlled comparison:

1. Keep SSIS output under `ssisout`.
2. Configure the ADF test version to write equivalent rows under `adfout`.
3. Run both systems for `2026-01-14`.
4. Run:

```powershell
sqlcmd -S localhost -E -b `
  -i samples\customer_transaction_risk\database\06_reconciliation.sql
```

The reconciliation checks:

- classified, exception, and customer-summary row counts;
- control totals;
- classified, exception, and customer-summary key sets in both directions;
- classified and customer-summary row hashes over material business columns.

A mismatch should be recorded through:

```powershell
ssis-adf reconcile `
  --workspace work\customer-transaction-risk `
  --package CRM_DailyTransaction_Risk `
  --result fail `
  --evidence <path-to-results> `
  --notes "<mismatch summary>"
```

That creates a `RECON-*` item and routes the package back to Copilot review.

## Known limitations

- The project files are generated to match SSDT-style SQL Server 2022 project structure, but this
  repository does not include evidence that every generated file opens in the SSDT designer.
- A real SSIS runtime is required to prove package execution.
- The current converter may generate incomplete Mapping Data Flow details; the review queue and
  reconciliation are intentionally used to identify those gaps.
- The reference-output SQL is a test fixture, not an SSIS execution substitute.
