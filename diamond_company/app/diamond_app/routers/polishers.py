from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import RedirectResponse

from .. import queries
from ..db import connect, fetch_all, fetch_one
from ..security import POLISHER, CurrentUser, get_current_user
from ..templating import render

router = APIRouter()


@router.get("/polishers")
def polishers(request: Request, user: CurrentUser = Depends(get_current_user)):
    if user.role == POLISHER:
        return RedirectResponse(f"/polishers/{user.employee_id}", status_code=303)
    with connect(user.username) as conn:
        workload = fetch_all(
            conn,
            "SELECT w.* FROM v_polisher_workload w JOIN (" + queries.POLISHERS_SQL + ") p "
            "ON p.employee_id = w.employee_id ORDER BY w.full_name",
        )
    return render(request, "polishers/list.html", section="polishers", title="Polishers", workload=workload)


@router.get("/polishers/{employee_id}")
def polisher_detail(request: Request, employee_id: int, user: CurrentUser = Depends(get_current_user)):
    if user.role == POLISHER and user.employee_id != employee_id:
        raise HTTPException(403, "Polishers can only see their own work.")
    with connect(user.username) as conn:
        employee = fetch_one(conn, "SELECT * FROM EMPLOYEES WHERE employee_id = :id", id=employee_id)
        if not employee:
            raise HTTPException(404, "That employee does not exist.")
        context = dict(
            employee=employee,
            totals=fetch_one(conn, "SELECT * FROM v_polisher_workload WHERE employee_id = :id", id=employee_id),
            holding=queries.stones_out(conn, holder=employee_id),
            jobs=fetch_all(
                conn,
                "SELECT w.*, ru.full_name AS released_by, bu.full_name AS returned_by "
                "FROM v_work_order_weights w "
                "LEFT JOIN APP_USERS ru ON ru.user_id = w.released_by_user_id "
                "LEFT JOIN APP_USERS bu ON bu.user_id = w.returned_by_user_id "
                "WHERE w.employee_id = :id ORDER BY w.work_order_id DESC LIMIT 200",
                id=employee_id,
            ),
        )
    return render(request, "polishers/detail.html", section="polishers", title=employee["full_name"], **context)
