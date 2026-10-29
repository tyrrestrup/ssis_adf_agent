"""Generate the customer-shaped SQL Server transaction-risk SSIS demo.

Run from the repository root:

    python samples/customer_transaction_risk/tools/generate_demo.py
    python samples/customer_transaction_risk/tools/generate_demo.py --check
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path

DEMO_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = DEMO_ROOT.parents[1]
FSI_TOOLS = REPO_ROOT / "samples" / "fsi" / "tools"
sys.path.insert(0, str(FSI_TOOLS))

from dtsx_builder import DTS_NS, Package, T, guid, project_params_xml  # noqa: E402

PROJECT_NAME = "CustomerTransactionRisk"
PACKAGE_NAME = "CRM_DailyTransaction_Risk"
BUSINESS_DATE = "2026-01-14T00:00:00"
PROJECT_DIR = DEMO_ROOT / "customer-input" / "ssis" / PROJECT_NAME

PROJECT_PARAMS = [
    (
        "Environment",
        "String",
        "LOCAL",
        True,
        False,
        "LOCAL | DEV | TEST | PROD",
    ),
    (
        "DemoDbConnStr",
        "String",
        "Data Source=localhost;Initial Catalog=SsisAdfCustomerDemo;"
        "Provider=MSOLEDBSQL.1;Integrated Security=SSPI;"
        "TrustServerCertificate=True;Application Name=SSIS-CustomerTransactionRisk;",
        True,
        False,
        "SQL Server database used by the reusable transaction-risk demo",
    ),
]

BASELINE = {
    "business_date": "2026-01-14",
    "input_transaction_count": 8,
    "classified_transaction_count": 7,
    "exception_transaction_count": 1,
    "high_risk_count": 3,
    "manual_review_count": 2,
    "standard_count": 2,
    "input_amount": "51250.00",
    "classified_amount": "50050.00",
    "exception_amount": "1200.00",
    "high_risk_amount": "42000.00",
    "manual_review_amount": "4800.00",
    "standard_amount": "3250.00",
    "customer_summary_count": 4,
    "high_risk_transaction_ids": [1002, 1004, 1005],
    "manual_review_transaction_ids": [1003, 1007],
    "standard_transaction_ids": [1001, 1008],
    "exception_transaction_ids": [1006],
    "invariants": [
        "input_transaction_count = classified_transaction_count + exception_transaction_count",
        "input_amount = classified_amount + exception_amount",
    ],
}


def _package() -> Package:
    package = Package(
        PACKAGE_NAME,
        "Enriches daily customer transactions with country risk, classifies risk, "
        "routes missing reference data to an exception path, and builds customer summaries.",
        product_version="16.0.1000.6",
        creator_computer="CUSTOMER-SSISDEV",
        creator_name="CUSTOMER\\ssis.developer",
    )
    package.oledb(
        "CustomerRiskDb",
        "localhost",
        "SsisAdfCustomerDemo",
        project_param="DemoDbConnStr",
        description="Local SQL Server customer-risk demo database",
    )
    business_date = package.parameter(
        "BusinessDate",
        "DateTime",
        BUSINESS_DATE,
        required=True,
        description="Business date processed by the package",
    )
    package.variable("BatchId", "Int64", "0", description="Audit batch identifier")
    package.variable("RowsExtracted", "Int32", "0")
    package.variable("RowsLoaded", "Int32", "0")
    package.variable("RowsRejected", "Int32", "0")

    start = package.execute_sql(
        "SQL Start Batch",
        "CustomerRiskDb",
        "EXEC audit.usp_StartPackageRun "
        "@PackageName = ?, @BusinessDate = ?, @ExecutionId = ?, @BatchId = ? OUTPUT;",
        params=[
            ("System::PackageName", "Input", "NVARCHAR", "0"),
            (business_date, "Input", "DATE", "1"),
            ("System::ServerExecutionID", "Input", "BIGINT", "2"),
            ("User::BatchId", "Output", "BIGINT", "3"),
        ],
        description="Create an auditable package run",
    )
    clear = package.execute_sql(
        "SQL Clear Business Date",
        "CustomerRiskDb",
        "EXEC audit.usp_ResetPackageOutputs @BusinessDate = ?;",
        params=[(business_date, "Input", "DATE", "0")],
        description="Make the fixed-date demo safe to rerun",
    )

    data_flow_task, flow = package.data_flow(
        "DFT Enrich and Classify Transactions",
        "Extract daily transactions, enrich country risk, classify, route exceptions, "
        "and aggregate customer totals",
    )
    source = flow.ole_src(
        "OLE SRC Daily Transactions",
        "CustomerRiskDb",
        "SELECT t.TransactionId, t.AccountId, a.CustomerId, "
        "CAST(t.BusinessDate AS date) AS BusinessDate,\n"
        "       t.Amount, t.CurrencyCode, t.OriginCountryCode, t.TransactionType,\n"
        "       c.CustomerRiskScore, c.RequiresManualReview\n"
        "FROM src.CustomerTransaction t\n"
        "JOIN src.Account a ON a.AccountId = t.AccountId\n"
        "JOIN src.Customer c ON c.CustomerId = a.CustomerId\n"
        "WHERE t.BusinessDate = ? AND t.Status = 'POSTED';",
        [
            ("TransactionId", T.I8),
            ("AccountId", T.I8),
            ("CustomerId", T.I8),
            ("BusinessDate", T.DATE),
            ("Amount", T.numeric(19, 2)),
            ("CurrencyCode", T.wstr(3)),
            ("OriginCountryCode", T.wstr(2)),
            ("TransactionType", T.wstr(20)),
            ("CustomerRiskScore", T.I4),
            ("RequiresManualReview", T.BOOL),
        ],
        params=[business_date],
    )
    extracted = flow.row_count("RC Rows Extracted", source, "User::RowsExtracted")
    matched, no_match = flow.lookup(
        "LKP Country Risk",
        extracted,
        "CustomerRiskDb",
        "SELECT CountryCode, CountryRiskScore, RiskTier "
        "FROM ref.CountryRisk WHERE IsActive = 1",
        joins=[("OriginCountryCode", "CountryCode")],
        copy=[
            ("CountryRiskScore", "CountryRiskScore", T.I4),
            ("RiskTier", "CountryRiskTier", T.wstr(20)),
        ],
    )

    enriched = flow.derived(
        "DER Calculate Risk Score",
        matched,
        [
            (
                "AmountRiskScore",
                "[Amount] >= 10000 ? 50 : ([Amount] >= 5000 ? 20 : 0)",
                T.I4,
            ),
            (
                "CombinedRiskScore",
                "[CustomerRiskScore] + [CountryRiskScore] "
                "+ ([Amount] >= 10000 ? 50 : ([Amount] >= 5000 ? 20 : 0))",
                T.I4,
            ),
            ("BatchId", "@[User::BatchId]", T.I8),
            ("LoadUtc", "(DT_DBTIMESTAMP)GETUTCDATE()", T.TIMESTAMP),
        ],
    )
    loaded = flow.row_count("RC Rows Classified", enriched, "User::RowsLoaded")
    split = flow.cond_split(
        "CSPL Transaction Risk",
        loaded,
        [
            (
                "High Risk",
                "[Amount] >= 10000 || [CountryRiskScore] >= 70 "
                "|| [CombinedRiskScore] >= 100",
            ),
            (
                "Manual Review",
                "[RequiresManualReview] || [CombinedRiskScore] >= 50",
            ),
        ],
        default_name="Standard",
    )

    summary_inputs = []
    for output_name, risk_class in (
        ("High Risk", "HIGH"),
        ("Manual Review", "MANUAL_REVIEW"),
        ("Standard", "STANDARD"),
    ):
        labelled = flow.derived(
            f"DER Label {risk_class}",
            split[output_name],
            [("RiskClass", f'"{risk_class}"', T.wstr(20))],
        )
        branches = flow.multicast(f"MC {risk_class}", labelled, 2)
        flow.ole_dest(
            f"OLE DST {risk_class}",
            branches[0],
            "CustomerRiskDb",
            "[ssisout].[TransactionRiskClassified]",
        )
        summary_inputs.append(branches[1])

    union = flow.union_all(
        "UALL Classified For Summary",
        summary_inputs,
        [
            ("CustomerId", T.I8),
            ("BusinessDate", T.DATE),
            ("RiskClass", T.wstr(20)),
            ("Amount", T.numeric(19, 2)),
        ],
    )
    summary = flow.aggregate(
        "AGG Customer Daily Risk",
        union,
        [
            ("CustomerId", "GroupBy", "CustomerId", T.I8),
            ("BusinessDate", "GroupBy", "BusinessDate", T.DATE),
            ("RiskClass", "GroupBy", "RiskClass", T.wstr(20)),
            ("TransactionCount", "CountAll", None, T.I8),
            ("TotalAmount", "Sum", "Amount", T.numeric(19, 2)),
        ],
    )
    flow.ole_dest(
        "OLE DST Customer Risk Stage",
        summary,
        "CustomerRiskDb",
        "[ssisout].[CustomerRiskDailyStage]",
    )

    exception = flow.derived(
        "DER Missing Country Risk",
        no_match,
        [
            ("ExceptionReason", '"COUNTRY_RISK_NOT_FOUND"', T.wstr(50)),
            ("BatchId", "@[User::BatchId]", T.I8),
            ("LoadUtc", "(DT_DBTIMESTAMP)GETUTCDATE()", T.TIMESTAMP),
        ],
    )
    rejected = flow.row_count("RC Rows Rejected", exception, "User::RowsRejected")
    flow.ole_dest(
        "OLE DST Risk Exceptions",
        rejected,
        "CustomerRiskDb",
        "[ssisout].[TransactionRiskException]",
    )

    merge = package.execute_sql(
        "SQL Merge Daily Risk Summary",
        "CustomerRiskDb",
        "EXEC ssisout.usp_MergeDailyCustomerRiskSummary "
        "@BusinessDate = ?, @BatchId = ?;",
        params=[
            (business_date, "Input", "DATE", "0"),
            ("User::BatchId", "Input", "BIGINT", "1"),
        ],
        description="Merge customer-level daily classifications into the reporting output",
    )
    validate = package.execute_sql(
        "SQL Validate Control Totals",
        "CustomerRiskDb",
        "EXEC audit.usp_ValidatePackageControlTotals "
        "@BusinessDate = ?, @RowsExtracted = ?, @RowsLoaded = ?, @RowsRejected = ?;",
        params=[
            (business_date, "Input", "DATE", "0"),
            ("User::RowsExtracted", "Input", "LONG", "1"),
            ("User::RowsLoaded", "Input", "LONG", "2"),
            ("User::RowsRejected", "Input", "LONG", "3"),
        ],
        description="Fail when source, classified, and exception totals do not reconcile",
    )
    complete = package.execute_sql(
        "SQL Complete Batch",
        "CustomerRiskDb",
        "EXEC audit.usp_CompletePackageRun "
        "@BatchId = ?, @RowsExtracted = ?, @RowsLoaded = ?, @RowsRejected = ?;",
        params=[
            ("User::BatchId", "Input", "BIGINT", "0"),
            ("User::RowsExtracted", "Input", "LONG", "1"),
            ("User::RowsLoaded", "Input", "LONG", "2"),
            ("User::RowsRejected", "Input", "LONG", "3"),
        ],
        description="Close the successful package audit record",
    )
    package.chain(start, clear, data_flow_task, merge, validate, complete)

    return package


def _dtproj() -> str:
    project_guid = guid(PROJECT_NAME, "dtproj")
    return f"""<?xml version="1.0" encoding="utf-8"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <Configuration Condition=" '$(Configuration)' == '' ">Development</Configuration>
    <Name>{PROJECT_NAME}</Name>
    <ProjectGuid>{project_guid}</ProjectGuid>
    <DeploymentModel>Project</DeploymentModel>
    <TargetServerVersion>SQLServer2022</TargetServerVersion>
    <ProtectionLevel>DontSaveSensitive</ProtectionLevel>
  </PropertyGroup>
  <ItemGroup>
    <DtsPackage Include="{PACKAGE_NAME}.dtsx">
      <Name>{PACKAGE_NAME}.dtsx</Name>
    </DtsPackage>
  </ItemGroup>
  <ItemGroup>
    <ProjectParameter Include="Project.params">
      <Name>Project.params</Name>
    </ProjectParameter>
  </ItemGroup>
  <Import Project="$(MSBuildExtensionsPath32)\\Microsoft\\VisualStudio\\v$(VisualStudioVersion)\\SSDT\\Microsoft.Data.Tools.IntegrationServices.targets" />
