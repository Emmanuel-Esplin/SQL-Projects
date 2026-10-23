"""Passwords, login sessions, roles and CSRF protection."""

import hmac
import secrets
import time
from collections import defaultdict, deque
from dataclasses import dataclass
from typing import Callable

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError
from fastapi import Depends, Form, Header, HTTPException, Request
from sqlalchemy import text

from .db import connect, fetch_one

ADMIN, SAFE_KEEPER, POLISHER, SALES = "ADMIN", "SAFE_KEEPER", "POLISHER", "SALES"
ROLES = (ADMIN, SAFE_KEEPER, POLISHER, SALES)
ROLE_LABELS = {ADMIN: "Admin", SAFE_KEEPER: "Safe keeper", POLISHER: "Polisher", SALES: "Sales"}
MIN_PASSWORD_LENGTH = 12

_hasher = PasswordHasher()  # argon2id with library defaults
# Verified against when the username does not exist, so a wrong username
# takes as long as a wrong password
_DUMMY_HASH = _hasher.hash(secrets.token_urlsafe(16))


def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password_hash: str, password: str) -> bool:
    try:
        return _hasher.verify(password_hash, password)
    except (VerificationError, InvalidHashError):
        return False


def password_problem(password: str) -> str | None:
    if len(password) < MIN_PASSWORD_LENGTH:
        return f"Use at least {MIN_PASSWORD_LENGTH} characters."
    return None


# ---------------------------------------------------------------------------
# Login throttling: at most 5 failures per username per 15 minutes
# ---------------------------------------------------------------------------
_FAILURE_WINDOW_S = 15 * 60
_MAX_FAILURES = 5
_failures: dict[str, deque] = defaultdict(deque)


def login_locked(username: str) -> bool:
    attempts = _failures[username.lower()]
    while attempts and attempts[0] < time.monotonic() - _FAILURE_WINDOW_S:
        attempts.popleft()
    return len(attempts) >= _MAX_FAILURES


def record_login_failure(username: str) -> None:
    _failures[username.lower()].append(time.monotonic())


def clear_login_failures(username: str) -> None:
    _failures.pop(username.lower(), None)


def authenticate(username: str, password: str) -> dict | None:
    with connect() as conn:
        user = fetch_one(
            conn,
            "SELECT user_id, password_hash, is_active FROM APP_USERS WHERE username = :u",
            u=username,
        )
        if not user:
            verify_password(_DUMMY_HASH, password)
            return None
        if not verify_password(user["password_hash"], password) or not user["is_active"]:
            return None
        conn.execute(text("UPDATE APP_USERS SET last_login_at = NOW() WHERE user_id = :id"), {"id": user["user_id"]})
        return user


# ---------------------------------------------------------------------------
# Current user
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class CurrentUser:
    user_id: int
    username: str
    full_name: str
    role: str
    employee_id: int | None

    @property
    def role_label(self) -> str:
        return ROLE_LABELS[self.role]

    def has(self, *roles: str) -> bool:
        return self.role == ADMIN or self.role in roles

    @property
    def sees_prices(self) -> bool:
        return self.role != POLISHER


class LoginRequired(Exception):
    """Raised by dependencies; main.py turns it into a redirect to /login."""


def start_session(request: Request, user_id: int) -> None:
    request.session.clear()  # new session on login (no session fixation)
    request.session["user_id"] = user_id
    request.session["csrf"] = secrets.token_urlsafe(32)


def csrf_token(request: Request) -> str:
    if "csrf" not in request.session:
        request.session["csrf"] = secrets.token_urlsafe(32)
    return request.session["csrf"]


def get_current_user(request: Request) -> CurrentUser:
    user_id = request.session.get("user_id")
    if not user_id:
        raise LoginRequired()
    # Re-read on every request so a deactivated user is locked out at once
    with connect() as conn:
        row = fetch_one(
            conn,
            "SELECT user_id, username, full_name, role, employee_id FROM APP_USERS "
            "WHERE user_id = :id AND is_active",
            id=user_id,
        )
    if not row:
        request.session.clear()
        raise LoginRequired()
    user = CurrentUser(**row)
    request.state.user = user
    return user


def require_roles(*roles: str) -> Callable[..., CurrentUser]:
    """Dependency: the user must have one of these roles (Admin always passes)."""

    def checker(user: CurrentUser = Depends(get_current_user)) -> CurrentUser:
        if not user.has(*roles):
            raise HTTPException(status_code=403, detail="Your role does not allow this action.")
        return user

    return checker


async def csrf_protect(
    request: Request,
    csrf_token_field: str = Form("", alias="csrf_token"),
    x_csrf_token: str = Header(""),
) -> None:
    """App-wide dependency: every POST must echo the session's CSRF token."""
    if request.method != "POST":
        return
    expected = request.session.get("csrf", "")
    sent = csrf_token_field or x_csrf_token
    if not expected or not hmac.compare_digest(expected, sent):
        raise HTTPException(status_code=403, detail="Your form expired. Reload the page and try again.")
