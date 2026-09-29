import duckdb
import pytest

from src.quality.silver_checks import SilverQualityError, validate_silver_file


def _infer_type(column: str, values, types: dict) -> str:
    if column in types:
        return types[column]
    for value in values:
        if value is None:
            continue
        if isinstance(value, bool):
            return "BOOLEAN"
        if isinstance(value, int):
            return "BIGINT"
        if isinstance(value, float):
            return "DOUBLE"
        return "VARCHAR"
    return "VARCHAR"


def _write_parquet(path, data: dict, types: dict | None = None):
    types = types or {}
    names = list(data.keys())
    rows = list(zip(*data.values())) if names else []

    column_defs = ", ".join(f"{col} {_infer_type(col, data[col], types)}" for col in names)
    placeholders = ", ".join(["?"] * len(names))

    with duckdb.connect() as con:
        con.execute(f"CREATE TABLE t ({column_defs})")
        if rows:
            con.executemany(f"INSERT INTO t VALUES ({placeholders})", rows)
        con.execute(f"COPY t TO '{path.as_posix()}' (FORMAT PARQUET)")

    return path


# ---------------------------------------------------------------------------
# not_null
# ---------------------------------------------------------------------------

def test_not_null_detects_null_values(tmp_path):
    file_path = _write_parquet(
        tmp_path / "customers.parquet",
        {"id": [1, 2, None], "name": ["Ana", "Luis", "Marta"]},
    )

    with pytest.raises(SilverQualityError) as exc_info:
        validate_silver_file(file_path, {"not_null": ["id"]})

    assert "id" in str(exc_info.value)
    assert "1" in str(exc_info.value)


def test_not_null_passes_without_nulls(tmp_path):
    file_path = _write_parquet(
        tmp_path / "customers.parquet",
        {"id": [1, 2, 3], "name": ["Ana", "Luis", "Marta"]},
    )

    assert validate_silver_file(file_path, {"not_null": ["id", "name"]}) is True


# ---------------------------------------------------------------------------
# unique
# ---------------------------------------------------------------------------

def test_unique_detects_duplicates_single_column(tmp_path):
    file_path = _write_parquet(
        tmp_path / "orders.parquet",
        {"order_id": [1, 2, 2, 3]},
    )

    with pytest.raises(SilverQualityError) as exc_info:
        validate_silver_file(file_path, {"unique": [["order_id"]]})

    assert "order_id" in str(exc_info.value)


def test_unique_allows_repeated_columns_when_combination_is_unique(tmp_path):
    """order_id repeats, but the (order_id, product_id) pair is unique."""
    file_path = _write_parquet(
        tmp_path / "order_items.parquet",
        {
            "order_id": [1, 1, 2],
            "product_id": ["A", "B", "A"],
        },
    )

    assert validate_silver_file(file_path, {"unique": [["order_id", "product_id"]]}) is True


def test_unique_detects_duplicates_in_composite_key(tmp_path):
    file_path = _write_parquet(
        tmp_path / "order_items.parquet",
        {
            "order_id": [1, 1, 2],
            "product_id": ["A", "A", "A"],  # (1, "A") repeats
        },
    )

    with pytest.raises(SilverQualityError):
        validate_silver_file(file_path, {"unique": [["order_id", "product_id"]]})


# ---------------------------------------------------------------------------
# positive
# ---------------------------------------------------------------------------

def test_positive_allows_zero_by_default(tmp_path):
    file_path = _write_parquet(tmp_path / "amounts.parquet", {"amount": [0, 5, 10]})

    rules = {"positive": [{"columns": ["amount"]}]}
    assert validate_silver_file(file_path, rules) is True


def test_positive_rejects_zero_when_allow_zero_is_false(tmp_path):
    file_path = _write_parquet(tmp_path / "amounts.parquet", {"amount": [0, 5, 10]})

    rules = {"positive": [{"columns": ["amount"], "allow_zero": False}]}
    with pytest.raises(SilverQualityError) as exc_info:
        validate_silver_file(file_path, rules)

    assert "amount" in str(exc_info.value)


def test_positive_detects_negative_values(tmp_path):
    file_path = _write_parquet(tmp_path / "amounts.parquet", {"amount": [-1, 5, 10]})

    rules = {"positive": [{"columns": ["amount"], "allow_zero": True}]}
    with pytest.raises(SilverQualityError):
        validate_silver_file(file_path, rules)


# ---------------------------------------------------------------------------
# date_order
# ---------------------------------------------------------------------------

