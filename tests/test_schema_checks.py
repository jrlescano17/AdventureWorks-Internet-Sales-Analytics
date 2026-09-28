from pathlib import Path
import csv
import json

BASE_DIR = Path(__file__).resolve().parent.parent


def _load_json(path: Path):
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def test_raw_headers_match_bronze_quality_config():
    """Validate that raw CSV headers include the required columns defined in
    `config/bronze_quality.json` for each bronze table. Only tables present in the
    quality config are validated; others are skipped.
    """
    bronze_cfg = _load_json(BASE_DIR / "config" / "pipeline" / "bronze.json")
    quality_rules = _load_json(BASE_DIR / "config" / "quality" / "bronze" / "bronze_quality.json")

    bronze_tables = {t["name"]: t for t in bronze_cfg.get("tables", [])}
    assert bronze_tables, "No tables defined in config/pipeline/bronze.json"

    for table_name, schema in quality_rules.items():
        required = schema.get("required", [])
        # Only validate if table declared in bronze config
        if table_name not in bronze_tables:
            continue

        source = BASE_DIR / bronze_tables[table_name]["source"]
        assert source.exists(), f"Source file missing for {table_name}: {source}"

        with source.open("r", encoding="utf-8", newline='') as fh:
            reader = csv.reader(fh)
            try:
                header = next(reader)
            except StopIteration:
                assert False, f"Source file is empty: {source}"

        header_norm = [h.strip().lower() for h in header]
        missing = [col for col in required if col.strip().lower() not in header_norm]

        assert not missing, f"Missing required columns in {source.name}: {missing}"
