"""Test fixtures.

The tests deploy sql/0*.sql, which DROPS and recreates Diamond_company.
Point them only at a throwaway MySQL server, and opt in explicitly:

    DT_TEST_DB_HOST=127.0.0.1 DT_TEST_DB_PORT=33999 DT_TEST_DB_USER=root \
    DT_TEST_ALLOW_RESET=1 .venv/bin/pytest
"""

import os
import re
import secrets
import subprocess
import tempfile
from pathlib import Path

import pytest

SQL_DIR = Path(__file__).resolve().parents[2] / "sql"
PASSWORD = "correct-horse-battery-staple"

if os.environ.get("DT_TEST_ALLOW_RESET") != "1":
    pytest.skip("Set DT_TEST_ALLOW_RESET=1 and point DT_TEST_DB_* at a throwaway MySQL server",
                allow_module_level=True)

DB = {
    "host": os.environ.get("DT_TEST_DB_HOST", "127.0.0.1"),
    "port": os.environ.get("DT_TEST_DB_PORT", "3306"),
    "user": os.environ.get("DT_TEST_DB_USER", "root"),
    "password": os.environ.get("DT_TEST_DB_PASSWORD", ""),
}

# Configure the app before it is imported
os.environ.update(
    DT_DB_HOST=DB["host"], DT_DB_PORT=DB["port"], DT_DB_USER=DB["user"], DT_DB_PASSWORD=DB["password"],
    DT_DB_NAME="Diamond_company", DT_SESSION_SECRET=secrets.token_urlsafe(48),
    DT_STORAGE_DIR=tempfile.mkdtemp(prefix="dt-storage-"), DT_BASE_URL="http://testserver",
)


def _mysql(sql_file: Path) -> None:
    env = {**os.environ, "MYSQL_PWD": DB["password"]}
    with sql_file.open("rb") as handle:
        subprocess.run(["mysql", "-h", DB["host"], "-P", DB["port"], "-u", DB["user"]],
                       stdin=handle, env=env, check=True, capture_output=True)


@pytest.fixture(scope="session", autouse=True)
def database():
    for script in sorted(SQL_DIR.glob("0*.sql")):
        _mysql(script)

    from sqlalchemy import text

    from diamond_app.db import connect
    from diamond_app.security import hash_password

    hashed = hash_password(PASSWORD)
    with connect() as conn:
        for username, role, employee in (("admin", "ADMIN", None), ("keeper", "SAFE_KEEPER", 3),
                                         ("polisher", "POLISHER", 1), ("seller", "SALES", None)):
            conn.execute(text("INSERT INTO APP_USERS (username, full_name, password_hash, role, employee_id) "
                              "VALUES (:u, :n, :h, :r, :e)"),
                         {"u": username, "n": username.title(), "h": hashed, "r": role, "e": employee})
    yield


CSRF_RE = re.compile(r'name="csrf_token" value="([^"]+)"')


class Client:
    """TestClient wrapper that logs in and adds the CSRF token to posts."""

    def __init__(self, username: str | None = None):
        from fastapi.testclient import TestClient

        from diamond_app.main import app

        self.http = TestClient(app, follow_redirects=False)
        self.csrf = None
        if username:
            self.login(username)

    def refresh_csrf(self) -> str:
        page = self.http.get("/login")
        if page.status_code == 303:  # already logged in: read it from any page
            page = self.http.get("/diamonds")
        self.csrf = CSRF_RE.search(page.text).group(1)
        return self.csrf

    def login(self, username: str, password: str = PASSWORD):
        self.refresh_csrf()
        response = self.http.post("/login", data={"username": username, "password": password,
                                                  "csrf_token": self.csrf, "next": "/"})
        if response.status_code == 303:
            self.refresh_csrf()  # the session (and token) is replaced on login
        return response

    def get(self, url: str, **kwargs):
        return self.http.get(url, **kwargs)

    def post(self, url: str, data: dict | None = None, **kwargs):
        return self.http.post(url, data={"csrf_token": self.csrf, **(data or {})}, **kwargs)


@pytest.fixture
def client_for():
    return Client
