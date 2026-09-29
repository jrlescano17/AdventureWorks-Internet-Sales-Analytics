import pytest

from src.quality.bronze_checks import BronzeQualityError, validate_bronze_file


def _write_csv(path, lines: list[str]):
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return path


# ---------------------------------------------------------------------------
# missing / empty / headerless file
# ---------------------------------------------------------------------------

def test_missing_file_raises_file_not_found_error(tmp_path):
    missing_path = tmp_path / "does_not_exist.csv"

    with pytest.raises(FileNotFoundError):
        validate_bronze_file(missing_path, required_columns=["id"])


def test_empty_file_raises_error(tmp_path):
    file_path = tmp_path / "customers.csv"
    file_path.write_text("", encoding="utf-8")  # 0 bytes, not even a header

    with pytest.raises(BronzeQualityError) as exc_info:
        validate_bronze_file(file_path, required_columns=["id"])

    assert "empty" in str(exc_info.value).lower()


def test_whitespace_only_header_fails_column_check(tmp_path):
    """A file with content (even if the header is just whitespace) doesn't
    trigger the 'empty file' check -- that only fires on 0 bytes on disk. But
    with no real columns in the header, the required-columns check must fail.
    """
    file_path = _write_csv(tmp_path / "customers.csv", ["   ", "1,Ana"])

    with pytest.raises(BronzeQualityError) as exc_info:
        validate_bronze_file(file_path, required_columns=["id", "name"])

    assert "id" in str(exc_info.value)


# ---------------------------------------------------------------------------
# required columns
# ---------------------------------------------------------------------------

def test_detects_missing_columns(tmp_path):
    file_path = _write_csv(
        tmp_path / "customers.csv",
        ["id,name", "1,Ana", "2,Luis"],
    )

    with pytest.raises(BronzeQualityError) as exc_info:
        validate_bronze_file(file_path, required_columns=["id", "name", "email"])

    assert "email" in str(exc_info.value)


def test_passes_when_all_required_columns_present(tmp_path):
    file_path = _write_csv(
        tmp_path / "customers.csv",
        ["id,name,email", "1,Ana,ana@example.com"],
    )

    assert validate_bronze_file(file_path, required_columns=["id", "name"]) is True


def test_passes_with_extra_unrequired_columns(tmp_path):
    file_path = _write_csv(
        tmp_path / "customers.csv",
        ["email,id,name,signup_date", "ana@example.com,1,Ana,2026-01-01"],
    )

    assert validate_bronze_file(file_path, required_columns=["id", "name"]) is True


def test_column_comparison_ignores_case_and_whitespace(tmp_path):
    """Raw CSVs are messy: 'Customer ID', ' id ' or 'ID' must all count as
    the required column 'id'."""
    file_path = _write_csv(
        tmp_path / "customers.csv",
        [" ID , Name ", "1,Ana"],
    )

    assert validate_bronze_file(file_path, required_columns=["id", "name"]) is True


def test_detects_multiple_missing_columns_at_once(tmp_path):
    file_path = _write_csv(
        tmp_path / "customers.csv",
        ["id", "1", "2"],
    )

    with pytest.raises(BronzeQualityError) as exc_info:
        validate_bronze_file(file_path, required_columns=["id", "name", "email"])

    message = str(exc_info.value)
    assert "name" in message
    assert "email" in message