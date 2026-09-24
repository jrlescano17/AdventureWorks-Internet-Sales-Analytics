import re
from pathlib import Path

from src.config_utils import load_layer_config, resolve_execution_order

ROOT = Path(__file__).resolve().parents[1]


def test_gold_execution_order_respects_dependencies():
    """Ensure Gold tables run after their required dependencies are loaded.

    This verifies the dependency graph is respected for the dim-geography and
    customer/fact chain before the fact table executes.
    """
    ordered = resolve_execution_order(load_layer_config("gold"))
    names = [table["name"] for table in ordered]

    assert names.index("dim_geography") > names.index("dim_sales_territory")
    assert names.index("dim_customer") > names.index("dim_geography")
    assert names.index("fact_internet_sales") > names.index("dim_customer")
    assert names[-1] == "fact_internet_sales"


def test_all_silver_tables_are_used_by_gold():
    """Check that every Silver table is actually referenced by Gold SQL.

    This protects against orphaned Silver tables that are not consumed by the
    analytical layer.
    """
    silver_tables = {table["name"] for table in load_layer_config("silver")}
    gold_references = set()

    for sql_file in (ROOT / "sql" / "gold").glob("*.sql"):
        content = sql_file.read_text(encoding="utf-8")
        matches = re.findall(r"data/silver/([A-Za-z0-9_]+)\.parquet", content)
        gold_references.update(matches)

    assert silver_tables == gold_references


def test_all_bronze_tables_are_used_by_silver():
    """Confirm every Bronze source is consumed by the Silver transformation layer.

    This detects stale or unused raw files that are no longer used in the data
    pipeline.
    """
    bronze_tables = {table["name"] for table in load_layer_config("bronze")}
    silver_references = set()

    for sql_file in (ROOT / "sql" / "silver").glob("*.sql"):
        content = sql_file.read_text(encoding="utf-8")
        matches = re.findall(r"data/bronze/([A-Za-z0-9_]+)\.parquet", content)
        silver_references.update(matches)

    assert bronze_tables == silver_references
