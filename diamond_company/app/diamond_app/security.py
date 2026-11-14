"""Passwords, login sessions, roles and CSRF protection."""

import hashlib
import hmac
import logging
import secrets
import time
from collections import OrderedDict, deque
from collections.abc import Callable
from dataclasses import dataclass
from urllib.parse import urlsplit

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError
from fastapi import Depends, Form, Header, HTTPException, Request
from sqlalchemy import text

from .config import get_settings
from .db import connect, fetch_one

ADMIN, SAFE_KEEPER, POLISHER, SALES = "ADMIN", "SAFE_KEEPER", "POLISHER", "SALES"
ROLES = (ADMIN, SAFE_KEEPER, POLISHER, SALES)
ROLE_LABELS = {ADMIN: "Admin", SAFE_KEEPER: "Safe keeper", POLISHER: "Polisher", SALES: "Sales"}
MIN_PASSWORD_LENGTH = 12
MAX_PASSWORD_LENGTH = 128

security_log = logging.getLogger("diamond_app.security")

_hasher = PasswordHasher()  # argon2id, RFC 9106 low-memory profile
# Verified against when the username does not exist, so a wrong username
# takes as long as a wrong password
_DUMMY_HASH = _hasher.hash(secrets.token_urlsafe(16))


def log_value(value: object, limit: int = 64) -> str:
    """Make user-supplied text safe to log: printable, one line, short."""
    return "".join(c if c.isprintable() else "?" for c in str(value))[:limit]


# ---------------------------------------------------------------------------
# Passwords (NIST SP 800-63B: length over complexity, block known-bad choices)
# ---------------------------------------------------------------------------
_COMMON_PASSWORDS = frozenset({
    "000000000000", "111111111111", "123123123123", "123456789012", "1234567890123", "12345678901234",  # gitleaks:allow
    "abc123456789", "abcdefghijkl", "adminadmin123", "administrator", "changeme1234", "football1234",  # gitleaks:allow
    "iloveyou1234", "letmein12345", "monkey123456", "p@ssw0rd1234", "passw0rd1234", "password1234",  # gitleaks:allow
    "password12345", "password123!", "passwordpassword", "qwerty123456", "qwertyuiop12", "qwertyuiopasdf",  # gitleaks:allow
    "welcome12345", "diamondtracker", "diamond12345", "diamonds1234",  # gitleaks:allow
})


def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password_hash: str, password: str) -> bool:
    try:
        return _hasher.verify(password_hash, password)
    except (VerificationError, InvalidHashError):
        return False


def password_problem(password: str, username: str | None = None) -> str | None:
    if len(password) < MIN_PASSWORD_LENGTH:
        return f"Use at least {MIN_PASSWORD_LENGTH} characters."
    if len(password) > MAX_PASSWORD_LENGTH:
        return f"Use at most {MAX_PASSWORD_LENGTH} characters."
    lowered = password.lower()
    if lowered in _COMMON_PASSWORDS or len(set(lowered)) < 4:
        return "That password is too easy to guess. A short phrase of unrelated words works well."
    if username and len(username) >= 3 and username.lower() in lowered:
        return "Do not include the username in the password."
    return None


# ---------------------------------------------------------------------------
# Login throttling: per username (guessing one account) and per client
# address (spraying many accounts). Memory is bounded.
# ---------------------------------------------------------------------------
class LoginThrottle:
    def __init__(self, max_failures: int, window_s: int, max_keys: int = 10_000):
        self.max_failures = max_failures
        self.window_s = window_s
        self.max_keys = max_keys
        self._hits: OrderedDict[str, deque] = OrderedDict()

    def _recent(self, key: str) -> deque | None:
        hits = self._hits.get(key)
        if hits is None:
            return None
        cutoff = time.monotonic() - self.window_s
        while hits and hits[0] < cutoff:
            hits.popleft()
        if not hits:
            del self._hits[key]
            return None
        return hits

    def blocked(self, key: str) -> bool:
        hits = self._recent(key)
        return hits is not None and len(hits) >= self.max_failures

    def record(self, key: str) -> None:
        hits = self._recent(key)
        if hits is None:
            hits = self._hits[key] = deque(maxlen=self.max_failures)
        hits.append(time.monotonic())
        self._hits.move_to_end(key)
        while len(self._hits) > self.max_keys:
            self._hits.popitem(last=False)  # forget the stalest key

    def clear(self, key: str) -> None:
        self._hits.pop(key, None)


LOCKOUT_MINUTES = 15
_by_username = LoginThrottle(max_failures=5, window_s=LOCKOUT_MINUTES * 60)
_by_address = LoginThrottle(max_failures=20, window_s=LOCKOUT_MINUTES * 60)


def login_locked(username: str, address: str) -> bool:
    return _by_username.blocked(username.lower()) or _by_address.blocked(address)


def record_login_failure(username: str, address: str) -> None:
    _by_username.record(username.lower())
    _by_address.record(address)


def clear_login_failures(username: str) -> None:
    _by_username.clear(username.lower())


