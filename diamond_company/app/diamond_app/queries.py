"""Read queries shared by several pages. All writes go through procedures."""

from sqlalchemy import Connection, bindparam, text

from .db import fetch_all, fetch_one

DIAMOND_SQL = """
SELECT v.*, d.base_price_per_carat, d.depth_pct, d.table_pct, d.length_mm, d.width_mm, d.depth_mm,
       d.created_at, d.updated_at
FROM v_diamond_4c v
JOIN DIAMONDS d ON d.diamond_id = v.diamond_id
"""

# Employees who can be handed stones: anyone on the payroll marked as a
# polisher, plus employees linked to a POLISHER login
POLISHERS_SQL = """
SELECT e.employee_id, e.full_name
FROM EMPLOYEES e
WHERE e.is_active
  AND (e.role LIKE 'Polisher%' OR EXISTS (SELECT 1 FROM APP_USERS u
                                           WHERE u.employee_id = e.employee_id AND u.role = 'POLISHER'))
ORDER BY e.full_name
"""


def get_diamond(conn: Connection, diamond_id: int) -> dict | None:
    return fetch_one(conn, DIAMOND_SQL + " WHERE v.diamond_id = :id", id=diamond_id)


def get_diamond_by_code(conn: Connection, code: str) -> dict | None:
    return fetch_one(conn, DIAMOND_SQL + " WHERE v.sku = :code", code=code)


def custody_state(conn: Connection, diamond_id: int) -> dict | None:
    """The open check-out for this stone, or None when it is in the safe."""
    return fetch_one(conn, "SELECT * FROM v_stones_out_of_safe WHERE diamond_id = :id", id=diamond_id)


def active_employees(conn: Connection) -> list[dict]:
    return fetch_all(conn, "SELECT employee_id, full_name, role FROM EMPLOYEES WHERE is_active ORDER BY full_name")


def polishers(conn: Connection) -> list[dict]:
    return fetch_all(conn, POLISHERS_SQL)


def stones_out(conn: Connection, purposes: tuple[str, ...] | None = None, holder: int | None = None) -> list[dict]:
    sql = "SELECT * FROM v_stones_out_of_safe WHERE 1 = 1"
    params: dict = {}
    if purposes:
        sql += " AND purpose IN :purposes"
        params["purposes"] = purposes
    if holder:
        sql += " AND holder_employee_id = :holder"
        params["holder"] = holder
    statement = text(sql + " ORDER BY is_overdue DESC, out_since")
    if purposes:
        statement = statement.bindparams(bindparam("purposes", expanding=True))
    return [dict(r) for r in conn.execute(statement, params).mappings()]


def recent_custody(conn: Connection, limit: int = 10, diamond_id: int | None = None,
                   holder: int | None = None) -> list[dict]:
    sql = """
    SELECT ce.event_id, ce.event_type, ce.purpose, ce.weight_carat, ce.occurred_at, ce.notes,
           ce.work_order_id, d.diamond_id, d.sku, u.full_name AS actor_name, e.full_name AS holder_name
    FROM CUSTODY_EVENTS ce
    JOIN DIAMONDS d ON d.diamond_id = ce.diamond_id
    JOIN APP_USERS u ON u.user_id = ce.actor_user_id
    LEFT JOIN EMPLOYEES e ON e.employee_id = ce.holder_employee_id
    WHERE (:diamond_id IS NULL OR ce.diamond_id = :diamond_id)
      AND (:holder IS NULL OR ce.holder_employee_id = :holder)
    ORDER BY ce.event_id DESC
    LIMIT :limit
    """
    return fetch_all(conn, sql, diamond_id=diamond_id, holder=holder, limit=limit)
