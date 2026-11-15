"""Logins, sessions, roles, CSRF and headers, against the real database."""

import time

from diamond_app.db import connect, fetch_one

from .conftest import PASSWORD

NEW_PASSWORD = "plum-orbit-candle-harbor"


def _user_id(username: str) -> int:
    with connect() as conn:
        return fetch_one(conn, "SELECT user_id FROM APP_USERS WHERE username = :u", u=username)["user_id"]


def test_pages_require_login(client_for):
    anon = client_for()
    for url in ("/", "/diamonds", "/safe", "/admin", "/certificates/1/file", "/d/DC-26-AAAAAA"):
        response = anon.get(url)
        assert response.status_code == 303, url
        assert response.headers["location"].startswith("/login")


def test_wrong_password_is_rejected(client_for):
    response = client_for().login("keeper", "not-the-password")
    assert response.status_code == 401
    assert "incorrect" in response.text


def test_unknown_user_gets_same_message(client_for):
    response = client_for().login("nobody-here", "whatever-password")
    assert response.status_code == 401
    assert "incorrect" in response.text


def test_login_redirect_cannot_leave_the_site(client_for):
    client = client_for()
    client.refresh_csrf()
    response = client.http.post("/login", data={"username": "keeper", "password": "correct-horse-battery-staple",
                                                "csrf_token": client.csrf, "next": "//evil.example/steal"})
    assert response.status_code == 303
    assert response.headers["location"] == "/"


def test_post_without_csrf_token_is_refused(client_for):
    client = client_for("keeper")
    response = client.http.post("/safe/check-out", data={"code": "x"})
    assert response.status_code == 403
    response = client.http.post("/safe/check-out", data={"code": "x", "csrf_token": "forged"})
    assert response.status_code == 403


def test_roles_limit_pages(client_for):
    polisher, seller, keeper = client_for("polisher"), client_for("seller"), client_for("keeper")
    assert polisher.get("/safe").status_code == 403
    assert polisher.get("/sales").status_code == 403
    assert polisher.get("/admin").status_code == 403
    assert polisher.get("/diamonds/new").status_code == 403
    assert seller.get("/safe").status_code == 403
    assert seller.get("/diamonds/new").status_code == 403
    assert keeper.get("/admin").status_code == 403
    assert keeper.get("/sales").status_code == 403
    assert client_for("admin").get("/admin").status_code == 200


def test_polisher_sees_only_own_page_and_no_prices(client_for):
    polisher = client_for("polisher")
    assert polisher.get("/polishers").headers["location"] == "/polishers/1"
    assert polisher.get("/polishers/1").status_code == 200
    assert polisher.get("/polishers/2").status_code == 403
    listing = polisher.get("/diamonds")
    assert listing.status_code == 200
    assert "Price" not in listing.text and "$" not in listing.text


def test_security_headers(client_for):
    response = client_for("keeper").get("/")
    assert "default-src 'self'" in response.headers["content-security-policy"]
    assert response.headers["x-content-type-options"] == "nosniff"
    cookie = response.headers.get("set-cookie", "")
    assert "dt_session" not in cookie or "httponly" in cookie.lower()


def test_deactivated_user_is_logged_out(client_for):
    from diamond_app.db import connect, fetch_one

    with connect() as conn:
        seller_id = fetch_one(conn, "SELECT user_id FROM APP_USERS WHERE username = 'seller'")["user_id"]
    admin, seller = client_for("admin"), client_for("seller")
    assert seller.get("/").status_code == 200
    assert admin.post(f"/admin/users/{seller_id}/active", {"active": "0"}).status_code == 303
    assert seller.get("/").status_code == 303  # session no longer valid
    admin.post(f"/admin/users/{seller_id}/active", {"active": "1"})


def test_admin_cannot_deactivate_self(client_for):
    from diamond_app.db import connect, fetch_one

    with connect() as conn:
        admin_id = fetch_one(conn, "SELECT user_id FROM APP_USERS WHERE username = 'admin'")["user_id"]
    admin = client_for("admin")
    admin.post(f"/admin/users/{admin_id}/active", {"active": "0"})
    assert admin.get("/").status_code == 200


