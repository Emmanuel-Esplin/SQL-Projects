"""HTTP behavior that needs no database: headers, CSRF, hosts, limits, errors.

The login page renders without touching MySQL, so it serves as the probe.
"""

import re

import pytest
from fastapi.testclient import TestClient

from diamond_app.config import Settings, get_settings
from diamond_app.main import BodySizeLimit, app
from diamond_app.templating import icon, static_version

CSRF_RE = re.compile(r'name="csrf_token" value="([^"]+)"')


@pytest.fixture
def client():
    return TestClient(app, follow_redirects=False)


def _token(client: TestClient) -> str:
    return CSRF_RE.search(client.get("/login").text).group(1)


def test_security_headers_on_pages(client):
    response = client.get("/login")
    assert response.status_code == 200
    headers = response.headers
    csp = headers["content-security-policy"]
    for directive in ("default-src 'self'", "script-src 'self'", "style-src 'self'", "object-src 'none'",
                      "frame-ancestors 'self'", "base-uri 'none'", "form-action 'self'"):
        assert directive in csp
    assert "unsafe-inline" not in csp and "unsafe-eval" not in csp
    assert headers["x-content-type-options"] == "nosniff"
    assert headers["x-frame-options"] == "SAMEORIGIN"
    assert headers["referrer-policy"] == "same-origin"
    assert headers["cross-origin-opener-policy"] == "same-origin"
    assert headers["cross-origin-resource-policy"] == "same-origin"
    assert "camera=()" in headers["permissions-policy"]
    assert headers["cache-control"] == "no-store"
    assert "strict-transport-security" not in headers  # HTTP only in tests


def test_session_cookie_flags(client):
    cookie = client.get("/login").headers["set-cookie"].lower()
    assert "dt_session=" in cookie and "httponly" in cookie and "samesite=lax" in cookie and "path=/" in cookie


def test_static_files_are_cached_only_when_versioned(client):
    versioned = client.get(f"/static/css/app.css?v={static_version()}")
    assert versioned.status_code == 200
    assert "immutable" in versioned.headers["cache-control"]
    assert client.get("/static/css/app.css").headers["cache-control"] == "no-cache"
    assert client.get("/static/icons/favicon.svg").status_code == 200


def test_pages_have_no_inline_scripts_or_styles(client):
    html = client.get("/login").text
    assert "style=" not in html
    assert not re.search(r"<script(?![^>]*\bsrc=)[^>]*>", html)
    assert re.search(r'<script src="/static/js/app\.js\?v=\w+">', html)


def test_post_without_token_is_refused(client):
    response = client.post("/login", data={"username": "x", "password": "y"})
    assert response.status_code == 403
    assert response.headers["content-type"].startswith("text/html")


@pytest.mark.parametrize("headers", [
    {"Sec-Fetch-Site": "cross-site"},
    {"Sec-Fetch-Site": "same-site"},
    {"Origin": "https://evil.example"},
    {"Origin": "null"},
])
def test_cross_site_posts_are_refused_before_the_token_check(client, headers):
    token = _token(client)
    response = client.post("/login", data={"username": "x", "password": "y", "csrf_token": token}, headers=headers)
    assert response.status_code == 403
    assert "another website" in response.text


def test_unknown_host_is_refused(client):
    assert client.get("/login", headers={"Host": "evil.example"}).status_code == 400
    assert client.get("/login", headers={"Host": "localhost"}).status_code == 200


def test_oversized_request_is_refused(client):
    token = _token(client)
    big = "x" * (get_settings().max_request_bytes + 1)
    response = client.post("/login", data={"username": big, "password": "y", "csrf_token": token})
    assert response.status_code == 413
    assert "too large" in response.text


def test_unknown_page_is_an_html_404(client):
    response = client.get("/no-such-page")
    assert response.status_code == 404
    assert "Not found" in response.text and response.headers["content-type"].startswith("text/html")


def test_wrong_method_is_a_405_page(client):
    response = client.get("/logout")
    assert response.status_code == 405
    assert response.headers["content-type"].startswith("text/html")


def test_no_api_docs_exposed(client):
    for path in ("/docs", "/redoc", "/openapi.json"):
        assert client.get(path).status_code == 404


def test_unhandled_errors_render_a_page_without_details():
    @app.get("/__boom")
    def boom():
        raise RuntimeError("secret internals")

    try:
        response = TestClient(app, raise_server_exceptions=False).get("/__boom")
        assert response.status_code == 500
        assert "secret internals" not in response.text and "Traceback" not in response.text
        assert "Something went wrong" in response.text
        assert response.headers["content-security-policy"].startswith("default-src 'self'")
    finally:
        app.router.routes[:] = [r for r in app.router.routes if getattr(r, "path", "") != "/__boom"]


def test_body_limit_counts_chunked_bodies():
    """No Content-Length: the limit still applies as the body streams in."""
    import asyncio

    async def endpoint(scope, receive, send):
        while (await receive()).get("more_body"):
            pass
        await send({"type": "http.response.start", "status": 200, "headers": []})
        await send({"type": "http.response.body", "body": b"accepted"})

    chunks = [{"type": "http.request", "body": b"x" * 600, "more_body": True} for _ in range(3)]
    sent = []

    async def receive():
        return chunks.pop() if chunks else {"type": "http.disconnect"}

    async def send(message):
        sent.append(message)

    scope = {"type": "http", "method": "POST", "path": "/login", "headers": [], "query_string": b"",
             "root_path": "", "scheme": "http", "server": ("testserver", 80)}
    asyncio.run(BodySizeLimit(endpoint, max_bytes=1000)(scope, receive, send))
    assert sent[0]["status"] == 413
    assert b"accepted" not in b"".join(m.get("body", b"") for m in sent)


def test_icon_label_is_escaped():
    assert '"><script>' not in icon("gem", '"><script>alert(1)</script>')
    assert 'aria-hidden="true"' in icon("gem")


def test_settings_validation(monkeypatch):
    with pytest.raises(ValueError, match="at least 32"):
        Settings(db_user="u", session_secret="short")
    with pytest.raises(ValueError, match="placeholder"):
        Settings(db_user="u", session_secret="a" * 40)
    settings = Settings(db_user="u", session_secret="k" + "abcdefghijklmnopqrstuvwxyz0123456789",
                        base_url="http://192.0.2.20:8000", allowed_hosts="Tracker.Local, ")
    assert settings.trusted_hosts == ["127.0.0.1", "192.0.2.20", "localhost", "tracker.local"]
