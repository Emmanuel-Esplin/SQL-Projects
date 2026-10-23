"""Tracking codes: DC-<yy>-<6 Crockford base32 chars>, generated in SQL by
fn_new_tracking_code(). This module only normalizes what people type or scan."""

import re

_DC_CODE = re.compile(r"^DC-?(\d{2})-?([0-9A-Z]{6})$")
# Crockford base32 reads look-alike letters as digits
_CROCKFORD_FIXES = str.maketrans({"O": "0", "I": "1", "L": "1"})


def normalize_code(raw: str) -> str:
    """Turn typed or scanned input into a stored code.

    Accepts lower case, spaces, missing dashes, look-alike letters (O/0, I/L/1)
    and a full QR URL such as http://host/d/DC-26-7K3M9Q.
    """
    value = raw.strip()
    if "/d/" in value:
        value = value.rsplit("/d/", 1)[1]
    value = value.split("?", 1)[0].strip().upper().replace(" ", "")
    match = _DC_CODE.match(value)
    if match:
        year, body = match.groups()
        return f"DC-{year}-{body.translate(_CROCKFORD_FIXES)}"
    return value
