from pathlib import Path
import logging
import duckdb

from src.config_utils import load_layer_config, resolve_execution_order


BASE_DIR = Path(__file__).resolve().parent.parent

GOLD_PATH = BASE_DIR / "data" / "gold"
GOLD_SQL_PATH = BASE_DIR / "sql" / "gold"

GOLD_PATH.mkdir(exist_ok=True)


logger = logging.getLogger(__name__)


con = duckdb.connect()

errors = []


def run_gold():
    """Build the Gold analytical layer from the curated Silver tables.

    This function reads the Gold configuration, resolves the dependency graph,
    executes each SQL transformation in order, and writes the resulting
    dimensional and fact tables as Parquet files in the Gold layer.
    """
    try:
        gold_tables = resolve_execution_order(load_layer_config("gold"))

        for table in gold_tables:
            try:
                sql_file = BASE_DIR / table["sql_file"]
                table_name = table["name"]
                query = sql_file.read_text(
                    encoding="utf-8"
                ).rstrip(";")

                output_file = GOLD_PATH / f"{table_name}.parquet"

                logger.info(f"Loading {sql_file.name}")

                con.execute(f"""
                    COPY ({query})
                    TO '{output_file}'
                    (FORMAT PARQUET);
                """)

                row_count = con.execute(f"""
                    SELECT COUNT(*) FROM read_parquet('{output_file}')
                """).fetchone()[0]

                logger.info(
                    f"Loaded gold.{table_name}: {row_count} rows"
                )

            except Exception as e:
                logger.error(
                    f"Failed loading {table['name']}: {e}",
                    exc_info=True
                )
                errors.append(table["name"])

    finally:
        con.close()

    if errors:
        raise RuntimeError(
            f"Loading finished with {len(errors)} errors"
        )