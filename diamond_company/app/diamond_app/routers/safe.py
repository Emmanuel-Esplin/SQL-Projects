from fastapi import APIRouter, Depends, Form, Request
from fastapi.responses import RedirectResponse

from .. import catalog, queries
from ..codes import normalize_code
from ..db import call_procedure, connect, fetch_one
from ..forms import choice_field, clean, decimal_field, int_field
from ..security import SAFE_KEEPER, CurrentUser, require_roles
from ..templating import flash, render

router = APIRouter()

_RETURN_PAGES = {"/safe", "/repairs"}


def _panel(conn, code: str) -> dict:
    """The stone a code refers to, plus what can be done with it now."""
    if not code:
        return {"stone": None, "code": ""}
    normalized = normalize_code(code)
    stone = queries.get_diamond_by_code(conn, normalized)
    if not stone:
        return {"stone": None, "code": normalized, "not_found": True}
    out = queries.custody_state(conn, stone["diamond_id"])
    last = fetch_one(conn, "SELECT event_type FROM CUSTODY_EVENTS WHERE diamond_id = :id "
                           "ORDER BY event_id DESC LIMIT 1", id=stone["diamond_id"])
    # A sold stone whose last movement was a check-out has gone to its buyer
    delivered = stone["status"] == "SOLD" and last is not None and last["event_type"] == "CHECK_OUT"
    return {"stone": stone, "code": normalized, "out": out, "delivered": delivered}


def _page(request: Request, user: CurrentUser, code: str = "", status_code: int = 200, **extra):
    with connect(user.username) as conn:
        context = _panel(conn, code)
        context.update(
            stones_out=queries.stones_out(conn),
            employees=queries.active_employees(conn),
            polishers=queries.polishers(conn),
        )
    context.update(extra)
    if request.headers.get("HX-Target") == "stone-panel":
        return render(request, "safe/_panel.html", **context)
    return render(request, "safe/index.html", status_code=status_code, section="safe", title="Safe", **context)


@router.get("/safe")
def safe(request: Request, code: str = "", user: CurrentUser = Depends(require_roles(SAFE_KEEPER))):
    return _page(request, user, code)


@router.post("/safe/check-out")
def check_out(
    request: Request,
    code: str = Form(""),
    purpose: str = Form(""),
    holder_employee_id: str = Form(""),
    weight_carat: str = Form(""),
    notes: str = Form(""),
    return_to: str = Form("/safe"),
    user: CurrentUser = Depends(require_roles(SAFE_KEEPER)),
):
    errors: dict[str, str] = {}
    purpose_value = choice_field(errors, "purpose", purpose, catalog.PURPOSES, "reason for taking it out", required=True)
    holder = int_field(errors, "holder_employee_id", holder_employee_id, "employee")
    weight = decimal_field(errors, "weight_carat", weight_carat, "weight on the scale", required=True)
    if purpose_value in ("POLISHING", "REPAIR") and holder is None and "holder_employee_id" not in errors:
        errors["holder_employee_id"] = "Choose who will hold the stone."
    return_to = return_to if return_to in _RETURN_PAGES else "/safe"

    with connect(user.username) as conn:
        stone = queries.get_diamond_by_code(conn, normalize_code(code))
        if not stone:
            errors["code"] = "Scan or type the code of the stone."
        if not errors:
            result = call_procedure(
                conn, "sp_check_out_diamond",
                [stone["diamond_id"], purpose_value, holder, weight, user.user_id, clean(notes)[:500] if clean(notes) else None],
                ["p_work_order_id", "p_success", "p_error_message"],
            )
            if result.ok:
                flash(request, f"{stone['sku']} checked out for {catalog.PURPOSES[purpose_value].lower()}.")
                return RedirectResponse(return_to, status_code=303)
            errors["_form"] = result.error

    values = {"purpose": purpose, "holder_employee_id": holder_employee_id, "weight_carat": weight_carat, "notes": notes}
    if return_to == "/repairs":
        from .repairs import repairs_page

        return repairs_page(request, user, code=code, errors=errors, values=values, status_code=422)
    return _page(request, user, code, status_code=422, errors=errors, values=values)


@router.post("/safe/check-in")
def check_in(
    request: Request,
    code: str = Form(""),
    weight_carat: str = Form(""),
    mark_polished: str = Form(""),
    cut_grade: str = Form(""),
    color_grade: str = Form(""),
    clarity_grade: str = Form(""),
    notes: str = Form(""),
    user: CurrentUser = Depends(require_roles(SAFE_KEEPER)),
):
    errors: dict[str, str] = {}
    weight = decimal_field(errors, "weight_carat", weight_carat, "weight on the scale", required=True)
    polished = mark_polished == "on"
    cut = choice_field(errors, "cut_grade", cut_grade, catalog.CUT_GRADES, "cut grade") if polished else None
    color = choice_field(errors, "color_grade", color_grade, catalog.COLOR_GRADES, "color grade") if polished else None
    clarity = choice_field(errors, "clarity_grade", clarity_grade, catalog.CLARITY_GRADES, "clarity grade") if polished else None

    with connect(user.username) as conn:
        stone = queries.get_diamond_by_code(conn, normalize_code(code))
        if not stone:
            errors["code"] = "Scan or type the code of the stone."
        elif polished:
            if not clarity and "clarity_grade" not in errors:
                errors["clarity_grade"] = "Choose the clarity grade of the polished stone."
            if stone["color_type"] == "WHITE" and not color and "color_grade" not in errors:
                errors["color_grade"] = "Choose the D-Z color grade of the polished stone."
        if not errors:
            result = call_procedure(
                conn, "sp_check_in_diamond",
                [stone["diamond_id"], weight, user.user_id, polished, cut, color, clarity,
                 clean(notes)[:500] if clean(notes) else None],
                ["p_weight_change", "p_success", "p_error_message"],
            )
            if result.ok:
                change = result["p_weight_change"]
                lost = f" Weight removed: {-change:.2f} ct." if change and change < 0 else ""
                flash(request, f"{stone['sku']} is back in the safe.{lost}")
                return RedirectResponse("/safe", status_code=303)
            errors["_form"] = result.error

    values = {"weight_carat": weight_carat, "mark_polished": mark_polished, "cut_grade": cut_grade,
              "color_grade": color_grade, "clarity_grade": clarity_grade, "notes": notes}
    return _page(request, user, code, status_code=422, errors=errors, values=values)
