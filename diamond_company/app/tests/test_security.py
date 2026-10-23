"""Logins, roles, CSRF and headers."""

from diamond_app.codes import normalize_code


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


def test_code_normalization():
    assert normalize_code(" dc-26-7k3m9q ") == "DC-26-7K3M9Q"
    assert normalize_code("DC267K3M9Q") == "DC-26-7K3M9Q"
    assert normalize_code("DC-26-OIL123") == "DC-26-011123"
    assert normalize_code("http://192.168.1.5:8000/d/DC-26-7K3M9Q") == "DC-26-7K3M9Q"
    assert normalize_code("SKU-GIA-12") == "SKU-GIA-12"
