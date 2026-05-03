"""Unit tests for ``CoinConverter`` / ``coin_converter``."""

from __future__ import annotations

import pytest

from core.utils.coin_converter import CoinConverter, coin_converter


@pytest.fixture
def cc() -> CoinConverter:
    return CoinConverter()


def test_convert_gp_integer(cc: CoinConverter) -> None:
    assert cc(5, "gp") == 500
    assert cc(1, "gp") == 100


def test_convert_cp(cc: CoinConverter) -> None:
    assert cc(12, "cp") == 12


def test_convert_pp(cc: CoinConverter) -> None:
    assert cc(2, "pp") == 2000


def test_convert_sp_ep(cc: CoinConverter) -> None:
    assert cc(3, "sp") == 30
    assert cc(2, "ep") == 100


def test_string_amount_with_unit(cc: CoinConverter) -> None:
    assert cc("10 gp") == 1000
    assert cc("1 pp") == 1000


def test_invalid_string_raises(cc: CoinConverter) -> None:
    with pytest.raises(ValueError, match="Invalid amount"):
        cc("not-a-number")


def test_invalid_unit_raises(cc: CoinConverter) -> None:
    with pytest.raises(ValueError, match="Invalid unit"):
        cc(5, "btc")


def test_singleton_matches_class(cc: CoinConverter) -> None:
    assert coin_converter(7, "gp") == cc(7, "gp")
