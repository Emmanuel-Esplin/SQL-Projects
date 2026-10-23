from fastapi import APIRouter, Depends, Request

from .. import queries
from ..db import connect, fetch_all
from ..security import CurrentUser, get_current_user
from ..templating import render

router = APIRouter()

TILE_ORDER = ("AVAILABLE", "IN_POLISHING", "IN_REPAIR", "RESERVED", "SOLD")


@router.get("/")
def dashboard(request: Request, user: CurrentUser = Depends(get_current_user)):
    with connect(user.username) as conn:
        summary = fetch_all(conn, "SELECT * FROM v_status_summary")
        holder = user.employee_id if user.role == "POLISHER" else None
        out = queries.stones_out(conn, holder=holder)
        recent = queries.recent_custody(conn, limit=10, holder=holder)
        workload = fetch_all(
            conn,
            "SELECT w.* FROM v_polisher_workload w JOIN (" + queries.POLISHERS_SQL + ") p "
            "ON p.employee_id = w.employee_id ORDER BY w.open_jobs DESC, w.full_name",
        )

    tiles = {status: {"stones": 0, "carat": 0, "value": 0, "unpolished": 0} for status in TILE_ORDER}
    for row in summary:
        tile = tiles.get(row["status"])
        if tile is None:
            continue
        tile["stones"] += row["stones"]
        tile["carat"] += row["total_carat"]
        tile["value"] += row["total_value_usd"]
        if row["polish_state"] == "UNPOLISHED":
            tile["unpolished"] += row["stones"]

    return render(request, "dashboard.html", section="dashboard", title="Dashboard",
                  tiles=tiles, out=out, recent=recent, workload=workload)
