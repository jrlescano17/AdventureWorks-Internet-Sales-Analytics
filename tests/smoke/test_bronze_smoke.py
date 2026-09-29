"""Smoke test: runs the real Bronze validation against the repository's real
config and CSV files (versioned for project reproducibility).

Unlike test_bronze_rules.py, which uses synthetic CSVs to test each rule in
isolation, this checks the data as it exists today in the repository.
"""

from src.quality.bronze_checks import validate_bronze_layer


def test_bronze_layer_passes_with_real_repository_data():
    validate_bronze_layer()