def test_login_redirect_ignores_tab_and_backslash_tricks(client_for):
    for target in ("/\t/evil.example", "/\\evil.example", "/%0a/evil", "https://evil.example/"):
        client = client_for()
        client.refresh_csrf()
        response = client.http.post("/login", data={"username": "keeper", "password": PASSWORD,
                                                    "csrf_token": client.csrf, "next": target})
        assert response.status_code == 303
        assert response.headers["location"] in ("/", target) and not response.headers["location"].startswith("//")
        assert "evil.example" not in response.headers["location"]


def test_cross_site_post_is_refused_even_with_token(client_for):
    keeper = client_for("keeper")
    response = keeper.post("/safe/check-out", {"code": "x"}, headers={"Sec-Fetch-Site": "cross-site"})
    assert response.status_code == 403
    assert "another website" in response.text
    response = keeper.post("/safe/check-out", {"code": "x"}, headers={"Origin": "https://evil.example"})
    assert response.status_code == 403
    # The same request from this site gets through to validation
    response = keeper.post("/safe/check-out", {"code": "x"}, headers={"Sec-Fetch-Site": "same-origin"})
    assert response.status_code == 422


def test_password_reset_ends_that_users_sessions(client_for):
    seller_id = _user_id("seller")
    admin, seller = client_for("admin"), client_for("seller")
    assert seller.get("/").status_code == 200
    try:
        assert admin.post(f"/admin/users/{seller_id}/password", {"password": NEW_PASSWORD}).status_code == 303
        response = seller.get("/")
        assert response.status_code == 303 and response.headers["location"].startswith("/login")
        assert "password was changed" in seller.get("/login").text
        assert client_for().login("seller", NEW_PASSWORD).status_code == 303
        assert client_for().login("seller", PASSWORD).status_code == 401
    finally:
        admin.post(f"/admin/users/{seller_id}/password", {"password": PASSWORD})


def test_changing_own_password_keeps_current_session(client_for):
    admin_id = _user_id("admin")
    admin, other_admin_session = client_for("admin"), client_for("admin")
    try:
        admin.post(f"/admin/users/{admin_id}/password", {"password": NEW_PASSWORD})
        assert admin.get("/admin").status_code == 200
        assert other_admin_session.get("/admin").status_code == 303
    finally:
        admin.post(f"/admin/users/{admin_id}/password", {"password": PASSWORD})


def test_weak_passwords_are_refused(client_for):
    admin = client_for("admin")
    for password, message in (("short", "at least 12"), ("password1234", "too easy"),
                              ("newbie-is-my-name", "username")):
        response = admin.post("/admin/users", {"username": "newbie", "full_name": "New Bie", "role": "SALES",
                                               "password": password})
        assert response.status_code == 422, password
        assert message in response.text, password


def test_idle_session_expires(client_for, monkeypatch):
    from diamond_app import security
    from diamond_app.config import get_settings

    keeper = client_for("keeper")
    assert keeper.get("/").status_code == 200
    later = time.time() + get_settings().session_idle_minutes * 60 + 5
    monkeypatch.setattr(security, "_now", lambda: later)
    response = keeper.get("/")
    assert response.status_code == 303
    assert "without activity" in keeper.get("/login").text


def test_one_address_cannot_spray_many_accounts(client_for):
    client = client_for()
    for n in range(20):
        client.login(f"nobody-{n}", "wrong-password-here")
    response = client.login("keeper", PASSWORD)  # right password, but this address is throttled
    assert response.status_code == 429


def test_bad_id_in_url_is_an_html_404(client_for):
    response = client_for("keeper").get("/diamonds/not-a-number")
    assert response.status_code == 404
    assert response.headers["content-type"].startswith("text/html")


def test_health_check_reaches_the_database(client_for):
    response = client_for().get("/healthz")
    assert response.status_code == 200 and response.json() == {"status": "ok"}


def test_logout_clears_cached_pages(client_for):
    keeper = client_for("keeper")
    response = keeper.post("/logout")
    assert response.status_code == 303
    assert response.headers["clear-site-data"] == '"cache"'
    assert keeper.get("/").status_code == 303