def client_address(request: Request) -> str:
    return request.client.host if request.client else "unknown"


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
        if _hasher.check_needs_rehash(user["password_hash"]):
            # Hashing parameters were raised since this password was set
            user["password_hash"] = hash_password(password)
            conn.execute(text("UPDATE APP_USERS SET password_hash = :h WHERE user_id = :id"),
                         {"h": user["password_hash"], "id": user["user_id"]})
        conn.execute(text("UPDATE APP_USERS SET last_login_at = NOW() WHERE user_id = :id"), {"id": user["user_id"]})
        return user


# ---------------------------------------------------------------------------
# Sessions
#
# The session cookie is signed, so its contents cannot be forged. It also
# carries a fingerprint of the password hash: changing a password ends every
# other session of that user. Sessions end after an idle period and after an
# absolute lifetime, whichever comes first.
# ---------------------------------------------------------------------------
_SEEN_RESOLUTION_S = 60  # refresh the idle timer at most once a minute


def _now() -> float:
    """Wall-clock time; sessions outlive server restarts. Tests replace it."""
    return time.time()


def session_fingerprint(password_hash: str) -> str:
    key = get_settings().session_secret.encode()
    return hmac.new(key, password_hash.encode(), hashlib.sha256).hexdigest()[:32]


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


def start_session(request: Request, user: dict) -> None:
    now = int(_now())
    request.session.clear()  # new session on login (no session fixation)
    request.session.update(
        user_id=user["user_id"],
        auth=session_fingerprint(user["password_hash"]),
        iat=now,
        seen=now,
        csrf=secrets.token_urlsafe(32),
    )


def refresh_session_auth(request: Request, password_hash: str) -> None:
    """Keep the current session valid after its own user's password changes."""
    request.session["auth"] = session_fingerprint(password_hash)


def csrf_token(request: Request) -> str:
    if "csrf" not in request.session:
        request.session["csrf"] = secrets.token_urlsafe(32)
    return request.session["csrf"]


def _end_session(request: Request, message: str | None, reason: str) -> None:
    security_log.info("session ended user_id=%s reason=%s", log_value(request.session.get("user_id")), reason)
    request.session.clear()
    if message:
        request.session["flash"] = {"kind": "info", "message": message}
    raise LoginRequired()


def get_current_user(request: Request) -> CurrentUser:
    session = request.session
    user_id = session.get("user_id")
    if not user_id:
        raise LoginRequired()

    settings = get_settings()
    now = int(_now())
    if now - session.get("iat", 0) > settings.session_max_age_hours * 3600:
        _end_session(request, "Your session ended. Log in again to continue.", "max_age")
    if now - session.get("seen", 0) > settings.session_idle_minutes * 60:
        _end_session(request, f"You were logged out after {settings.session_idle_minutes} minutes without activity.",
                     "idle")

    # Re-read on every request so a deactivated user is locked out at once
    with connect() as conn:
        row = fetch_one(
            conn,
            "SELECT user_id, username, full_name, role, employee_id, password_hash FROM APP_USERS "
            "WHERE user_id = :id AND is_active",
            id=user_id,
        )
    if not row:
        _end_session(request, None, "inactive")
    if not hmac.compare_digest(session.get("auth", ""), session_fingerprint(row.pop("password_hash"))):
        _end_session(request, "Your password was changed. Log in with the new password.", "password_changed")

    if now - session.get("seen", 0) >= _SEEN_RESOLUTION_S:
        session["seen"] = now
    user = CurrentUser(**row)
    request.state.user = user
    return user


def require_roles(*roles: str) -> Callable[..., CurrentUser]:
    """Dependency: the user must have one of these roles (Admin always passes)."""

    def checker(user: CurrentUser = Depends(get_current_user)) -> CurrentUser:
        if not user.has(*roles):
            security_log.warning("forbidden user=%s role=%s", log_value(user.username), user.role)
            raise HTTPException(status_code=403, detail="Your role does not allow this action.")
        return user

    return checker


# ---------------------------------------------------------------------------
# CSRF: every state-changing request must come from this site (Fetch
# Metadata / Origin) and echo the session's token. SameSite=Lax on the
# cookie is a third, independent layer.
# ---------------------------------------------------------------------------
_SAFE_METHODS = frozenset({"GET", "HEAD", "OPTIONS"})


def same_origin(request: Request) -> bool:
    site = request.headers.get("sec-fetch-site")
    if site is not None:
        return site in ("same-origin", "none")
    origin = request.headers.get("origin")
    if origin is None:
        return True  # older browsers and non-browser clients: the token still decides
    return urlsplit(origin).netloc.lower() == request.headers.get("host", "").lower()


async def csrf_protect(
    request: Request,
    csrf_token_field: str = Form("", alias="csrf_token"),
    x_csrf_token: str = Header(""),
) -> None:
    """App-wide dependency, applied to every route."""
    if request.method in _SAFE_METHODS:
        return
    if not same_origin(request):
        security_log.warning("cross-site request refused path=%s origin=%s", log_value(request.url.path),
                             log_value(request.headers.get("origin")))
        raise HTTPException(status_code=403, detail="This request came from another website and was refused.")
    expected = request.session.get("csrf", "")
    sent = csrf_token_field or x_csrf_token
    if not expected or not hmac.compare_digest(expected, sent):
        security_log.info("csrf token mismatch path=%s", log_value(request.url.path))
        raise HTTPException(status_code=403, detail="Your form expired. Reload the page and try again.")
