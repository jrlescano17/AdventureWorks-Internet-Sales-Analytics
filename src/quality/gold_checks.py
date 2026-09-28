import json
import logging
from pathlib import Path

import duckdb

BASE_DIR = Path(__file__).resolve().parent.parent.parent

logger = logging.getLogger(__name__)


class GoldQualityError(ValueError):
    """Se lanza al final de la validación con TODOS los errores encontrados."""

    def __init__(self, errors):
        self.errors = list(errors)
        header = f"{len(self.errors)} Gold data quality error(s) found:"
        body = "\n".join(f"  - {e}" for e in self.errors)
        super().__init__(f"{header}\n{body}")


def _load_json(path: Path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def _q(identifier) -> str:
    """Entrecomilla un identificador SQL (columna)."""
    return '"' + str(identifier).replace('"', '""') + '"'


def _count(con, sql: str) -> int:
    return con.execute(sql).fetchone()[0]


def _run_check(errors: list, description: str, fn):
    """Ejecuta una comprobación y registra el error en vez de propagarlo.

    fn() devuelve un mensaje (str) si la regla falla, o None si pasa.
    Si la consulta no se puede ejecutar (p. ej. columna inexistente),
    se registra como error.
    """
    try:
        message = fn()
    except duckdb.Error as exc:
        errors.append(f"{description}: rule could not be evaluated ({exc})")
        return
    if message:
        errors.append(message)


def _collect_errors(path: Path, rules: dict) -> list:
    """Evalúa todas las reglas de una tabla. Asume que el archivo existe."""
    errors: list = []
    name = path.name

    with duckdb.connect() as con:
        table_ref = f"read_parquet('{path.as_posix()}')"

        # --- not_null ---
        for column in rules.get("not_null", []):
            def check(column=column):
                n = _count(con, f"SELECT COUNT(*) FROM {table_ref} WHERE {_q(column)} IS NULL")
                if n:
                    return f"[{name}] Column '{column}' has {n} NULL values."

            _run_check(errors, f"[{name}] not_null '{column}'", check)

        # --- unique (claves simples o compuestas) ---
        for columns in rules.get("unique", []):
            def check(columns=columns):
                cols = ", ".join(_q(c) for c in columns)
                n = _count(
                    con,
                    f"SELECT COUNT(*) FROM ("
                    f"SELECT {cols} FROM {table_ref} GROUP BY {cols} HAVING COUNT(*) > 1"
                    f")",
                )
                if n:
                    return f"[{name}] {n} duplicated key(s) for columns {columns}."

            _run_check(errors, f"[{name}] unique {columns}", check)

        # --- positive ---
        for rule in rules.get("positive", []):
            allow_zero = rule.get("allow_zero", True)
            operator = "<" if allow_zero else "<="
            expected = ">= 0" if allow_zero else "> 0"
            for column in rule.get("columns", []):
                def check(column=column):
                    n = _count(
                        con,
                        f"SELECT COUNT(*) FROM {table_ref} WHERE {_q(column)} {operator} 0",
                    )
                    if n:
                        return f"[{name}] Column '{column}' has {n} invalid values (must be {expected})."

                _run_check(errors, f"[{name}] positive '{column}'", check)

        # --- foreign_keys ---
        for rule in rules.get("foreign_keys", []):
            fk_column = rule.get("fk_column")
            parent_table = rule.get("parent_table")
            parent_column = rule.get("parent_column")
            parent_path = BASE_DIR / "data" / "gold" / f"{parent_table}.parquet"

            if not parent_path.exists():
                logger.warning(
                    "[%s] Skipping FK %s -> %s.%s: parent table not found.",
                    name, fk_column, parent_table, parent_column,
                )
                continue

            def check(fk_column=fk_column, parent_table=parent_table,
                      parent_column=parent_column, parent_path=parent_path):
                n = _count(
                    con,
                    f"SELECT COUNT(*) FROM {table_ref} t "
                    f"LEFT JOIN read_parquet('{parent_path.as_posix()}') p "
                    f"ON t.{_q(fk_column)} = p.{_q(parent_column)} "
                    f"WHERE t.{_q(fk_column)} IS NOT NULL AND p.{_q(parent_column)} IS NULL",
                )
                if n:
                    return (
                        f"[{name}] {n} orphan row(s): {fk_column} -> "
                        f"{parent_table}.{parent_column}."
                    )

            _run_check(errors, f"[{name}] foreign_key {fk_column} -> {parent_table}.{parent_column}", check)

    return errors


def validate_gold_file(file_path, rules=None):
    """Valida una tabla Gold. Lanza GoldQualityError con todos los errores."""
    path = Path(file_path)
    if not path.exists():
        raise FileNotFoundError(f"Gold table not found: {path}")

    errors = _collect_errors(path, rules or {})
    if errors:
        raise GoldQualityError(errors)
    return True


def validate_gold_layer(config_path=None, quality_path=None):
    """Valida todas las tablas Gold declaradas en el config.

    Una tabla con reglas definidas pero sin parquet es un error.
    Acumula errores de todas las tablas y lanza un único GoldQualityError.
    """
    config_path = Path(config_path) if config_path else BASE_DIR / "config" / "pipeline" / "gold.json"
    quality_path = (
        Path(quality_path)
        if quality_path
        else BASE_DIR / "config" / "quality" / "gold" / "gold_quality.json"
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

        rules = quality_rules.get(table_name, {})
        if not rules:
            logger.warning("Skipping '%s': no quality rules defined.", table_name)
            continue

        parquet_file = BASE_DIR / "data" / "gold" / f"{table_name}.parquet"
        if not parquet_file.exists():
            all_errors.append(f"[{table_name}] Gold table not found: {parquet_file}")
            continue

        table_errors = _collect_errors(parquet_file, rules)
        if table_errors:
            all_errors.extend(table_errors)
        else:
            validated.append(table_name)

    if all_errors:
        raise GoldQualityError(all_errors)

    return validated


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    validate_gold_layer()
    print("Gold checks passed")