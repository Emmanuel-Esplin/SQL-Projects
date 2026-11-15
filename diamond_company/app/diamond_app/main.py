"""Diamond Tracker - FastAPI application.

Run from diamond_company/app/:
    .venv/bin/uvicorn diamond_app.main:app --host 127.0.0.1 --port 8000 --no-server-header
"""

import logging

from fastapi import Depends, FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text
from starlette.exceptions import HTTPException
from starlette.middleware.sessions import SessionMiddleware
from starlette.middleware.trustedhost import TrustedHostMiddleware
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from .config import get_settings
from .db import get_engine
from .routers import admin, auth, certificates, dashboard, diamonds, polishers, repairs, safe, sales
from .security import LoginRequired, csrf_protect
from .templating import PACKAGE_DIR, render, templates

settings = get_settings()

log = logging.getLogger("diamond_app")
if not log.handlers:
    _handler = logging.StreamHandler()
    _handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(name)s: %(message)s"))
    log.addHandler(_handler)
    log.setLevel(logging.INFO)

app = FastAPI(
    title="Diamond Tracker",
    docs_url=None,  # no public API docs: this is an internal tool
    redoc_url=None,
    openapi_url=None,
    dependencies=[Depends(csrf_protect)],
)


# ---------------------------------------------------------------------------
# Response headers
# ---------------------------------------------------------------------------
def _csp() -> str:
    directives = [
        "default-src 'self'", "img-src 'self' data:", "style-src 'self'", "script-src 'self'",
        "font-src 'self'", "connect-src 'self'", "object-src 'none'", "worker-src 'none'",
        "frame-src 'self'", "frame-ancestors 'self'", "base-uri 'none'", "form-action 'self'",
    ]
    if settings.secure_cookies:
        directives.append("upgrade-insecure-requests")
    return "; ".join(directives)


