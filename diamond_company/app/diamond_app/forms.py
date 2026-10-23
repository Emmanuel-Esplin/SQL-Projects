"""Form value parsing. Each helper records a field error instead of raising,
so a form can report every problem at once."""

from decimal import Decimal, InvalidOperation


def clean(value: str | None) -> str | None:
    value = (value or "").strip()
    return value or None


def decimal_field(errors: dict, name: str, raw: str | None, label: str, *, required: bool = False,
                  places: int = 2, positive: bool = True, maximum: Decimal | None = None) -> Decimal | None:
    raw = clean(raw)
    if raw is None:
        if required:
            errors[name] = f"Enter the {label}."
        return None
    try:
        value = Decimal(raw.replace(",", "").replace("$", ""))
    except InvalidOperation:
        errors[name] = f"Enter the {label} as a number, e.g. 1.25."
        return None
    if not value.is_finite() or (positive and value <= 0) or (not positive and value < 0):
        errors[name] = f"The {label} must be {'greater than 0' if positive else '0 or more'}."
        return None
    if -value.as_tuple().exponent > places:
        errors[name] = f"Enter the {label} with at most {places} decimal places."
        return None
    if maximum is not None and value > maximum:
        errors[name] = f"The {label} must be {maximum} or less."
        return None
    return value


def choice_field(errors: dict, name: str, raw: str | None, allowed, label: str, *,
                 required: bool = False) -> str | None:
    raw = clean(raw)
    if raw is None:
        if required:
            errors[name] = f"Choose the {label}."
        return None
    if raw not in allowed:
        errors[name] = f"Choose a valid {label}."
        return None
    return raw


def int_field(errors: dict, name: str, raw: str | None, label: str, *, required: bool = False) -> int | None:
    raw = clean(raw)
    if raw is None:
        if required:
            errors[name] = f"Choose the {label}."
        return None
    try:
        return int(raw)
    except ValueError:
        errors[name] = f"Choose a valid {label}."
        return None
