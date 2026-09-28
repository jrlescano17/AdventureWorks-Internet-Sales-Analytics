from pathlib import Path
import json

BASE_DIR = Path(__file__).resolve().parent.parent


def _load_json(path: Path):
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def _check_sql_references(config_path: Path, key: str = "sql_file"):
    cfg = _load_json(config_path)
    tables = cfg.get("tables", [])
    assert tables is not None, f"No tables list in {config_path}"

    for table in tables:
        if key in table:
            sql_path = BASE_DIR / table.get(key)
            assert sql_path.exists(), f"SQL file missing: {sql_path}"
            assert sql_path.stat().st_size > 0, f"SQL file is empty: {sql_path}"


def test_silver_sql_files_exist():
    _check_sql_references(BASE_DIR / "config" / "pipeline" / "silver.json")


def test_gold_sql_files_exist():
    _check_sql_references(BASE_DIR / "config" / "pipeline" / "gold.json")
