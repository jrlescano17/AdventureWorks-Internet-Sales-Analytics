from pathlib import Path
import json

from src.quality.bronze_checks import validate_bronze_file

BASE_DIR = Path(__file__).resolve().parent.parent


def _load_json(path: Path):
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def test_raw_files_exist_and_not_empty():
    cfg = _load_json(BASE_DIR / "config" / "pipeline" / "bronze.json")
    quality_rules = _load_json(BASE_DIR / "config" / "quality" / "bronze" / "bronze_quality.json")
    tables = cfg.get("tables", [])
    assert tables, "No tables defined in config/pipeline/bronze.json"

    for table in tables:
        table_name = table.get("name")
        required = quality_rules.get(table_name, {}).get("required", [])
        if not required:
            continue

        source = BASE_DIR / table.get("source", "")
        validate_bronze_file(source, required)
