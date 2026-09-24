from pathlib import Path
import logging
import duckdb

from src.config_utils import load_layer_config, resolve_execution_order

# Configuración de paths
BASE_DIR = Path(__file__).resolve().parent.parent

RAW_PATH = BASE_DIR / "data" / "raw"
BRONZE_PATH = BASE_DIR / "data" / "bronze"

BRONZE_PATH.mkdir(exist_ok=True)


logger = logging.getLogger(__name__)

con = duckdb.connect()

errors = []


def run_ingestion():
    """Ingest raw CSV files into the Bronze layer as Parquet files.

    The function reads the Bronze configuration from the JSON descriptor,
    resolves table ordering by dependencies, and loads each source file into
    Parquet while adding metadata columns for ingestion timestamp and source
    filename.
    """
    try:
        bronze_tables = resolve_execution_order(load_layer_config("bronze"))

        for table in bronze_tables:
            try:
                source_file = BASE_DIR / table["source"]
                output_file = BASE_DIR / table["target"]
                table_name = table["name"]

                logger.info(f"Loading {source_file.name}")

                con.execute(f"""
                    COPY (
                        SELECT
                            *,
                            CURRENT_TIMESTAMP AS _ingestion_ts,
                            '{source_file.name}' AS _source_file
                        FROM read_csv_auto(
                            '{source_file.as_posix()}',
                            ALL_VARCHAR=TRUE
                        )
                    )
                    TO '{output_file.as_posix()}'
                    (FORMAT PARQUET);
                """)

                row_count = con.execute(f"""
                    SELECT COUNT(*)
                    FROM read_parquet('{output_file.as_posix()}')
                """).fetchone()[0]

                logger.info(
                    f"Loaded {row_count} rows from {table_name}"
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
            f"Failed transformations: {errors}"
        )