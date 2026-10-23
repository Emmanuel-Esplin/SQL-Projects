"""Admin: users and roles, employees, customers, suppliers and rough lots.

These are reference records, so they use plain parameterized INSERT/UPDATE
statements rather than procedures.
"""

import re
from datetime import date
from decimal import Decimal

from fastapi import APIRouter, Depends, Form, Request
from fastapi.responses import RedirectResponse
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError

from ..db import connect, fetch_all, fetch_one
from ..forms import clean, decimal_field, int_field
from ..security import POLISHER, ROLE_LABELS, ROLES, CurrentUser, hash_password, password_problem, require_roles
from ..templating import flash, render

router = APIRouter(prefix="/admin")
admin_only = require_roles()  # no extra roles: Admin only

_USERNAME = re.compile(r"^[a-z0-9._-]{3,60}$")


def _page(request: Request, user: CurrentUser, status_code: int = 200, **extra):
    with connect(user.username) as conn:
        context = dict(
            users=fetch_all(conn, "SELECT u.*, e.full_name AS employee_name FROM APP_USERS u "
                                  "LEFT JOIN EMPLOYEES e ON e.employee_id = u.employee_id ORDER BY u.is_active DESC, u.username"),
            employees=fetch_all(conn, "SELECT * FROM EMPLOYEES ORDER BY is_active DESC, full_name"),
            customers=fetch_all(conn, "SELECT * FROM CUSTOMERS ORDER BY full_name"),
            suppliers=fetch_all(conn, "SELECT * FROM SUPPLIERS ORDER BY name"),
            rough_lots=fetch_all(conn, "SELECT r.*, s.name AS supplier FROM ROUGH_STONES r "
                                       "JOIN SUPPLIERS s ON s.supplier_id = r.supplier_id ORDER BY r.rough_id DESC LIMIT 50"),
            role_labels=ROLE_LABELS,
        )
    context.update(extra)
    context.setdefault("form_errors", {})
    context.setdefault("form_values", {})
    return render(request, "admin.html", status_code=status_code, section="admin", title="Admin", **context)


def _failed(request, user, form: str, errors: dict, values: dict):
    """Re-render with one form's errors; field ids are prefixed per form."""
    return _page(request, user, status_code=422, form_errors={form: errors}, form_values={form: values})


@router.get("")
def admin(request: Request, user: CurrentUser = Depends(admin_only)):
    return _page(request, user)


# -------------------------------------------------------------------- users

@router.post("/users")
def create_user(request: Request, username: str = Form(""), full_name: str = Form(""), role: str = Form(""),
                employee_id: str = Form(""), password: str = Form(""), user: CurrentUser = Depends(admin_only)):
    errors: dict[str, str] = {}
    username = username.strip().lower()
    if not _USERNAME.match(username):
        errors["username"] = "Use 3-60 lower-case letters, digits, dots, dashes or underscores."
    if not clean(full_name):
        errors["full_name"] = "Enter the person's full name."
    if role not in ROLES:
        errors["role"] = "Choose a role."
    employee = int_field(errors, "employee_id", employee_id, "employee record")
    if role == POLISHER and employee is None and "employee_id" not in errors:
        errors["employee_id"] = "Polishers must be linked to their employee record."
    problem = password_problem(password)
    if problem:
        errors["password"] = problem
    if not errors:
        try:
            with connect(user.username) as conn:
                conn.execute(text(
                    "INSERT INTO APP_USERS (username, full_name, password_hash, role, employee_id) "
                    "VALUES (:u, :n, :h, :r, :e)"),
                    {"u": username, "n": full_name.strip(), "h": hash_password(password), "r": role, "e": employee})
        except IntegrityError:
            errors["username"] = "That username, or that employee's login, already exists."
    if errors:
        return _failed(request, user, "user", errors,
                       {"username": username, "full_name": full_name, "role": role, "employee_id": employee_id})
    flash(request, f"User {username} created. Share the password with them privately.")
    return RedirectResponse("/admin", status_code=303)


@router.post("/users/{user_id}/active")
def toggle_user(request: Request, user_id: int, active: str = Form(""), user: CurrentUser = Depends(admin_only)):
    if user_id == user.user_id:
        flash(request, "You cannot deactivate your own account.", "error")
        return RedirectResponse("/admin", status_code=303)
    with connect(user.username) as conn:
        conn.execute(text("UPDATE APP_USERS SET is_active = :a WHERE user_id = :id"),
                     {"a": active == "1", "id": user_id})
    flash(request, "User activated." if active == "1" else "User deactivated. They are logged out immediately.")
    return RedirectResponse("/admin", status_code=303)


@router.post("/users/{user_id}/password")
def reset_password(request: Request, user_id: int, password: str = Form(""), user: CurrentUser = Depends(admin_only)):
    problem = password_problem(password)
    if problem:
        flash(request, f"Password not changed: {problem}", "error")
    else:
        with connect(user.username) as conn:
            conn.execute(text("UPDATE APP_USERS SET password_hash = :h WHERE user_id = :id"),
                         {"h": hash_password(password), "id": user_id})
        flash(request, "Password changed.")
    return RedirectResponse("/admin", status_code=303)


# ---------------------------------------------------------------- employees

