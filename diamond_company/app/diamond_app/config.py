"""Settings, read from environment variables or app/.env (never committed)."""

from functools import lru_cache
from pathlib import Path
from urllib.parse import urlsplit

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

APP_DIR = Path(__file__).resolve().parent.parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=APP_DIR / ".env", env_prefix="DT_", extra="ignore")

    db_host: str = "127.0.0.1"
    db_port: int = 3306
    db_user: str
    db_password: str = ""
    db_name: str = "Diamond_company"
    # CA bundle for an encrypted connection to a MySQL server on another machine
    db_ssl_ca: Path | None = None

    # Signs the session cookie. Generate with:
    #   python3 -c "import secrets; print(secrets.token_urlsafe(48))"
    session_secret: str
    session_max_age_hours: int = 12  # absolute limit, however active the user is
    session_idle_minutes: int = 60  # logged out after this long without a request
    secure_cookies: bool = False  # set true when served over HTTPS (also enables HSTS)

    # Address printed inside QR codes; use the LAN address to scan with a phone
    base_url: str = "http://127.0.0.1:8000"
    # Extra host names the app answers to, comma-separated. The base_url host,
    # 127.0.0.1 and localhost are always allowed.
    allowed_hosts: str = ""

    storage_dir: Path = APP_DIR / "storage"
    max_upload_mb: int = 10

    @field_validator("session_secret")
    @classmethod
    def secret_is_strong(cls, value: str) -> str:
        if len(value) < 32:
            raise ValueError("DT_SESSION_SECRET must be at least 32 characters")
        if len(set(value)) < 10:
            raise ValueError("DT_SESSION_SECRET looks like a placeholder; generate a random one")
        return value

    @field_validator("session_max_age_hours", "session_idle_minutes", "max_upload_mb")
    @classmethod
    def positive(cls, value: int) -> int:
        if value < 1:
            raise ValueError("must be at least 1")
        return value

    @property
    def certificate_dir(self) -> Path:
        return self.storage_dir / "certificates"

    @property
    def trusted_hosts(self) -> list[str]:
        hosts = {"127.0.0.1", "localhost", urlsplit(self.base_url).hostname or "127.0.0.1"}
        hosts.update(h.strip().lower() for h in self.allowed_hosts.split(",") if h.strip())
        return sorted(hosts)

    @property
    def max_request_bytes(self) -> int:
        # Largest upload plus room for the other form fields
        return (self.max_upload_mb + 1) * 1024 * 1024


@lru_cache
def get_settings() -> Settings:
    return Settings()
