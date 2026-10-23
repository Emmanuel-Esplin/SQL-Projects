"""Database access.

The engine runs in AUTOCOMMIT mode: plain SELECTs read the latest committed
data, and every state change goes through a stored procedure, which manages
its own transaction, retries and locking (see sql/03_stored_procedures.sql).

Each request borrows one connection and sets @app_user on it, so the audit
triggers record who made the change.
"""

import re
from contextlib import contextmanager
from functools import lru_cache
from typing import Any, Iterator

from sqlalchemy import Connection, Engine, create_engine, text
from sqlalchemy.engine import URL

from .config import get_settings

_PROC_NAME = re.compile(r"^sp_[a-z_]+$")

# Friendly wording for CHECK constraints the procedures can surface
_CONSTRAINT_MESSAGES = {
    "ck_d_polished_clarity": "A polished stone needs a clarity grade.",
    "ck_d_white_color": "A polished white stone needs a D-Z color grade.",
    "ck_d_fancy_color": "A fancy-color stone needs a hue and no D-Z color grade.",
    "ck_d_white_no_hue": "A white stone cannot have a fancy hue or intensity.",
}


@lru_cache
def get_engine() -> Engine:
    s = get_settings()
    url = URL.create(
        "mysql+pymysql",
        username=s.db_user,
        password=s.db_password,
        host=s.db_host,
        port=s.db_port,
        database=s.db_name,
        query={"charset": "utf8mb4"},
    )
    return create_engine(url, isolation_level="AUTOCOMMIT", pool_pre_ping=True, pool_recycle=3600)


@contextmanager
def connect(app_user: str | None = None) -> Iterator[Connection]:
    with get_engine().connect() as conn:
        conn.exec_driver_sql("SET @app_user = %s", (app_user,))
        try:
            yield conn
        finally:
            conn.exec_driver_sql("SET @app_user = NULL")


def fetch_all(conn: Connection, sql: str, **params: Any) -> list[dict]:
    return [dict(row) for row in conn.execute(text(sql), params).mappings()]


def fetch_one(conn: Connection, sql: str, **params: Any) -> dict | None:
    row = conn.execute(text(sql), params).mappings().first()
    return dict(row) if row else None


class ProcedureResult(dict):
    """OUT parameters of a procedure call, plus success / error_message."""

    @property
    def ok(self) -> bool:
        return bool(self.get("p_success"))

    @property
    def error(self) -> str:
        message = self.get("p_error_message") or ""
        for constraint, friendly in _CONSTRAINT_MESSAGES.items():
            if constraint in message:
                return friendly
        return message or "The operation could not be completed."


def call_procedure(conn: Connection, name: str, args: list[Any], outs: list[str]) -> ProcedureResult:
    """CALL name(args..., @out1, @out2...) and return the OUT values by name.

    Every procedure in this project ends with p_success and p_error_message.
    """
    if not _PROC_NAME.match(name) or not all(re.match(r"^p_[a-z_]+$", o) for o in outs):
        raise ValueError(f"Unexpected procedure or parameter name: {name}")
    placeholders = ", ".join(["%s"] * len(args) + [f"@{o}" for o in outs])
    conn.exec_driver_sql(f"CALL {name}({placeholders})", tuple(args))
    values = conn.exec_driver_sql("SELECT " + ", ".join(f"@{o}" for o in outs)).fetchone()
    return ProcedureResult(zip(outs, values))