</Project>
"""


def _solution() -> str:
    project_guid = guid(PROJECT_NAME, "dtproj")
    solution_guid = guid(PROJECT_NAME, "solution")
    return f"""Microsoft Visual Studio Solution File, Format Version 12.00
# Visual Studio Version 17
VisualStudioVersion = 17.0.31903.59
MinimumVisualStudioVersion = 10.0.40219.1
Project("{{159641D6-6404-4A2A-AE62-294DE0FE8301}}") = "{PROJECT_NAME}", "{PROJECT_NAME}.dtproj", "{project_guid}"
EndProject
Global
\tGlobalSection(SolutionConfigurationPlatforms) = preSolution
\t\tDevelopment|Default = Development|Default
\tEndGlobalSection
\tGlobalSection(ProjectConfigurationPlatforms) = postSolution
\t\t{project_guid}.Development|Default.ActiveCfg = Development
\t\t{project_guid}.Development|Default.Build.0 = Development
\tEndGlobalSection
\tGlobalSection(SolutionProperties) = preSolution
\t\tHideSolutionNode = FALSE
\tEndGlobalSection
\tGlobalSection(ExtensibilityGlobals) = postSolution
\t\tSolutionGuid = {solution_guid}
\tEndGlobalSection
EndGlobal
"""


def _inventory(xml_text: str) -> dict:
    root = ET.fromstring(xml_text)
    dts = f"{{{DTS_NS}}}"
    tasks: Counter[str] = Counter()
    for executable in root.iter(f"{dts}Executable"):
        if executable is root:
            continue
        tasks[executable.get(f"{dts}CreationName", "")] += 1
    components = Counter(
        component.get("componentClassID")
        for component in root.iter("component")
    )
    constraints = list(root.iter(f"{dts}PrecedenceConstraint"))
    return {
        "package": PACKAGE_NAME,
        "target_server_version": "SQLServer2022",
        "package_format_version": 8,
        "connection_managers": 1,
        "package_parameters": ["BusinessDate"],
        "user_variables": [
            "BatchId",
            "RowsExtracted",
            "RowsLoaded",
            "RowsRejected",
        ],
        "tasks": dict(sorted(tasks.items())),
        "data_flow_components": dict(sorted(components.items())),
        "precedence_constraints": len(constraints),
        "event_handlers": [],
        "semantic_risk": {
            "component": "LKP Country Risk",
            "requirement": (
                "Lookup no-match rows must be written to "
                "ssisout.TransactionRiskException."
            ),
        },
    }


def _expected_review_queue() -> list[dict[str, str]]:
    return [
        {
            "route": "review_required",
            "task": "DFT Enrich and Classify Transactions / LKP Country Risk",
            "risk": "Lookup no-match behavior and output routing must be preserved.",
            "acceptance": (
                "TransactionId 1006 is written to the exception output and is absent "
                "from classified and summary outputs."
            ),
        },
        {
            "route": "review_required",
            "task": "DFT Enrich and Classify Transactions / CSPL Transaction Risk",
            "risk": (
                "Conditional Split order is significant: HIGH is evaluated before "
                "MANUAL_REVIEW."
            ),
            "acceptance": (
                "Transactions 1002, 1004, and 1005 are HIGH even when another "
                "review condition also applies."
            ),
        },
    ]


def build() -> dict[Path, str]:
    package_xml = _package().to_xml()
    files = {
        PROJECT_DIR / f"{PACKAGE_NAME}.dtsx": package_xml,
        PROJECT_DIR / "Project.params": project_params_xml(PROJECT_PARAMS),
        PROJECT_DIR / f"{PROJECT_NAME}.dtproj": _dtproj(),
        PROJECT_DIR / f"{PROJECT_NAME}.sln": _solution(),
        DEMO_ROOT / "expected" / "inventory.json": (
            json.dumps(_inventory(package_xml), indent=2) + "\n"
        ),
        DEMO_ROOT / "expected" / "baseline.json": (
            json.dumps(BASELINE, indent=2) + "\n"
        ),
        DEMO_ROOT / "expected" / "expected_review_queue.json": (
            json.dumps(_expected_review_queue(), indent=2) + "\n"
        ),
    }
    manifest = {
        "name": PROJECT_NAME,
        "package": PACKAGE_NAME,
        "generator": "tools/generate_demo.py",
        "generated_files": {
            str(path.relative_to(DEMO_ROOT)).replace("\\", "/"): hashlib.sha256(
                text.encode("utf-8")
            ).hexdigest()
            for path, text in sorted(files.items(), key=lambda item: str(item[0]))
        },
    }
    files[DEMO_ROOT / "expected" / "generation_manifest.json"] = (
        json.dumps(manifest, indent=2) + "\n"
    )
    return files


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Fail if committed generated files do not match the generator",
    )
    args = parser.parse_args()

    stale: list[Path] = []
    for path, content in build().items():
        if args.check:
            if not path.exists() or path.read_text(encoding="utf-8") != content:
                stale.append(path)
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8", newline="\n")
        print(f"wrote {path.relative_to(REPO_ROOT)}")

    if stale:
        print("Stale generated files:")
        for path in stale:
            print(f"  {path.relative_to(REPO_ROOT)}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
