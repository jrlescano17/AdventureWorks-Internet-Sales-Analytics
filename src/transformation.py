from pathlib import Path
import logging
import duckdb

from src.config_utils import load_layer_config, resolve_execution_order


BASE_DIR = Path(__file__).resolve().parent.parent

SILVER_PATH = BASE_DIR / "data" / "silver"
SILVER_SQL_PATH = BASE_DIR / "sql" / "silver"

SILVER_PATH.mkdir(exist_ok=True)


logger = logging.getLogger(__name__)


con = duckdb.connect()

errors = []


def run_silver():
    """Execute the Silver SQL transformations and persist the refined data.

    Each SQL file is read from the Silver configuration, executed against the
    Bronze Parquet dataset, and written to the Silver layer as a Parquet table.
    The execution order is determined by configured dependencies rather than by
    the filename.
    """
    try:
        silver_tables = resolve_execution_order(load_layer_config("silver"))

        for table in silver_tables:
            try:
                sql_file = BASE_DIR / table["sql_file"]
                table_name = table["name"]
                query = sql_file.read_text(
                    encoding="utf-8"
                ).rstrip(";")

                output_file = SILVER_PATH / f"{table_name}.parquet"

                logger.info(f"Transforming {sql_file.name}")

                con.execute(f"""
                    COPY ({query})
                    TO '{output_file}'
                    (FORMAT PARQUET);
                """)

                row_count = con.execute(f"""
                    SELECT COUNT(*) FROM read_parquet('{output_file}')
                """).fetchone()[0]

                logger.info(
                    f"Loaded silver.{table_name}: {row_count} rows"
                )

            except Exception as e:
                logger.error(
                    f"Failed transforming {table['name']}: {e}",
                    exc_info=True
                )
                errors.append(table["name"])

    finally:
        con.close()

    if errors:
        raise RuntimeError(
            f"Transformation finished with {len(errors)} errors"
        )