def test_date_order_detects_start_after_end(tmp_path):
    file_path = _write_parquet(
        tmp_path / "orders.parquet",
        {
            "created_at": ["2026-01-10", "2026-01-01"],
            "shipped_at": ["2026-01-01", "2026-01-05"],  # row 1: created > shipped
        },
        types={"created_at": "DATE", "shipped_at": "DATE"},
    )

    rules = {"date_order": [{"start": "created_at", "end": "shipped_at"}]}
    with pytest.raises(SilverQualityError) as exc_info:
        validate_silver_file(file_path, rules)

    assert "created_at" in str(exc_info.value)
    assert "shipped_at" in str(exc_info.value)


def test_date_order_passes_when_dates_are_ordered(tmp_path):
    file_path = _write_parquet(
        tmp_path / "orders.parquet",
        {
            "created_at": ["2026-01-01", "2026-01-02"],
            "shipped_at": ["2026-01-05", "2026-01-02"],  # equal dates are also valid
        },
        types={"created_at": "DATE", "shipped_at": "DATE"},
    )

    rules = {"date_order": [{"start": "created_at", "end": "shipped_at"}]}
    assert validate_silver_file(file_path, rules) is True


# ---------------------------------------------------------------------------
# foreign_keys
# ---------------------------------------------------------------------------
#
# The parent table path is built as
# BASE_DIR / "data" / "silver" / f"{parent_table}.parquet".
# BASE_DIR is monkeypatched to a temp dir so no real data is touched.

def test_foreign_key_detects_orphan_rows(tmp_path, monkeypatch):
    import src.quality.silver_checks as silver_checks

    monkeypatch.setattr(silver_checks, "BASE_DIR", tmp_path)

    silver_dir = tmp_path / "data" / "silver"
    silver_dir.mkdir(parents=True)

    _write_parquet(silver_dir / "customers.parquet", {"customer_id": [1, 2]})
    child_path = _write_parquet(
        silver_dir / "orders.parquet",
        {"order_id": [10, 11], "customer_id": [1, 999]},  # 999 doesn't exist in customers
    )

    rules = {
        "foreign_keys": [
            {"fk_column": "customer_id", "parent_table": "customers", "parent_column": "customer_id"}
        ]
    }

    with pytest.raises(SilverQualityError) as exc_info:
        validate_silver_file(child_path, rules)

    assert "customer_id" in str(exc_info.value)
    assert "customers" in str(exc_info.value)


def test_foreign_key_passes_when_all_keys_exist(tmp_path, monkeypatch):
    import src.quality.silver_checks as silver_checks

    monkeypatch.setattr(silver_checks, "BASE_DIR", tmp_path)

    silver_dir = tmp_path / "data" / "silver"
    silver_dir.mkdir(parents=True)

    _write_parquet(silver_dir / "customers.parquet", {"customer_id": [1, 2]})
    child_path = _write_parquet(
        silver_dir / "orders.parquet",
        {"order_id": [10, 11], "customer_id": [1, 2]},
    )

    rules = {
        "foreign_keys": [
            {"fk_column": "customer_id", "parent_table": "customers", "parent_column": "customer_id"}
        ]
    }

    assert validate_silver_file(child_path, rules) is True


def test_foreign_key_skipped_when_parent_missing(tmp_path, monkeypatch):
    """A missing parent table is skipped with a warning, not treated as a failure."""
    import src.quality.silver_checks as silver_checks

    monkeypatch.setattr(silver_checks, "BASE_DIR", tmp_path)

    silver_dir = tmp_path / "data" / "silver"
    silver_dir.mkdir(parents=True)

    child_path = _write_parquet(
        silver_dir / "orders.parquet",
        {"order_id": [10, 11], "customer_id": [1, 2]},
    )

    rules = {
        "foreign_keys": [
            {"fk_column": "customer_id", "parent_table": "nonexistent_customers", "parent_column": "customer_id"}
        ]
    }

    assert validate_silver_file(child_path, rules) is True


# ---------------------------------------------------------------------------
# Error accumulation and missing-file case
# ---------------------------------------------------------------------------

def test_accumulates_errors_from_multiple_rules_in_one_exception(tmp_path):
    file_path = _write_parquet(
        tmp_path / "orders.parquet",
        {
            "order_id": [1, 1],   # violates 'unique'
            "amount": [-5, 10],   # violates 'positive'
        },
    )

    rules = {
        "unique": [["order_id"]],
        "positive": [{"columns": ["amount"], "allow_zero": True}],
    }

    with pytest.raises(SilverQualityError) as exc_info:
        validate_silver_file(file_path, rules)

    assert len(exc_info.value.errors) == 2


def test_missing_file_raises_file_not_found_error(tmp_path):
    missing_path = tmp_path / "does_not_exist.parquet"

    with pytest.raises(FileNotFoundError):
        validate_silver_file(missing_path, {"not_null": ["id"]})