import duckdb
import pytest

from src.quality.gold_checks import GoldQualityError, validate_gold_file


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
        tmp_path / "dim_customer.parquet",
        {"customer_id": [1, 2, None], "name": ["Ana", "Luis", "Marta"]},
    )

    with pytest.raises(GoldQualityError) as exc_info:
        validate_gold_file(file_path, {"not_null": ["customer_id"]})

    assert "customer_id" in str(exc_info.value)
    assert "1" in str(exc_info.value)


def test_not_null_passes_without_nulls(tmp_path):
    file_path = _write_parquet(
        tmp_path / "dim_customer.parquet",
        {"customer_id": [1, 2, 3], "name": ["Ana", "Luis", "Marta"]},
    )

    assert validate_gold_file(file_path, {"not_null": ["customer_id", "name"]}) is True


# ---------------------------------------------------------------------------
# unique
# ---------------------------------------------------------------------------

def test_unique_detects_duplicates_single_column(tmp_path):
    file_path = _write_parquet(
        tmp_path / "dim_customer.parquet",
        {"customer_id": [1, 2, 2, 3]},
    )

    with pytest.raises(GoldQualityError) as exc_info:
        validate_gold_file(file_path, {"unique": [["customer_id"]]})

    assert "customer_id" in str(exc_info.value)


def test_unique_allows_repeated_columns_when_combination_is_unique(tmp_path):
    """customer_id repeats, but the (customer_id, order_id) pair is unique."""
    file_path = _write_parquet(
        tmp_path / "fact_internet_sales.parquet",
        {
            "customer_id": [1, 1, 2],
            "order_id": [100, 101, 100],
        },
    )

    assert validate_gold_file(
        file_path, {"unique": [["customer_id", "order_id"]]}
    ) is True


def test_unique_detects_duplicates_in_composite_key(tmp_path):
    file_path = _write_parquet(
        tmp_path / "fact_internet_sales.parquet",
        {
            "customer_id": [1, 1, 2],
            "order_id": [100, 100, 100],  # (1, 100) repeats
        },
    )

    with pytest.raises(GoldQualityError):
        validate_gold_file(file_path, {"unique": [["customer_id", "order_id"]]})


# ---------------------------------------------------------------------------
# positive
# ---------------------------------------------------------------------------

def test_positive_allows_zero_by_default(tmp_path):
    file_path = _write_parquet(tmp_path / "fact_internet_sales.parquet", {"sales_amount": [0, 5, 10]})

    rules = {"positive": [{"columns": ["sales_amount"]}]}
    assert validate_gold_file(file_path, rules) is True


def test_positive_rejects_zero_when_allow_zero_is_false(tmp_path):
    file_path = _write_parquet(tmp_path / "fact_internet_sales.parquet", {"sales_amount": [0, 5, 10]})

    rules = {"positive": [{"columns": ["sales_amount"], "allow_zero": False}]}
    with pytest.raises(GoldQualityError) as exc_info:
        validate_gold_file(file_path, rules)

    assert "sales_amount" in str(exc_info.value)


def test_positive_detects_negative_values(tmp_path):
    file_path = _write_parquet(tmp_path / "fact_internet_sales.parquet", {"sales_amount": [-1, 5, 10]})

    rules = {"positive": [{"columns": ["sales_amount"], "allow_zero": True}]}
    with pytest.raises(GoldQualityError):
        validate_gold_file(file_path, rules)


# ---------------------------------------------------------------------------
# foreign_keys
# ---------------------------------------------------------------------------
#
# The parent table path is built as
# BASE_DIR / "data" / "gold" / f"{parent_table}.parquet".

def test_foreign_key_detects_orphan_rows(tmp_path, monkeypatch):
    import src.quality.gold_checks as gold_checks

    monkeypatch.setattr(gold_checks, "BASE_DIR", tmp_path)

    gold_dir = tmp_path / "data" / "gold"
    gold_dir.mkdir(parents=True)

    _write_parquet(gold_dir / "dim_customer.parquet", {"customer_id": [1, 2]})
    child_path = _write_parquet(
        gold_dir / "fact_internet_sales.parquet",
        {"order_id": [10, 11], "customer_id": [1, 999]},  # 999 doesn't exist in dim_customer
    )

    rules = {
        "foreign_keys": [
            {"fk_column": "customer_id", "parent_table": "dim_customer", "parent_column": "customer_id"}
        ]
    }

    with pytest.raises(GoldQualityError) as exc_info:
        validate_gold_file(child_path, rules)

    assert "customer_id" in str(exc_info.value)
    assert "dim_customer" in str(exc_info.value)


def test_foreign_key_passes_when_all_keys_exist(tmp_path, monkeypatch):
    import src.quality.gold_checks as gold_checks

    monkeypatch.setattr(gold_checks, "BASE_DIR", tmp_path)

    gold_dir = tmp_path / "data" / "gold"
    gold_dir.mkdir(parents=True)

    _write_parquet(gold_dir / "dim_customer.parquet", {"customer_id": [1, 2]})
    child_path = _write_parquet(
        gold_dir / "fact_internet_sales.parquet",
        {"order_id": [10, 11], "customer_id": [1, 2]},
    )

    rules = {
        "foreign_keys": [
            {"fk_column": "customer_id", "parent_table": "dim_customer", "parent_column": "customer_id"}
        ]
    }

    assert validate_gold_file(child_path, rules) is True


def test_foreign_key_skipped_when_parent_missing(tmp_path, monkeypatch):
    """A missing parent table is skipped with a warning, not treated as a failure."""
    import src.quality.gold_checks as gold_checks

    monkeypatch.setattr(gold_checks, "BASE_DIR", tmp_path)

    gold_dir = tmp_path / "data" / "gold"
    gold_dir.mkdir(parents=True)

    child_path = _write_parquet(
        gold_dir / "fact_internet_sales.parquet",
        {"order_id": [10, 11], "customer_id": [1, 2]},
    )

    rules = {
        "foreign_keys": [
            {"fk_column": "customer_id", "parent_table": "nonexistent_dim", "parent_column": "customer_id"}
        ]
    }

    assert validate_gold_file(child_path, rules) is True


# ---------------------------------------------------------------------------
# Error accumulation and missing-file case
# ---------------------------------------------------------------------------

def test_accumulates_errors_from_multiple_rules_in_one_exception(tmp_path):
    file_path = _write_parquet(
        tmp_path / "fact_internet_sales.parquet",
        {
            "order_id": [1, 1],        # violates 'unique'
            "sales_amount": [-5, 10],  # violates 'positive'
        },
    )

    rules = {
        "unique": [["order_id"]],
        "positive": [{"columns": ["sales_amount"], "allow_zero": True}],
    }

    with pytest.raises(GoldQualityError) as exc_info:
        validate_gold_file(file_path, rules)

    assert len(exc_info.value.errors) == 2


def test_missing_file_raises_file_not_found_error(tmp_path):
    missing_path = tmp_path / "does_not_exist.parquet"

    with pytest.raises(FileNotFoundError):
        validate_gold_file(missing_path, {"not_null": ["customer_id"]})