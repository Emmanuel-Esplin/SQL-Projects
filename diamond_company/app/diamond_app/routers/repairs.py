from fastapi import APIRouter, Depends, Request

from .. import queries
from ..db import connect, fetch_all
from ..security import SAFE_KEEPER, CurrentUser, require_roles
from ..templating import render

router = APIRouter()


def repairs_page(request: Request, user: CurrentUser, code: str = "", status_code: int = 200, **extra):
    with connect(user.username) as conn:
        context = dict(
            in_repair=queries.stones_out(conn, purposes=("REPAIR",)),
            history=fetch_all(
                conn,
                "SELECT * FROM v_work_order_weights WHERE work_type = 'REPAIR' AND status = 'DONE' "
                "ORDER BY end_date DESC, work_order_id DESC LIMIT 50",
            ),
            employees=queries.active_employees(conn),
            code=code,
        )
    context.update(extra)
    return render(request, "repairs.html", status_code=status_code, section="repairs", title="Repairs", **context)


@router.get("/repairs")
def repairs(request: Request, user: CurrentUser = Depends(require_roles(SAFE_KEEPER))):
    return repairs_page(request, user)