SECURITY_HEADERS = {
    "Content-Security-Policy": _csp(),
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "SAMEORIGIN",  # for browsers without frame-ancestors
    "Referrer-Policy": "same-origin",
    "Cross-Origin-Opener-Policy": "same-origin",
    "Cross-Origin-Resource-Policy": "same-origin",
    "Permissions-Policy": ("camera=(), microphone=(), geolocation=(), payment=(), usb=(), serial=(), "
                           "bluetooth=(), browsing-topics=()"),
}
if settings.secure_cookies:
    # Only over HTTPS: tells browsers never to use plain HTTP for this host
    SECURITY_HEADERS["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"


@app.middleware("http")
async def security_headers(request: Request, call_next):
    response = await call_next(request)
    for name, value in SECURITY_HEADERS.items():
        response.headers.setdefault(name, value)
    if request.url.path.startswith("/static/"):
        # Templates add ?v=<content hash>, so a versioned file never changes
        cache = "public, max-age=31536000, immutable" if "v" in request.query_params else "no-cache"
        response.headers.setdefault("Cache-Control", cache)
    else:
        # Pages show stock, prices and custody: never keep them in a cache
        response.headers.setdefault("Cache-Control", "no-store")
    return response


# ---------------------------------------------------------------------------
# Request size: refuse bodies larger than the biggest allowed upload before
# they are spooled to disk
# ---------------------------------------------------------------------------
def standalone_error(request: Request, status_code: int, title: str, message: str):
    """An error page for code running outside the session and header
    middleware (request-size checks, unhandled exceptions)."""
    response = templates.TemplateResponse(
        request, "error.html",
        {"user": None, "flash": None, "errors": {}, "values": {}, "title": title, "message": message},
        status_code=status_code,
    )
    response.headers.update({**SECURITY_HEADERS, "Cache-Control": "no-store"})
    return response


class _BodyTooLarge(Exception):
    pass


class BodySizeLimit:
    """Pure ASGI middleware. A declared Content-Length over the limit is
    refused before the app runs. A streamed body that grows past it is cut
    off, and whatever the app answers is replaced by the same 413 page."""

    def __init__(self, app: ASGIApp, max_bytes: int):
        self.app = app
        self.max_bytes = max_bytes

    async def _reject(self, scope: Scope, receive: Receive, send: Send) -> None:
        limit_mb = self.max_bytes // (1024 * 1024) - 1
        response = standalone_error(Request(scope), 413, "File too large",
                                    f"The upload is too large. Files must be {limit_mb} MB or smaller.")
        response.headers["Connection"] = "close"
        await response(scope, receive, send)

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        declared = dict(scope["headers"]).get(b"content-length", b"0")
        if not declared.isdigit() or int(declared) > self.max_bytes:
            await self._reject(scope, receive, send)
            return

        received = 0
        overflow = False

        async def limited_receive() -> Message:
            nonlocal received, overflow
            message = await receive()
            if message["type"] == "http.request":
                received += len(message.get("body", b""))
                if received > self.max_bytes:
                    overflow = True
                    raise _BodyTooLarge()
            return message

        async def guarded_send(message: Message) -> None:
            if not overflow:
                await send(message)

        try:
            await self.app(scope, limited_receive, guarded_send)
        except Exception:  # noqa: BLE001 - frameworks may wrap our signal in groups or 400s
            if not overflow:
                raise
        if overflow:
            await self._reject(scope, receive, send)


# Middleware added later wraps the earlier ones. From the outside in:
# trusted host -> body size -> session -> security headers -> routes
app.add_middleware(
    SessionMiddleware,
    secret_key=settings.session_secret,
    # The __Host- prefix makes browsers refuse the cookie unless it is Secure,
    # host-only and path=/, so a sibling subdomain cannot plant or read it
    session_cookie="__Host-dt_session" if settings.secure_cookies else "dt_session",
    max_age=settings.session_max_age_hours * 3600,
    same_site="lax",
    https_only=settings.secure_cookies,
)
app.add_middleware(BodySizeLimit, max_bytes=settings.max_request_bytes)
# Rejects requests for other host names (DNS rebinding, Host header attacks)
app.add_middleware(TrustedHostMiddleware, allowed_hosts=settings.trusted_hosts)

app.mount("/static", StaticFiles(directory=PACKAGE_DIR / "static"), name="static")

for module in (auth, dashboard, diamonds, safe, polishers, repairs, certificates, sales, admin):
    app.include_router(module.router)


@app.get("/healthz", include_in_schema=False)
def healthz():
    """Liveness and database check for the container; reveals nothing else."""
    try:
        with get_engine().connect() as conn:
            conn.execute(text("SELECT 1"))
    except Exception:  # noqa: BLE001 - any failure means "not healthy"
        log.exception("health check failed")
        return JSONResponse({"status": "unavailable"}, status_code=503)
    return {"status": "ok"}


# ---------------------------------------------------------------------------
# Errors: friendly HTML pages, never stack traces or framework JSON
# ---------------------------------------------------------------------------
_TITLES = {400: "Bad request", 403: "Not allowed", 404: "Not found", 405: "Not allowed",
           413: "File too large", 422: "Check the request", 429: "Too many requests"}


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
    message = exc.detail if isinstance(exc.detail, str) and exc.status_code != 405 else None
    return render(
        request,
        "error.html",
        status_code=exc.status_code,
        title=_TITLES.get(exc.status_code, "Something went wrong"),
        message=message or "The request could not be completed.",
    )


@app.exception_handler(RequestValidationError)
async def validation_error(request: Request, exc: RequestValidationError):
    # A malformed id in the URL (/diamonds/abc) is a page that does not exist
    if any(error.get("loc", ("",))[0] == "path" for error in exc.errors()):
        return render(request, "error.html", status_code=404, title="Not found",
                      message="That page does not exist.")
    return render(request, "error.html", status_code=422, title="Check the request",
                  message="Some values in the request were not valid. Go back and try again.")


@app.exception_handler(Exception)
async def server_error(request: Request, exc: Exception):
    # Runs outside the session middleware, so render without session data
    log.exception("unhandled error on %s %s", request.method, request.url.path, exc_info=exc)
    return standalone_error(
        request, 500, "Something went wrong",
        "The app hit an unexpected problem. Open the stone or page again to check whether your change was "
        "saved before retrying, and tell an admin if it keeps happening.",
    )
