from pathlib import Path
import json

BASE_DIR = Path(__file__).resolve().parents[2]


def _load_json(path: Path):
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def test_every_bronze_table_has_quality_rule():
    bronze = _load_json(BASE_DIR / "config" / "pipeline" / "bronze.json")
    quality_rules = _load_json(BASE_DIR / "config" / "quality" / "bronze" / "bronze_quality.json")

    bronze_tables = [t for t in bronze.get("tables", [])]
    missing = []

    for t in bronze_tables:
        name = t.get("name")
        if t.get("skip_schema"):
            continue
        if name not in quality_rules:
            missing.append(name)

    assert not missing, (
        "The following bronze tables have no quality rule in config/bronze_quality.json: "
        + ", ".join(missing)
    )
