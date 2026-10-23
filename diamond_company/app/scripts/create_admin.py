"""Create the first Admin login (or another admin).

Run from diamond_company/app/ after configuring .env:
    .venv/bin/python scripts/create_admin.py

The password is typed at a hidden prompt; it is never stored or logged in
plain text - only its argon2 hash reaches the database.
"""

import getpass
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import text  # noqa: E402
from sqlalchemy.exc import IntegrityError  # noqa: E402

from diamond_app.db import connect  # noqa: E402
from diamond_app.security import hash_password, password_problem  # noqa: E402


def main() -> int:
    username = input("Admin username (e.g. admin): ").strip().lower()
    full_name = input("Full name: ").strip()
    if not username or not full_name:
        print("Username and full name are required.")
        return 1
    password = getpass.getpass("Password (at least 12 characters): ")
    problem = password_problem(password)
    if problem:
        print(problem)
        return 1
    if getpass.getpass("Repeat password: ") != password:
        print("The passwords do not match.")
        return 1
    try:
        with connect("create_admin.py") as conn:
            conn.execute(
                text("INSERT INTO APP_USERS (username, full_name, password_hash, role) VALUES (:u, :n, :h, 'ADMIN')"),
                {"u": username, "n": full_name, "h": hash_password(password)},
            )
    except IntegrityError:
        print(f"A user named {username} already exists.")
        return 1
    print(f"Admin {username} created. Start the app and log in.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
