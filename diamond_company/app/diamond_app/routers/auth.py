from urllib.parse import urlsplit

from fastapi import APIRouter, Form, Request
from fastapi.responses import RedirectResponse

from ..security import (
    LOCKOUT_MINUTES,
    authenticate,
    clear_login_failures,
    client_address,
    log_value,
    login_locked,
    record_login_failure,
    security_log,
    start_session,
)
from ..templating import render

router = APIRouter()

# Longer than any password the app accepts, but stops multi-megabyte inputs
# reaching the password hasher
_MAX_LOGIN_PASSWORD = 1024


def safe_next(target: str) -> str:
    """Only same-site paths, which blocks open redirects such as //evil.example.

    Browsers drop tabs and newlines from URLs and read a backslash as a slash,
    so "/\\t/evil.example" would otherwise become "//evil.example".
    """
    if (not target.startswith("/") or len(target) > 2000
            or any(not c.isprintable() or c.isspace() or c == "\\" for c in target)):
        return "/"
    parts = urlsplit(target)
    if parts.scheme or parts.netloc or target.startswith("//"):
        return "/"
    # Rebuilt from a constant "/" so the result can only ever be a path here
    return "/" + target.lstrip("/")


@router.get("/login")
def login_form(request: Request, next: str = "/"):
    if request.session.get("user_id"):
        return RedirectResponse(safe_next(next), status_code=303)
    return render(request, "login.html", title="Log in", next=safe_next(next))


@router.post("/login")
def login(request: Request, username: str = Form(""), password: str = Form(""), next: str = Form("/")):
    username = username.strip()[:60]
    target = safe_next(next)
    address = client_address(request)
    if login_locked(username, address):
        security_log.warning("login refused (locked) user=%s ip=%s", log_value(username), log_value(address))
        return render(request, "login.html", status_code=429, title="Log in", next=target,
                      values={"username": username},
                      errors={"_form": f"Too many failed attempts. Wait {LOCKOUT_MINUTES} minutes, "
                                       "or ask an admin to reset your password."})
    valid_input = username and password and len(password) <= _MAX_LOGIN_PASSWORD
    user = authenticate(username, password) if valid_input else None
    if not user:
        record_login_failure(username, address)
        security_log.warning("login failed user=%s ip=%s", log_value(username), log_value(address))
        return render(request, "login.html", status_code=401, title="Log in", next=target,
                      values={"username": username},
                      errors={"_form": "The username or password is incorrect."})
    clear_login_failures(username)
    start_session(request, user)
    security_log.info("login ok user_id=%s ip=%s", log_value(user["user_id"]), log_value(address))
    return RedirectResponse(target, status_code=303)


@router.post("/logout")
def logout(request: Request):
    security_log.info("logout user_id=%s", log_value(request.session.get("user_id")))
    request.session.clear()
    response = RedirectResponse("/login", status_code=303)
    # Drop cached copies of pages this user saw on a shared computer
    response.headers["Clear-Site-Data"] = '"cache"'
    return response