@router.post("/employees")
def create_employee(request: Request, full_name: str = Form(""), role: str = Form(""), hire_date: str = Form(""),
                    user: CurrentUser = Depends(admin_only)):
    errors: dict[str, str] = {}
    if not clean(full_name):
        errors["full_name"] = "Enter the employee's full name."
    if not clean(role):
        errors["role"] = "Enter the job role, e.g. Polisher."
    try:
        hired = date.fromisoformat(hire_date.strip())
    except ValueError:
        errors["hire_date"] = "Enter the hire date."
        hired = None
    if errors:
        return _failed(request, user, "employee", errors, {"full_name": full_name, "role": role, "hire_date": hire_date})
    with connect(user.username) as conn:
        conn.execute(text("INSERT INTO EMPLOYEES (full_name, role, hire_date) VALUES (:n, :r, :d)"),
                     {"n": full_name.strip(), "r": role.strip()[:60], "d": hired})
    flash(request, f"Employee {full_name.strip()} added.")
    return RedirectResponse("/admin#employees", status_code=303)


@router.post("/employees/{employee_id}/active")
def toggle_employee(request: Request, employee_id: int, active: str = Form(""), user: CurrentUser = Depends(admin_only)):
    with connect(user.username) as conn:
        conn.execute(text("UPDATE EMPLOYEES SET is_active = :a WHERE employee_id = :id"),
                     {"a": active == "1", "id": employee_id})
    flash(request, "Employee updated.")
    return RedirectResponse("/admin#employees", status_code=303)


# ---------------------------------------------------------------- customers

@router.post("/customers")
def create_customer(request: Request, full_name: str = Form(""), email: str = Form(""), phone: str = Form(""),
                    user: CurrentUser = Depends(admin_only)):
    errors: dict[str, str] = {}
    if not clean(full_name):
        errors["full_name"] = "Enter the customer's name."
    email_value = clean(email)
    if email_value and not re.match(r"^[^@\s]+@[^@\s]+\.[^@\s]+$", email_value):
        errors["email"] = "Enter an email address like name@example.com."
    if not errors:
        try:
            with connect(user.username) as conn:
                conn.execute(text("INSERT INTO CUSTOMERS (full_name, email, phone) VALUES (:n, :e, :p)"),
                             {"n": full_name.strip()[:120], "e": email_value, "p": clean(phone)})
        except IntegrityError:
            errors["email"] = "A customer with that email already exists."
    if errors:
        return _failed(request, user, "customer", errors, {"full_name": full_name, "email": email, "phone": phone})
    flash(request, f"Customer {full_name.strip()} added.")
    return RedirectResponse("/admin#customers", status_code=303)


# ------------------------------------------------------- suppliers / rough

@router.post("/suppliers")
def create_supplier(request: Request, name: str = Form(""), country: str = Form(""), contact_email: str = Form(""),
                    user: CurrentUser = Depends(admin_only)):
    if not clean(name):
        return _failed(request, user, "supplier", {"name": "Enter the supplier's name."},
                       {"name": name, "country": country, "contact_email": contact_email})
    try:
        with connect(user.username) as conn:
            conn.execute(text("INSERT INTO SUPPLIERS (name, country, contact_email) VALUES (:n, :c, :e)"),
                         {"n": name.strip()[:120], "c": clean(country), "e": clean(contact_email)})
    except IntegrityError:
        return _failed(request, user, "supplier", {"name": "That supplier already exists."},
                       {"name": name, "country": country, "contact_email": contact_email})
    flash(request, f"Supplier {name.strip()} added.")
    return RedirectResponse("/admin#rough", status_code=303)


@router.post("/rough-lots")
def create_rough_lot(request: Request, supplier_id: str = Form(""), received_date: str = Form(""),
                     weight_carat: str = Form(""), cost_usd: str = Form(""), user: CurrentUser = Depends(admin_only)):
    errors: dict[str, str] = {}
    supplier = int_field(errors, "supplier_id", supplier_id, "supplier", required=True)
    weight = decimal_field(errors, "weight_carat", weight_carat, "lot weight", required=True, places=3,
                           maximum=Decimal("99999.999"))
    cost = decimal_field(errors, "cost_usd", cost_usd, "cost", required=True, positive=False,
                         maximum=Decimal("9999999999.99"))
    try:
        received = date.fromisoformat(received_date.strip())
    except ValueError:
        errors["received_date"] = "Enter the date the lot was received."
        received = None
    values = {"supplier_id": supplier_id, "received_date": received_date, "weight_carat": weight_carat, "cost_usd": cost_usd}
    if errors:
        return _failed(request, user, "rough", errors, values)
    with connect(user.username) as conn:
        if not fetch_one(conn, "SELECT 1 AS x FROM SUPPLIERS WHERE supplier_id = :s", s=supplier):
            return _failed(request, user, "rough", {"supplier_id": "Choose a valid supplier."}, values)
        conn.execute(text("INSERT INTO ROUGH_STONES (supplier_id, received_date, weight_carat, cost_usd) "
                          "VALUES (:s, :d, :w, :c)"), {"s": supplier, "d": received, "w": weight, "c": cost})
    flash(request, "Rough lot recorded. Register each stone from it on the Diamonds page.")
    return RedirectResponse("/admin#rough", status_code=303)
