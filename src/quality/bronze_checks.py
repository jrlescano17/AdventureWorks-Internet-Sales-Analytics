import csv
import json
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent.parent


def _load_json(path: Path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def validate_bronze_file(file_path, required_columns):
    """Validate that a raw Bronze CSV exists, is non-empty, and contains all
    required columns.
    """
    path = Path(file_path)
    if not path.exists():
        raise FileNotFoundError(f"Raw file not found: {path}")
    if path.stat().st_size == 0:
        raise ValueError(f"Raw file is empty: {path}")

    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.reader(handle)
        try:
            header = next(reader)
        except StopIteration as exc:
            raise ValueError(f"Raw file has no header row: {path}") from exc

    normalized = {column.strip().lower() for column in header if column and column.strip()}
    missing = [
        column
        for column in required_columns
        if column.strip().lower() not in normalized
    ]

    if missing:
        raise ValueError(
            f"Missing required columns in {path.name}: {missing}"
        )

    return True


def validate_bronze_layer(config_path=None, quality_path=None):
    """Validate all Bronze tables declared in the pipeline config."""
    config_path = Path(config_path) if config_path else BASE_DIR / "config" / "pipeline" / "bronze.json"
    quality_path = Path(quality_path) if quality_path else BASE_DIR / "config" / "quality" / "bronze" / "bronze_quality.json"

    config = _load_json(config_path)
    quality_rules = _load_json(quality_path)

    validated = []
    tables = config.get("tables", [])

    for table in tables:
        table_name = table.get("name")
        if table.get("skip_schema"):
            continue
        required = quality_rules.get(table_name, {}).get("required", [])
        if not required:
            continue

        source = BASE_DIR / table.get("source", "")
        validate_bronze_file(source, required)
        validated.append(table_name)

    return validated


if __name__ == "__main__":
    validate_bronze_layer()
    print("Bronze checks passed")
