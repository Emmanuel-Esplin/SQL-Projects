from fastapi import APIRouter, Depends, Form, Request
from fastapi.responses import RedirectResponse

from .. import catalog, queries
from ..codes import normalize_code
from ..db import call_procedure, connect, fetch_all
from ..forms import int_field
from ..security import SALES, CurrentUser, require_roles
from ..templating import flash, render

router = APIRouter()

ORDER_SQL = """
SELECT o.order_id, o.order_date, o.status, o.total_amount, o.updated_at,
       c.customer_id, c.full_name AS customer,
       d.diamond_id, d.sku, d.shape, d.carat, d.color_type, d.color_grade, d.fancy_hue, d.fancy_intensity,
       d.clarity_grade, d.cut_grade
FROM ORDERS o
JOIN CUSTOMERS c ON c.customer_id = o.customer_id
JOIN ORDER_ITEMS oi ON oi.order_id = o.order_id
JOIN DIAMONDS d ON d.diamond_id = oi.diamond_id
"""


def _page(request: Request, user: CurrentUser, code: str = "", status_code: int = 200, **extra):
    with connect(user.username) as conn:
        stone = queries.get_diamond_by_code(conn, normalize_code(code)) if code else None
        context = dict(
            code=code,
            stone=stone,
            customers=fetch_all(conn, "SELECT customer_id, full_name, email FROM CUSTOMERS ORDER BY full_name"),
            being_sold=fetch_all(conn, ORDER_SQL + " WHERE o.status = 'PENDING' ORDER BY o.order_id DESC"),
            sold=fetch_all(conn, ORDER_SQL + " WHERE o.status IN ('PAID', 'SHIPPED') "
                                             "ORDER BY o.updated_at DESC LIMIT 100"),
        )
    context.update(extra)
    return render(request, "sales.html", status_code=status_code, section="sales", title="Sales", **context)


@router.get("/sales")
def sales(request: Request, code: str = "", user: CurrentUser = Depends(require_roles(SALES))):
    return _page(request, user, code)


@router.post("/sales/reserve")
def reserve(request: Request, code: str = Form(""), customer_id: str = Form(""),
            user: CurrentUser = Depends(require_roles(SALES))):
    errors: dict[str, str] = {}
    customer = int_field(errors, "customer_id", customer_id, "customer", required=True)
    with connect(user.username) as conn:
        stone = queries.get_diamond_by_code(conn, normalize_code(code))
        if not stone:
            errors["code"] = "Scan or type the code of the stone to reserve."
        if not errors:
            result = call_procedure(conn, "sp_place_order", [customer, stone["diamond_id"]],
                                    ["p_order_id", "p_success", "p_error_message"])
            if result.ok:
                flash(request, f"{stone['sku']} reserved on order #{result['p_order_id']}.")
                return RedirectResponse("/sales", status_code=303)
            errors["_form"] = result.error
    return _page(request, user, code, status_code=422, errors=errors,
                 values={"code": code, "customer_id": customer_id})


@router.post("/sales/orders/{order_id}/status")
def set_status(request: Request, order_id: int, status: str = Form(""),
               user: CurrentUser = Depends(require_roles(SALES))):
    if status not in ("PAID", "SHIPPED", "CANCELLED"):
        flash(request, "Choose a valid order status.", "error")
        return RedirectResponse("/sales", status_code=303)
    with connect(user.username) as conn:
        result = call_procedure(conn, "sp_fulfill_order", [order_id, status], ["p_success", "p_error_message"])
    if result.ok:
        flash(request, f"Order #{order_id} marked {catalog.ORDER_STATUSES[status].lower()}.")
    else:
        flash(request, result.error, "error")
    return RedirectResponse("/sales", status_code=303)
