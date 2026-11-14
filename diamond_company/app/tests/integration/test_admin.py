"""Admin reference data: users, employees, customers, suppliers and rough lots."""

from diamond_app.db import connect, fetch_one

from .conftest import PASSWORD


def _row(sql: str, **params) -> dict | None:
    with connect() as conn:
        return fetch_one(conn, sql, **params)


def test_create_user_and_log_in(client_for):
    admin = client_for("admin")
    response = admin.post("/admin/users", {"username": "Sales.Two", "full_name": "Sales Two", "role": "SALES",
                                           "password": PASSWORD})
    assert response.status_code == 303
    user = _row("SELECT role, password_hash FROM APP_USERS WHERE username = 'sales.two'")  # lower-cased
    assert user["role"] == "SALES" and user["password_hash"].startswith("$argon2id$")
    assert client_for().login("sales.two").status_code == 303

    duplicate = admin.post("/admin/users", {"username": "sales.two", "full_name": "Again", "role": "SALES",
                                            "password": PASSWORD})
    assert duplicate.status_code == 422 and "already exists" in duplicate.text


def test_create_user_validation(client_for):
    response = client_for("admin").post("/admin/users", {"username": "x", "full_name": "", "role": "OWNER",
                                                         "password": PASSWORD})
    assert response.status_code == 422
    for message in ("3-60 lower-case", "full name", "Choose a role"):
        assert message in response.text
    response = client_for("admin").post("/admin/users", {"username": "polly", "full_name": "Polly", "role": "POLISHER",
                                                         "password": PASSWORD})
    assert "linked to their employee record" in response.text


def test_password_reset_validates(client_for):
    admin = client_for("admin")
    assert "Password not changed" in admin.get(
        admin.post("/admin/users/1/password", {"password": "short"}).headers["location"]).text
    assert "does not exist" in admin.get(
        admin.post("/admin/users/999999/password", {"password": PASSWORD}).headers["location"]).text


def test_employees(client_for):
    admin = client_for("admin")
    response = admin.post("/admin/employees", {"full_name": "Ada Facet", "role": "Polisher", "hire_date": "2026-01-05"})
    assert response.status_code == 303
    employee = _row("SELECT employee_id, is_active FROM EMPLOYEES WHERE full_name = 'Ada Facet'")
    assert employee["is_active"]
    admin.post(f"/admin/employees/{employee['employee_id']}/active", {"active": "0"})
    assert not _row("SELECT is_active FROM EMPLOYEES WHERE employee_id = :id", id=employee["employee_id"])["is_active"]

    response = admin.post("/admin/employees", {"full_name": "", "role": "", "hire_date": "yesterday"})
    assert response.status_code == 422
    assert "hire date" in response.text and "job role" in response.text


def test_customers(client_for):
    admin = client_for("admin")
    assert admin.post("/admin/customers", {"full_name": "Grace Hopper", "email": "grace@example.com"}).status_code == 303
    duplicate = admin.post("/admin/customers", {"full_name": "Grace H", "email": "grace@example.com"})
    assert duplicate.status_code == 422 and "already exists" in duplicate.text
    bad = admin.post("/admin/customers", {"full_name": "", "email": "not-an-email"})
    assert bad.status_code == 422 and "name@example.com" in bad.text


def test_suppliers_and_rough_lots(client_for):
    admin = client_for("admin")
    assert admin.post("/admin/suppliers", {"name": "Facet Mines", "country": "Botswana"}).status_code == 303
    assert admin.post("/admin/suppliers", {"name": " "}).status_code == 422
    supplier = _row("SELECT supplier_id FROM SUPPLIERS WHERE name = 'Facet Mines'")["supplier_id"]

    response = admin.post("/admin/rough-lots", {"supplier_id": str(supplier), "received_date": "2026-02-01",
                                                "weight_carat": "12.345", "cost_usd": "50000"})
    assert response.status_code == 303
    lot = _row("SELECT weight_carat FROM ROUGH_STONES WHERE supplier_id = :s", s=supplier)
    assert str(lot["weight_carat"]) == "12.345"

    bad = admin.post("/admin/rough-lots", {"supplier_id": "999999", "received_date": "2026-02-01",
                                           "weight_carat": "1", "cost_usd": "1"})
    assert bad.status_code == 422 and "valid supplier" in bad.text
    bad = admin.post("/admin/rough-lots", {"supplier_id": "", "received_date": "", "weight_carat": "-1", "cost_usd": "x"})
    assert bad.status_code == 422 and "date the lot was received" in bad.text


def test_admin_page_lists_everything(client_for):
    page = client_for("admin").get("/admin")
    assert page.status_code == 200
    for heading in ("Users", "Employees", "Customers"):
        assert heading in page.text
