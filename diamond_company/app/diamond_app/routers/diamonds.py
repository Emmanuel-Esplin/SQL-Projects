from decimal import Decimal

from fastapi import APIRouter, Depends, Form, HTTPException, Request
from fastapi.responses import RedirectResponse, Response
from sqlalchemy import text

from .. import catalog, queries
from ..codes import normalize_code
from ..db import call_procedure, connect, fetch_all, fetch_one
from ..forms import choice_field, clean, decimal_field, int_field
from ..qr import lookup_url, qr_svg
from ..security import SAFE_KEEPER, SALES, CurrentUser, get_current_user, require_roles
from ..templating import flash, render

router = APIRouter()

PAGE_SIZE = 50
MAX_CARAT = Decimal("999.99")

_FILTERS = {
    "status": catalog.STATUSES,
    "shape": catalog.SHAPES,
    "origin": catalog.ORIGINS,
    "polish_state": catalog.POLISH_STATES,
    "color_type": catalog.COLOR_TYPES,
    "color_grade": catalog.COLOR_GRADES,
    "clarity_grade": catalog.CLARITY_GRADES,
}


# --------------------------------------------------------------------- list

@router.get("/diamonds")
def list_diamonds(request: Request, page: int = 1, q: str = "", user: CurrentUser = Depends(get_current_user)):
    filters = {k: request.query_params.get(k, "") for k in _FILTERS}
    where, params = [], {}
    for column, allowed in _FILTERS.items():
        value = filters[column]
        if value and value in allowed:
            where.append(f"v.{column} = :{column}")
            params[column] = value
    if q.strip():
        where.append("v.sku LIKE :q")
        params["q"] = "%" + normalize_code(q).replace("%", "").replace("_", "") + "%"
    clause = (" WHERE " + " AND ".join(where)) if where else ""
    page = max(page, 1)

    with connect(user.username) as conn:
        total = conn.execute(text("SELECT COUNT(*) FROM v_diamond_4c v" + clause), params).scalar_one()
        rows = fetch_all(
            conn,
            "SELECT v.* FROM v_diamond_4c v" + clause + " ORDER BY v.diamond_id DESC LIMIT :limit OFFSET :offset",
            **params, limit=PAGE_SIZE, offset=(page - 1) * PAGE_SIZE,
        )

    context = dict(section="diamonds", title="Diamonds", rows=rows, total=total, page=page,
                   pages=max(1, -(-total // PAGE_SIZE)), filters=filters, q=q)
    if request.headers.get("HX-Request") and request.headers.get("HX-Target") == "results":
        return render(request, "diamonds/_table.html", **context)
    return render(request, "diamonds/list.html", **context)


@router.get("/search")
def search(code: str = "", user: CurrentUser = Depends(get_current_user)):
    normalized = normalize_code(code)
    if not normalized:
        return RedirectResponse("/diamonds", status_code=303)
    with connect(user.username) as conn:
        found = fetch_one(conn, "SELECT diamond_id FROM DIAMONDS WHERE sku = :c", c=normalized)
    if found:
        return RedirectResponse(f"/diamonds/{found['diamond_id']}", status_code=303)
    return RedirectResponse(f"/diamonds?q={normalized}", status_code=303)


@router.get("/d/{code}")
def qr_lookup(code: str, user: CurrentUser = Depends(get_current_user)):
    """Target of every QR label."""
    with connect(user.username) as conn:
        found = fetch_one(conn, "SELECT diamond_id FROM DIAMONDS WHERE sku = :c", c=normalize_code(code))
    if not found:
        raise HTTPException(404, f"No diamond has the code {normalize_code(code)}.")
    return RedirectResponse(f"/diamonds/{found['diamond_id']}", status_code=303)


# ----------------------------------------------------------------- register

def _form_options(conn) -> dict:
    return {
        "rough_lots": fetch_all(
            conn,
            "SELECT r.rough_id, r.received_date, r.weight_carat, s.name AS supplier "
            "FROM ROUGH_STONES r JOIN SUPPLIERS s ON s.supplier_id = r.supplier_id "
            "ORDER BY r.rough_id DESC LIMIT 200",
        )
    }


@router.get("/diamonds/new")
def new_diamond(request: Request, user: CurrentUser = Depends(require_roles(SAFE_KEEPER))):
    with connect(user.username) as conn:
        options = _form_options(conn)
    values = {"origin": "NATURAL", "color_type": "WHITE", "polish_state": "UNPOLISHED"}
    return render(request, "diamonds/new.html", section="diamonds", title="Register diamond", values=values, **options)


@router.post("/diamonds")
async def create_diamond(request: Request, user: CurrentUser = Depends(require_roles(SAFE_KEEPER))):
    form = await request.form()
    values = {k: (v if isinstance(v, str) else "") for k, v in form.items() if k != "csrf_token"}
    errors: dict[str, str] = {}

    shape = choice_field(errors, "shape", values.get("shape"), catalog.SHAPES, "shape", required=True)
    origin = choice_field(errors, "origin", values.get("origin"), catalog.ORIGINS, "origin", required=True)
    color_type = choice_field(errors, "color_type", values.get("color_type"), catalog.COLOR_TYPES, "color type", required=True)
    polish_state = choice_field(errors, "polish_state", values.get("polish_state"), catalog.POLISH_STATES,
                                "polish state", required=True)
    weight = decimal_field(errors, "carat", values.get("carat"), "weight in carats", required=True, maximum=MAX_CARAT)
    cut = choice_field(errors, "cut_grade", values.get("cut_grade"), catalog.CUT_GRADES, "cut grade")
    clarity = choice_field(errors, "clarity_grade", values.get("clarity_grade"), catalog.CLARITY_GRADES, "clarity grade")
    polished = polish_state == "POLISHED"

    color = hue = intensity = None
    if color_type == "WHITE":
        color = choice_field(errors, "color_grade", values.get("color_grade"), catalog.COLOR_GRADES, "color grade")
        if polished and not color and "color_grade" not in errors:
            errors["color_grade"] = "Choose the D-Z color grade of the polished stone."
    elif color_type == "FANCY":
        hue = clean(values.get("fancy_hue"))
        if not hue:
            errors["fancy_hue"] = "Enter the fancy color hue, e.g. Yellow or Pink."
        elif len(hue) > 40:
            errors["fancy_hue"] = "Keep the hue under 40 characters."
        intensity = choice_field(errors, "fancy_intensity", values.get("fancy_intensity"),
                                 catalog.FANCY_INTENSITIES, "fancy intensity")
        if polished and not intensity and "fancy_intensity" not in errors:
            errors["fancy_intensity"] = "Choose the GIA fancy intensity of the polished stone."
    if polished and not clarity and "clarity_grade" not in errors:
        errors["clarity_grade"] = "Choose the clarity grade of the polished stone."

    price = decimal_field(errors, "price_usd", values.get("price_usd"), "price", positive=False,
                          maximum=Decimal("9999999999.99"))
    base = decimal_field(errors, "base_price_per_carat", values.get("base_price_per_carat"), "price per carat",
                         positive=False, maximum=Decimal("99999999.99"))
    if price is not None and base is not None:
        errors["price_usd"] = "Enter either a total price or a price per carat, not both."

    rough_id = int_field(errors, "rough_id", values.get("rough_id"), "rough lot")
    parent_code = clean(values.get("parent_code"))

    with connect(user.username) as conn:
        parent_id = None
        if parent_code:
            parent = fetch_one(conn, "SELECT diamond_id FROM DIAMONDS WHERE sku = :c", c=normalize_code(parent_code))
            if parent:
                parent_id = parent["diamond_id"]
            else:
                errors["parent_code"] = f"No stone has the code {normalize_code(parent_code)}."
        if rough_id and not fetch_one(conn, "SELECT 1 AS x FROM ROUGH_STONES WHERE rough_id = :r", r=rough_id):
            errors["rough_id"] = "Choose a valid rough lot."

        if not errors:
            result = call_procedure(
                conn, "sp_register_diamond",
                [user.user_id, rough_id, parent_id, shape, origin, color_type, hue, intensity, polish_state,
                 weight, cut, color, clarity, price, base],
                ["p_diamond_id", "p_sku", "p_success", "p_error_message"],
            )
            if result.ok:
                flash(request, f"Registered {result['p_sku']}. Print its label and put it in the safe.")
                return RedirectResponse(f"/diamonds/{result['p_diamond_id']}/label", status_code=303)
            errors["_form"] = result.error

        options = _form_options(conn)
    return render(request, "diamonds/new.html", status_code=422, section="diamonds", title="Register diamond",
                  values=values, errors=errors, **options)


# ------------------------------------------------------------------- detail

def _lineage(conn, diamond_id: int) -> dict:
    """Family tree of the stone: root ancestor and every descendant."""
    root = fetch_one(
        conn,
        """
        WITH RECURSIVE up AS (
          SELECT diamond_id, parent_diamond_id, 0 AS lvl FROM DIAMONDS WHERE diamond_id = :id
          UNION ALL
          SELECT d.diamond_id, d.parent_diamond_id, up.lvl + 1
          FROM DIAMONDS d JOIN up ON d.diamond_id = up.parent_diamond_id
          WHERE up.lvl < 50
        )
        SELECT diamond_id FROM up ORDER BY lvl DESC LIMIT 1
        """,
        id=diamond_id,
    )
    rows = fetch_all(
        conn,
        """
        WITH RECURSIVE down AS (
          SELECT diamond_id, parent_diamond_id, 0 AS depth FROM DIAMONDS WHERE diamond_id = :root
          UNION ALL
          SELECT d.diamond_id, d.parent_diamond_id, down.depth + 1
          FROM DIAMONDS d JOIN down ON d.parent_diamond_id = down.diamond_id
          WHERE down.depth < 50
        )
        SELECT down.depth, d.diamond_id, d.parent_diamond_id, d.sku, d.shape, d.carat, d.polish_state, d.status
        FROM down JOIN DIAMONDS d ON d.diamond_id = down.diamond_id
        ORDER BY down.depth, d.diamond_id
        """,
        root=root["diamond_id"],
    )
    nodes = {r["diamond_id"]: {**r, "children": []} for r in rows}
    for node in nodes.values():
        if node["parent_diamond_id"] in nodes and node["diamond_id"] != root["diamond_id"]:
            nodes[node["parent_diamond_id"]]["children"].append(node)
    return nodes[root["diamond_id"]]


def _load_detail(conn, diamond_id: int) -> dict:
    d = queries.get_diamond(conn, diamond_id)
    if not d:
        raise HTTPException(404, "That diamond does not exist.")
    return {
        "d": d,
        "out": queries.custody_state(conn, diamond_id),
        "lineage": _lineage(conn, diamond_id),
        "rough_lot": fetch_one(
            conn,
            "SELECT r.rough_id, r.received_date, r.weight_carat, s.name AS supplier, s.country "
            "FROM ROUGH_STONES r JOIN SUPPLIERS s ON s.supplier_id = r.supplier_id WHERE r.rough_id = :r",
            r=d["rough_id"],
        ) if d["rough_id"] else None,
        "custody": queries.recent_custody(conn, limit=200, diamond_id=diamond_id),
        "weights": fetch_all(
            conn,
            "SELECT w.*, u.full_name AS recorded_by_name FROM WEIGHT_LOG w "
            "LEFT JOIN APP_USERS u ON u.user_id = w.recorded_by WHERE w.diamond_id = :id ORDER BY w.weight_id",
            id=diamond_id,
        ),
        "work_orders": fetch_all(
            conn, "SELECT * FROM v_work_order_weights WHERE diamond_id = :id ORDER BY work_order_id DESC", id=diamond_id
        ),
        "certificates": fetch_all(
            conn,
            "SELECT c.*, u.full_name AS uploaded_by_name FROM CERTIFICATES c "
            "JOIN APP_USERS u ON u.user_id = c.uploaded_by WHERE c.diamond_id = :id ORDER BY c.certificate_id DESC",
            id=diamond_id,
        ),
        "orders": fetch_all(
            conn,
            "SELECT o.order_id, o.order_date, o.status, oi.price_at_sale, c.full_name AS customer "
            "FROM ORDER_ITEMS oi JOIN ORDERS o ON o.order_id = oi.order_id "
            "JOIN CUSTOMERS c ON c.customer_id = o.customer_id WHERE oi.diamond_id = :id ORDER BY o.order_id DESC",
            id=diamond_id,
        ),
        "audit": fetch_all(
            conn,
            "SELECT action, payload, changed_by, changed_at FROM AUDIT_LOG "
            "WHERE table_name = 'DIAMONDS' AND row_id = :id ORDER BY audit_id DESC LIMIT 25",
            id=diamond_id,
        ),
    }


@router.get("/diamonds/{diamond_id}")
def diamond_detail(request: Request, diamond_id: int, user: CurrentUser = Depends(get_current_user)):
    with connect(user.username) as conn:
        detail = _load_detail(conn, diamond_id)
    return render(request, "diamonds/detail.html", section="diamonds", title=detail["d"]["sku"],
                  qr_target=lookup_url(detail["d"]["sku"]), **detail)


@router.get("/diamonds/{diamond_id}/qr.svg")
def diamond_qr(diamond_id: int, user: CurrentUser = Depends(get_current_user)):
    with connect(user.username) as conn:
        d = fetch_one(conn, "SELECT sku FROM DIAMONDS WHERE diamond_id = :id", id=diamond_id)
    if not d:
        raise HTTPException(404, "That diamond does not exist.")
    return Response(qr_svg(d["sku"]), media_type="image/svg+xml", headers={"Cache-Control": "private, max-age=86400"})


@router.get("/diamonds/{diamond_id}/label")
def diamond_label(request: Request, diamond_id: int, copies: int = 1, user: CurrentUser = Depends(get_current_user)):
    with connect(user.username) as conn:
        d = queries.get_diamond(conn, diamond_id)
    if not d:
        raise HTTPException(404, "That diamond does not exist.")
    return render(request, "diamonds/label.html", section="diamonds", title=f"Label {d['sku']}", d=d,
                  copies=min(max(copies, 1), 24), qr_target=lookup_url(d["sku"]))


# ------------------------------------------------------------ price / split

@router.post("/diamonds/{diamond_id}/price")
def update_price(request: Request, diamond_id: int, price_usd: str = Form(""), recompute: str = Form(""),
                 user: CurrentUser = Depends(require_roles(SAFE_KEEPER, SALES))):
    with connect(user.username) as conn:
        if recompute:
            result = call_procedure(conn, "sp_compute_price", [diamond_id], ["p_success", "p_error_message"])
            flash(request, "Price recalculated from the 4Cs." if result.ok else result.error,
                  "success" if result.ok else "error")
        else:
            errors: dict = {}
            price = decimal_field(errors, "price_usd", price_usd, "price", required=True, positive=False,
                                  maximum=Decimal("9999999999.99"))
            if errors:
                flash(request, errors["price_usd"], "error")
            else:
                # Keep base_price_per_carat consistent, so the audit log records
                # the change and sp_compute_price reproduces this price
                conn.execute(text(
                    "UPDATE DIAMONDS d "
                    "LEFT JOIN CUT cu ON cu.Grade = d.cut_grade "
                    "LEFT JOIN COLOR co ON co.Grade = d.color_grade "
                    "LEFT JOIN CLARITY cl ON cl.Grade = d.clarity_grade "
                    "SET d.price_usd = :p, d.base_price_per_carat = ROUND(:p / (d.carat "
                    "* COALESCE(cu.multiplier, 1) * COALESCE(co.multiplier, 1) * COALESCE(cl.multiplier, 1)), 2) "
                    "WHERE d.diamond_id = :id AND d.status NOT IN ('SOLD', 'SPLIT')"
                ), {"p": price, "id": diamond_id})
                flash(request, "Price updated.")
    return RedirectResponse(f"/diamonds/{diamond_id}", status_code=303)


@router.post("/diamonds/{diamond_id}/split")
def split_diamond(request: Request, diamond_id: int, child_weights: str = Form(""),
                  user: CurrentUser = Depends(require_roles(SAFE_KEEPER))):
    with connect(user.username) as conn:
        result = call_procedure(conn, "sp_split_diamond", [diamond_id, child_weights.strip(), user.user_id],
                                ["p_child_skus", "p_success", "p_error_message"])
    if result.ok:
        flash(request, f"Split into {result['p_child_skus'].replace(',', ', ')}. Print a label for each piece.")
    else:
        flash(request, result.error, "error")
    return RedirectResponse(f"/diamonds/{diamond_id}", status_code=303)
