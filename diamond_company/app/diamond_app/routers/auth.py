from fastapi import APIRouter, Form, Request
from fastapi.responses import RedirectResponse

from ..security import (authenticate, clear_login_failures, login_locked, record_login_failure,
                        start_session)
from ..templating import render

router = APIRouter()


def _safe_next(target: str) -> str:
    # Only same-site paths: blocks open redirects such as //evil.example
    if target.startswith("/") and not target.startswith("//") and "\\" not in target:
        return target
    return "/"


@router.get("/login")
def login_form(request: Request, next: str = "/"):
    if request.session.get("user_id"):
        return RedirectResponse(_safe_next(next), status_code=303)
    return render(request, "login.html", next=_safe_next(next))


@router.post("/login")
def login(request: Request, username: str = Form(""), password: str = Form(""), next: str = Form("/")):
    username = username.strip()
    target = _safe_next(next)
    if login_locked(username):
        return render(request, "login.html", status_code=429, next=target, values={"username": username},
                      errors={"_form": "Too many failed attempts. Wait 15 minutes, or ask an admin to reset your password."})
    user = authenticate(username, password) if username and password else None
    if not user:
        record_login_failure(username)
        return render(request, "login.html", status_code=401, next=target, values={"username": username},
                      errors={"_form": "The username or password is incorrect."})
    clear_login_failures(username)
    start_session(request, user["user_id"])
    return RedirectResponse(target, status_code=303)


@router.post("/logout")
def logout(request: Request):
    request.session.clear()
    return RedirectResponse("/login", status_code=303)
