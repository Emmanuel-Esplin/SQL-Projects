"""Shared test setup: configure the app before any of it is imported.

tests/unit/         no database needed; runs anywhere
tests/integration/  rebuilds Diamond_company on a throwaway MySQL server
                    (opt in with DT_TEST_ALLOW_RESET=1, see its conftest.py)
"""

import os
import secrets
import tempfile

DB = {
    "host": os.environ.get("DT_TEST_DB_HOST", "127.0.0.1"),
    "port": os.environ.get("DT_TEST_DB_PORT", "3306"),
    "user": os.environ.get("DT_TEST_DB_USER", "root"),
    "password": os.environ.get("DT_TEST_DB_PASSWORD", ""),
}

os.environ.update(
    DT_DB_HOST=DB["host"], DT_DB_PORT=DB["port"], DT_DB_USER=DB["user"], DT_DB_PASSWORD=DB["password"],
    DT_DB_NAME="Diamond_company", DT_SESSION_SECRET=secrets.token_urlsafe(48),
    DT_STORAGE_DIR=tempfile.mkdtemp(prefix="dt-storage-"), DT_BASE_URL="http://testserver",
    DT_SECURE_COOKIES="false", DT_ALLOWED_HOSTS="",
)
