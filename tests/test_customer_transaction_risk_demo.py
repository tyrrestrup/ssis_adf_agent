from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

from ssis_adf_agent.analyzers.complexity_scorer import score_package
from ssis_adf_agent.analyzers.gap_analyzer import analyze_gaps
from ssis_adf_agent.parsers.readers.local_reader import LocalReader
from ssis_adf_agent.workflow import load_workspace, run_migration, validate_workspace

REPO = Path(__file__).resolve().parents[1]
DEMO = REPO / "samples" / "customer_transaction_risk"
PROJECT = DEMO / "customer-input" / "ssis" / "CustomerTransactionRisk"
PACKAGE = PROJECT / "CRM_DailyTransaction_Risk.dtsx"


def test_generated_customer_demo_is_current() -> None:
    result = subprocess.run(
        [
            sys.executable,
            str(DEMO / "tools" / "generate_demo.py"),
            "--check",
        ],
        cwd=REPO,
        check=False,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stdout + result.stderr


def test_customer_package_is_medium_and_contains_semantic_review_cases() -> None:
    package = LocalReader().read(PACKAGE)
    score = score_package(package)
    gaps = analyze_gaps(package)

    assert package.name == "CRM_DailyTransaction_Risk"
    assert score.score == 49
    assert score.effort_estimate == "Medium"
    assert len(package.tasks) == 6
    assert len(package.constraints) == 5

    gap_types = {gap.task_type for gap in gaps}
    assert "DataFlow/Lookup" in gap_types
    assert "DataFlow/ConditionalSplit" in gap_types
    assert "DataFlow/Aggregate" in gap_types
    assert all(gap.severity == "warning" for gap in gaps)


def test_customer_input_runs_through_migration_workflow(tmp_path: Path) -> None:
    workspace = tmp_path / "customer-risk-work"
    manifest = run_migration(DEMO / "customer-input" / "ssis", workspace)
    persisted, queue = load_workspace(workspace)

    assert manifest["errors"] == []
    assert len(persisted["packages"]) == 1
    package = persisted["packages"][0]
    assert package["key"] == "CRM_DailyTransaction_Risk"
    assert package["complexity"]["effort_estimate"] == "Medium"
    assert package["conversion_status"] == "review_required"
    assert package["open_review_items"] == 3
    assert {item["task_type"] for item in queue} == {
        "DataFlow/Lookup",
        "DataFlow/ConditionalSplit",
        "DataFlow/Aggregate",
    }
    assert (workspace / "03_adf" / package["key"] / "pipeline").is_dir()

    validation = validate_workspace(workspace)
    result = validation["packages"][0]
    assert result["status"] == "blocked"
    assert result["validation_issues"] == []
    assert len(result["open_review_items"]) == 3
    assert result["assessment_approved"] is False


def test_baseline_is_balanced_and_preserves_lookup_exception() -> None:
    baseline = json.loads((DEMO / "expected" / "baseline.json").read_text(encoding="utf-8"))

    assert baseline["input_transaction_count"] == (
        baseline["classified_transaction_count"]
        + baseline["exception_transaction_count"]
    )
    assert float(baseline["input_amount"]) == (
        float(baseline["classified_amount"]) + float(baseline["exception_amount"])
    )
    assert baseline["high_risk_transaction_ids"] == [1002, 1004, 1005]
    assert baseline["exception_transaction_ids"] == [1006]
    assert baseline["customer_summary_count"] == 4


def test_customer_handoff_contains_required_assets() -> None:
    required = [
        DEMO / "README.md",
        PROJECT / "CustomerTransactionRisk.sln",
        PROJECT / "CustomerTransactionRisk.dtproj",
        PROJECT / "Project.params",
        PACKAGE,
        DEMO / "database" / "00_create_database.sql",
        DEMO / "database" / "01_create_schema.sql",
        DEMO / "database" / "02_seed_reference_data.sql",
        DEMO / "database" / "03_seed_daily_transactions.sql",
        DEMO / "database" / "04_reset_demo.sql",
        DEMO / "database" / "05_materialize_expected_output.sql",
        DEMO / "database" / "05_verify_baseline.sql",
        DEMO / "database" / "06_reconciliation.sql",
        DEMO / "config" / "local.example.json",
        DEMO / "tools" / "setup_demo.ps1",
        DEMO / "tools" / "run_checks.ps1",
    ]
    assert all(path.exists() for path in required)

    reconciliation = (DEMO / "database" / "06_reconciliation.sql").read_text(
        encoding="utf-8"
    )
    assert "ssisout.TransactionRiskClassified" in reconciliation
    assert "ssisout.TransactionRiskException" in reconciliation
    assert "ssisout.DailyCustomerRiskSummary" in reconciliation
