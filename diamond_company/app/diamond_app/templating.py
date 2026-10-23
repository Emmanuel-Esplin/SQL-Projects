"""Jinja2 setup: shared helpers available in every template."""

from decimal import Decimal
from functools import lru_cache
from pathlib import Path
from urllib.parse import urlencode

from fastapi import Request
from fastapi.templating import Jinja2Templates
from markupsafe import Markup

from . import catalog
from .security import csrf_token

PACKAGE_DIR = Path(__file__).resolve().parent
templates = Jinja2Templates(directory=PACKAGE_DIR / "templates")


@lru_cache
def icon(name: str, label: str | None = None) -> Markup:
    """Inline a Lucide SVG so it inherits the text color.

    Decorative by default (aria-hidden); pass label for icon-only controls.
    """
    path = PACKAGE_DIR / "static" / "icons" / f"{name}.svg"
    svg = path.read_text().split("-->", 1)[-1].strip()
    a11y = f'role="img" aria-label="{label}"' if label else 'aria-hidden="true" focusable="false"'
    svg = svg.replace("<svg", f'<svg class="icon" {a11y}', 1).replace('class="lucide', 'data-lucide="', 1)
    return Markup(svg)


def money(value) -> str:
    if value is None:
        return "-"
    return f"${Decimal(value):,.2f}"


def carat(value) -> str:
    return "-" if value is None else f"{Decimal(value):.2f} ct"


def color_label(d: dict) -> str:
    if d.get("color_type") == "FANCY":
        return " ".join(x for x in (d.get("fancy_intensity"), d.get("fancy_hue")) if x) or "Fancy"
    return d.get("color_grade") or "-"


def query_with(request: Request, **changes) -> str:
    """Current query string with some parameters replaced (for pagination)."""
    params = dict(request.query_params)
    params.update({k: v for k, v in changes.items() if v is not None})
    return "?" + urlencode(params)


env = templates.env
env.globals.update(
    icon=icon,
    csrf_token=csrf_token,
    catalog=catalog,
    color_label=color_label,
    query_with=query_with,
    zip=zip,
)
env.filters.update(money=money, carat=carat)


def flash(request: Request, message: str, kind: str = "success") -> None:
    """Show a message on the next page rendered (after a redirect)."""
    request.session["flash"] = {"kind": kind, "message": message}


def render(request: Request, name: str, status_code: int = 200, **context):
    context.setdefault("user", getattr(request.state, "user", None))
    context.setdefault("flash", request.session.pop("flash", None))
    context.setdefault("errors", {})
    context.setdefault("values", {})
    return templates.TemplateResponse(request, name, context, status_code=status_code)
