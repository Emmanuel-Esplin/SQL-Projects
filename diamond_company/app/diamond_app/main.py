"""Diamond Tracker - FastAPI application.

Run from diamond_company/app/:
    .venv/bin/uvicorn diamond_app.main:app --host 127.0.0.1 --port 8000
"""

from fastapi import Depends, FastAPI, Request
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles
from starlette.exceptions import HTTPException
from starlette.middleware.sessions import SessionMiddleware

from .config import get_settings
from .routers import admin, auth, certificates, dashboard, diamonds, polishers, repairs, safe, sales
from .security import LoginRequired, csrf_protect
from .templating import PACKAGE_DIR, render

settings = get_settings()

app = FastAPI(
    title="Diamond Tracker",
    docs_url=None,  # no public API docs: this is an internal tool
    redoc_url=None,
    openapi_url=None,
    dependencies=[Depends(csrf_protect)],
)

_SECURITY_HEADERS = {
    "Content-Security-Policy": (
        "default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; "
        "font-src 'self'; object-src 'none'; frame-src 'self'; frame-ancestors 'self'; "
        "base-uri 'self'; form-action 'self'"
    ),
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "same-origin",
    "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
}


@app.middleware("http")
async def security_headers(request: Request, call_next):
    response = await call_next(request)
    for name, value in _SECURITY_HEADERS.items():
        response.headers.setdefault(name, value)
    if request.url.path.startswith(("/diamonds", "/certificates", "/safe", "/sales", "/admin")):
        response.headers.setdefault("Cache-Control", "no-store")
    return response


# Added after the header middleware so it wraps it (sessions are outermost)
app.add_middleware(
    SessionMiddleware,
    secret_key=settings.session_secret,
    session_cookie="dt_session",
    max_age=settings.session_max_age_hours * 3600,
    same_site="lax",
    https_only=settings.secure_cookies,
)

app.mount("/static", StaticFiles(directory=PACKAGE_DIR / "static"), name="static")

for module in (auth, dashboard, diamonds, safe, polishers, repairs, certificates, sales, admin):
    app.include_router(module.router)


@app.exception_handler(LoginRequired)
async def login_required(request: Request, exc: LoginRequired):
    target = request.url.path
    if request.headers.get("HX-Request"):
        response = RedirectResponse("/login", status_code=303)
        response.headers["HX-Redirect"] = "/login"
        return response
    return RedirectResponse(f"/login?next={target}" if target != "/" else "/login", status_code=303)


@app.exception_handler(HTTPException)
async def http_error(request: Request, exc: HTTPException):
    titles = {403: "Not allowed", 404: "Not found"}
    return render(
        request,
        "error.html",
        status_code=exc.status_code,
        title=titles.get(exc.status_code, "Something went wrong"),
        message=exc.detail if isinstance(exc.detail, str) else "The request could not be completed.",
    )
