"""Certificate files on local disk.

Files are identified by their content (magic bytes), never by the name or
type the browser sends, and stored under a random name with a sha256 hash.
"""

import hashlib
import secrets
from dataclasses import dataclass
from pathlib import Path

from fastapi import UploadFile

from .config import get_settings

_SIGNATURES = (
    (b"%PDF-", "application/pdf", ".pdf"),
    (b"\x89PNG\r\n\x1a\n", "image/png", ".png"),
    (b"\xff\xd8\xff", "image/jpeg", ".jpg"),
)
_SAFE_STORED_NAME = set("0123456789abcdef.pdfjngp")


class UploadRejected(ValueError):
    pass


@dataclass(frozen=True)
class StoredFile:
    stored_filename: str
    original_filename: str
    mime_type: str
    sha256: str


async def save_certificate(upload: UploadFile) -> StoredFile:
    settings = get_settings()
    limit = settings.max_upload_mb * 1024 * 1024
    data = await upload.read(limit + 1)
    if not data:
        raise UploadRejected("Choose a certificate file to upload.")
    if len(data) > limit:
        raise UploadRejected(f"The file is larger than {settings.max_upload_mb} MB.")

    for signature, mime_type, extension in _SIGNATURES:
        if data.startswith(signature):
            break
    else:
        raise UploadRejected("Upload a PDF, JPEG or PNG file.")

    stored_filename = secrets.token_hex(16) + extension
    folder = settings.certificate_dir
    folder.mkdir(parents=True, exist_ok=True)
    (folder / stored_filename).write_bytes(data)

    original = Path(upload.filename or "certificate").name[:255]
    return StoredFile(stored_filename, original, mime_type, hashlib.sha256(data).hexdigest())


def delete_stored(stored_filename: str) -> None:
    """Remove a file whose database insert failed."""
    path = certificate_path(stored_filename)
    if path:
        path.unlink(missing_ok=True)


def certificate_path(stored_filename: str) -> Path | None:
    # Names come from the database, but never let one escape the folder
    if not stored_filename or not set(stored_filename) <= _SAFE_STORED_NAME:
        return None
    return get_settings().certificate_dir / stored_filename
