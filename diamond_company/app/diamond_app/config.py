"""Settings, read from environment variables or app/.env (never committed)."""

from functools import lru_cache
from pathlib import Path

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

    # Signs the session cookie. Generate with:
    #   python3 -c "import secrets; print(secrets.token_urlsafe(48))"
    session_secret: str
    session_max_age_hours: int = 12
    secure_cookies: bool = False  # set true when served over HTTPS

    # Address printed inside QR codes; use the LAN address to scan with a phone
    base_url: str = "http://127.0.0.1:8000"

    storage_dir: Path = APP_DIR / "storage"
    max_upload_mb: int = 10

    @field_validator("session_secret")
    @classmethod
    def secret_is_strong(cls, value: str) -> str:
        if len(value) < 32:
            raise ValueError("DT_SESSION_SECRET must be at least 32 characters")
        return value

    @property
    def certificate_dir(self) -> Path:
        return self.storage_dir / "certificates"


@lru_cache
def get_settings() -> Settings:
    return Settings()
