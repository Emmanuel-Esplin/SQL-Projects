"""Form parsing and tracking-code normalization."""

from decimal import Decimal

import pytest

from diamond_app.codes import normalize_code
from diamond_app.forms import choice_field, clean, decimal_field, int_field


@pytest.mark.parametrize(("raw", "expected"), [
    (" dc-26-7k3m9q ", "DC-26-7K3M9Q"),
    ("DC267K3M9Q", "DC-26-7K3M9Q"),
    ("DC-26-OIL123", "DC-26-011123"),  # Crockford look-alikes
    ("http://192.0.2.5:8000/d/DC-26-7K3M9Q", "DC-26-7K3M9Q"),
    ("http://host/d/dc-26-7k3m9q?utm=x", "DC-26-7K3M9Q"),
    ("SKU-GIA-12", "SKU-GIA-12"),
    ("", ""),
])
def test_normalize_code(raw, expected):
    assert normalize_code(raw) == expected


def test_clean():
    assert clean("  x ") == "x"
    assert clean("   ") is None
    assert clean(None) is None


@pytest.mark.parametrize(("raw", "expected"), [
    ("1.25", Decimal("1.25")), ("$1,250.50", Decimal("1250.50")), (" 2 ", Decimal("2")),
])
def test_decimal_field_accepts(raw, expected):
    errors: dict = {}
    assert decimal_field(errors, "w", raw, "weight") == expected
    assert errors == {}


@pytest.mark.parametrize(("raw", "kwargs", "message"), [
    ("abc", {}, "as a number"),
    ("NaN", {}, "greater than 0"),
    ("Infinity", {}, "greater than 0"),
    ("0", {}, "greater than 0"),
    ("-1", {"positive": False}, "0 or more"),
    ("1.234", {}, "at most 2 decimal places"),
    ("1000", {"maximum": Decimal("999.99")}, "999.99 or less"),
    ("", {"required": True}, "Enter the weight"),
])
def test_decimal_field_rejects(raw, kwargs, message):
    errors: dict = {}
    assert decimal_field(errors, "w", raw, "weight", **kwargs) is None
    assert message in errors["w"]


def test_decimal_field_optional_blank_is_fine():
    errors: dict = {}
    assert decimal_field(errors, "w", "  ", "weight") is None
    assert errors == {}


def test_choice_field():
    errors: dict = {}
    assert choice_field(errors, "c", "VS1", ("VS1", "VS2"), "clarity") == "VS1"
    assert choice_field(errors, "d", "XX", ("VS1",), "clarity") is None
    assert choice_field(errors, "e", "", ("VS1",), "clarity", required=True) is None
    assert errors == {"d": "Choose a valid clarity.", "e": "Choose the clarity."}


def test_int_field():
    errors: dict = {}
    assert int_field(errors, "a", "42", "lot") == 42
    assert int_field(errors, "b", "4.2", "lot") is None
    assert int_field(errors, "c", None, "lot") is None
    assert errors == {"b": "Choose a valid lot."}
