import logging
from pathlib import Path

from src.ingestion import run_ingestion
from src.transformation import run_silver
from src.loading import run_gold

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


def run_pipeline():

    try:
        logger.info("========== PIPELINE START ==========")

        logger.info("Starting ingestion")
        run_ingestion()

        logger.info("Starting silver transformation")
        run_silver()

        logger.info("Starting gold loading")
        run_gold()

        logger.info("========== PIPELINE SUCCESS ==========")

    except Exception as e:
        logger.error(
            f"Pipeline failed: {e}",
            exc_info=True
        )
        raise


if __name__ == "__main__":
    run_pipeline()