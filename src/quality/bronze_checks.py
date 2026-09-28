import csv
import json
import logging
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent.parent

logger = logging.getLogger(__name__)


class BronzeQualityError(ValueError):
    """Se lanza al final de la validación con TODOS los errores encontrados."""

    def __init__(self, errors):
        self.errors = list(errors)
        header = f"{len(self.errors)} Bronze validation error(s) found:"
        body = "\n".join(f"  - {e}" for e in self.errors)
        super().__init__(f"{header}\n{body}")


def _load_json(path: Path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def _collect_errors(path: Path, required_columns) -> list:
    """Evalúa un CSV crudo. Asume que el archivo existe."""
    name = path.name

    if path.stat().st_size == 0:
        return [f"[{name}] Raw file is empty: {path}"]

    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.reader(handle)
        try:
            header = next(reader)
        except StopIteration:
            return [f"[{name}] Raw file has no header row: {path}"]

    # Comparación sin distinguir mayúsculas ni espacios: los CSV crudos son sucios.
    normalized = {column.strip().lower() for column in header if column and column.strip()}
    missing = [
        column
        for column in required_columns
        if column.strip().lower() not in normalized
    ]

    if missing:
        return [f"[{name}] Missing required columns: {missing}"]

    return []


def validate_bronze_file(file_path, required_columns):
    """Valida que un CSV Bronze exista, no esté vacío y tenga las columnas requeridas."""
    path = Path(file_path)
    if not path.exists():
        raise FileNotFoundError(f"Raw file not found: {path}")

    errors = _collect_errors(path, required_columns)
    if errors:
        raise BronzeQualityError(errors)
    return True


def validate_bronze_layer(config_path=None, quality_path=None):
    """Valida todas las tablas Bronze declaradas en el config.

    Acumula errores de todos los archivos y lanza un único BronzeQualityError.
    """
    config_path = Path(config_path) if config_path else BASE_DIR / "config" / "pipeline" / "bronze.json"
    quality_path = (
        Path(quality_path)
        if quality_path
        else BASE_DIR / "config" / "quality" / "bronze" / "bronze_quality.json"
    )

    config = _load_json(config_path)
    quality_rules = _load_json(quality_path)

    validated = []
    all_errors = []

    for table in config.get("tables", []):
        table_name = table.get("name")

        if table.get("skip_schema"):
            logger.info("Skipping '%s' (skip_schema).", table_name)
            continue

        required = quality_rules.get(table_name, {}).get("required", [])
        if not required:
            logger.warning("Skipping '%s': no required columns defined.", table_name)
            continue

        source_value = table.get("source")
        if not source_value:
            all_errors.append(f"[{table_name}] No 'source' defined in pipeline config.")
            continue

        source = BASE_DIR / source_value
        if not source.exists():
            all_errors.append(f"[{table_name}] Raw file not found: {source}")
            continue

        table_errors = _collect_errors(source, required)
        if table_errors:
            all_errors.extend(table_errors)
        else:
            validated.append(table_name)

    if all_errors:
        raise BronzeQualityError(all_errors)

    return validated


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    validate_bronze_layer()
    print("Bronze checks passed")