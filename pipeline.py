import logging
from pathlib import Path

from src.ingestion import run_ingestion
from src.loading import run_gold
from src.quality import (
    validate_bronze_layer,
    validate_gold_layer,
    validate_silver_layer,
)
from src.quality.bronze_checks import BronzeQualityError
from src.quality.gold_checks import GoldQualityError
from src.quality.silver_checks import SilverQualityError
from src.transformation import run_silver

Path("logs").mkdir(exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(name)s | %(levelname)s | %(message)s",
    handlers=[
        logging.FileHandler("logs/pipeline.log"),
        logging.StreamHandler()
    ]
)

logger = logging.getLogger(__name__)

QUALITY_ERRORS = (BronzeQualityError, SilverQualityError, GoldQualityError)


def run_pipeline():

    try:
        logger.info("========== PIPELINE START ==========")

        # Valida los CSV crudos de origen antes de ingerirlos
        logger.info("Running Bronze quality checks")
        validate_bronze_layer()

        logger.info("Starting ingestion")
        run_ingestion()

        logger.info("Starting silver transformation")
        run_silver()

        # Valida lo que acaba de producir run_silver, antes de construir Gold
        logger.info("Running Silver quality checks")
        validate_silver_layer()

        logger.info("Starting gold loading")
        run_gold()

        logger.info("Running Gold quality checks")
        validate_gold_layer()

        logger.info("========== PIPELINE SUCCESS ==========")

    except QUALITY_ERRORS as e:
        # Fallo de calidad de datos: lo útil es la lista de errores, no el traceback
        logger.error("Pipeline stopped by data quality checks (%d error(s)):", len(e.errors))
        for error in e.errors:
            logger.error("  - %s", error)
        raise

    except Exception:
        # Cualquier otro fallo (bug, archivo corrupto, etc.): aquí sí sirve el traceback
        logger.exception("Pipeline failed with an unexpected error")
        raise


if __name__ == "__main__":
    run_pipeline()