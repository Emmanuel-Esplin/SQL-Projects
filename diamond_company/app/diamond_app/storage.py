"""Certificate files on local disk.

Files are identified by their content (magic bytes), never by the name or
type the browser sends, and stored under a random name with a sha256 hash.
Images must decode cleanly, and PDFs that carry scripts or launch actions
are refused, because certificates are previewed inline in the browser.
"""

import hashlib
import io
import re
import secrets
import warnings
from dataclasses import dataclass
from pathlib import Path

from fastapi import UploadFile
from PIL import Image

from .config import get_settings

_SIGNATURES = (
    (b"%PDF-", "application/pdf", ".pdf"),
    (b"\x89PNG\r\n\x1a\n", "image/png", ".png"),
    (b"\xff\xd8\xff", "image/jpeg", ".jpg"),
)
_SAFE_STORED_NAME = re.compile(r"^[0-9a-f]{32}\.(pdf|png|jpg)$")
# PDF name objects that run code or open other programs. Names may be
# written with #xx escapes, so those are decoded before matching.
_PDF_ACTIVE = re.compile(rb"/(JavaScript|JS|Launch|EmbeddedFile|RichMedia|XFA)\b")
_PDF_NAME_ESCAPE = re.compile(rb"#([0-9A-Fa-f]{2})")
MAX_IMAGE_PIXELS = 50_000_000  # a certificate scan at 600 dpi is well under this


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

    match = next((sig for sig in _SIGNATURES if data.startswith(sig[0])), None)
    if match is None:
        raise UploadRejected("Upload a PDF, JPEG or PNG file.")
    _, mime_type, extension = match
    if mime_type == "application/pdf":
        _check_pdf(data)
    else:
        _check_image(data)

    stored_filename = secrets.token_hex(16) + extension
    folder = settings.certificate_dir
    folder.mkdir(parents=True, exist_ok=True)
    (folder / stored_filename).write_bytes(data)

    original = Path(upload.filename or "certificate").name[:255]
    return StoredFile(stored_filename, original, mime_type, hashlib.sha256(data).hexdigest())


def _check_pdf(data: bytes) -> None:
    names = _PDF_NAME_ESCAPE.sub(lambda m: bytes([int(m.group(1), 16)]), data)
    if _PDF_ACTIVE.search(names):
        raise UploadRejected("This PDF contains scripts, attachments or forms. Upload the plain report "
                             "from the laboratory, or a scan of it.")


def _check_image(data: bytes) -> None:
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(data)) as image:
                if image.width * image.height > MAX_IMAGE_PIXELS:
                    raise UploadRejected("The image is too large. Scan it at a lower resolution.")
                image.verify()
            with Image.open(io.BytesIO(data)) as image:
                image.load()  # verify() skips pixel data; a truncated file fails here
    except UploadRejected:
        raise
    except (OSError, ValueError, SyntaxError, Image.DecompressionBombError, Image.DecompressionBombWarning):
        raise UploadRejected("The image file is damaged or not a real JPEG or PNG.") from None


def delete_stored(stored_filename: str) -> None:
    """Remove a file whose database insert failed."""
    path = certificate_path(stored_filename)
    if path:
        path.unlink(missing_ok=True)


def certificate_path(stored_filename: str) -> Path | None:
    # Names come from the database, but never let one escape the folder
    if not stored_filename or not _SAFE_STORED_NAME.match(stored_filename):
        return None
    return get_settings().certificate_dir / stored_filename
