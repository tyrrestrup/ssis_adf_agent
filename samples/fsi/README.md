# Synthetic FSI SSIS package corpus

This folder contains 10 deterministic SSIS packages modeled on financial-services batch
workloads. The packages are fictional and contain no customer code or data.

Use the corpus to test package parsing, assessment, conversion, gap detection, and artifact
validation across a broader set of SSIS patterns.

## Package catalog

| Package | Domain | Representative patterns |
|---|---|---|
| `FIN_FX_DailyRates_Load` | Finance | Flat file, SQL load, audit |
| `FIN_GL_JournalEntries_Incremental` | General ledger | Watermark, MERGE, OR precedence |
| `OPS_Custodian_Positions_Ingest` | Investment operations | Foreach file, quarantine, split outputs |
| `CRM_Customer_KYC_SCD2` | Customer and KYC | Sequence, SCD, OLE DB Command |
| `AML_CTR_Daily_Monitoring` | AML | Aggregate, threshold routing, Script Task |
| `PAY_ACH_NACHA_Outbound` | Payments | Fixed-width output, script, executable, SFTP |
| `TRS_Bank_Statement_Reconciliation` | Treasury | Sort, full outer Merge Join, tolerance |
| `RISK_Credit_Exposure_Aggregation` | Credit risk | Cross-database SQL, lookup, aggregate |
| `CMP_OFAC_Sanctions_Screening` | Sanctions | Fuzzy match, Script Task, alert output |
| `ORCH_EOD_Regulatory_Batch_Master` | Orchestration | Child packages, loops, parallel branches |

The detailed machine-readable inventory is in [`catalog.json`](catalog.json).

## Feature coverage

- project and package parameters;
- variables and expressions;
- Execute SQL result sets and parameter bindings;
- data flows with sources, destinations, lookups, splits, aggregates, sorts, joins, and unions;
- Foreach, For Loop, and Sequence containers;
- success, failure, completion, expression, AND, and OR precedence;
- Execute Package, Script, Execute Process, File System, and Send Mail tasks;
- event handlers;
- linked-server and cross-database references;
- encrypted-package warnings and sensitive parameters.

Several packages contain deliberate semantic traps, including unconnected outputs, business-date
selection errors, fuzzy-match differences, fixed-width file requirements, lookup no-match paths,
and loop-condition inversion. These cases should be caught through review and reconciliation,
not treated as automatic success.

## Regenerate and validate

From the repository root:

```powershell
pip install -e ".[dev]"

python samples\fsi\tools\generate_packages.py
python samples\fsi\tools\generate_packages.py --check
python samples\fsi\tools\validate_corpus.py
```

Generation is deterministic. Edit `tools/packages_a.py` or `tools/packages_b.py`, not the
generated `.dtsx` files.

`validate_corpus.py` checks:

1. DTSX structural integrity and references;
2. parser output against `catalog.json`;
3. conversion and generated-artifact behavior.

## Important limitation

The files follow the SSIS 2019 DTSX structure and pass the repository's structural checks. They
have not all been opened, built, and executed in SSDT or SSISDB. Use the
[`customer_transaction_risk`](../customer_transaction_risk/README.md) sample when a SQL-backed
baseline and reconciliation example are required.
