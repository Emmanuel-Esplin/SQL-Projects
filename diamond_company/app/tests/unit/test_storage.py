"""Certificate upload checks."""

import asyncio
import io
import zlib

import pytest
from PIL import Image
from starlette.datastructures import UploadFile

from diamond_app import storage

PDF = b"%PDF-1.4\n1 0 obj << /Type /Catalog >> endobj\ntrailer << /Root 1 0 R >>\n%%EOF\n"


def _upload(data: bytes, name: str = "report.pdf") -> UploadFile:
    return UploadFile(io.BytesIO(data), filename=name)


def _save(data: bytes, name: str = "report.pdf") -> storage.StoredFile:
    return asyncio.run(storage.save_certificate(_upload(data, name)))


def _image(fmt: str, size=(40, 30)) -> bytes:
    buffer = io.BytesIO()
    Image.new("RGB", size, "white").save(buffer, fmt)
    return buffer.getvalue()


def test_pdf_is_stored_under_a_random_name():
    stored = _save(PDF, "../../etc/GIA report.pdf")
    assert stored.mime_type == "application/pdf"
    assert stored.original_filename == "GIA report.pdf"  # directory parts dropped
    assert storage.certificate_path(stored.stored_filename).read_bytes() == PDF
    assert len(stored.sha256) == 64
    storage.delete_stored(stored.stored_filename)
    assert not storage.certificate_path(stored.stored_filename).exists()


@pytest.mark.parametrize(("fmt", "mime"), [("PNG", "image/png"), ("JPEG", "image/jpeg")])
def test_real_images_are_accepted(fmt, mime):
    stored = _save(_image(fmt), "scan")
    assert stored.mime_type == mime
    storage.delete_stored(stored.stored_filename)


def test_type_comes_from_content_not_name():
    with pytest.raises(storage.UploadRejected, match="PDF, JPEG or PNG"):
        _save(b"<html><script>alert(1)</script></html>", "report.pdf")


def test_empty_and_oversized_files_are_refused(monkeypatch):
    with pytest.raises(storage.UploadRejected, match="Choose"):
        _save(b"")
    monkeypatch.setattr(storage.get_settings(), "max_upload_mb", 1)
    with pytest.raises(storage.UploadRejected, match="larger than 1 MB"):
        _save(PDF + b"0" * (1024 * 1024))


@pytest.mark.parametrize("payload", [
    b"/OpenAction << /S /JavaScript /JS (app.alert(1)) >>",
    b"/AA << /O << /S /Launch /F (cmd.exe) >> >>",
    b"/Names << /EmbeddedFiles << >> >> /EmbeddedFile",
    b"/S /J#61vaScript",  # hex-escaped name
])
def test_pdfs_with_active_content_are_refused(payload):
    with pytest.raises(storage.UploadRejected, match="scripts"):
        _save(PDF.replace(b"endobj", payload + b" endobj", 1))


def test_truncated_image_is_refused():
    with pytest.raises(storage.UploadRejected, match="damaged"):
        _save(_image("PNG")[:60], "scan.png")


def test_decompression_bomb_is_refused(monkeypatch):
    monkeypatch.setattr(storage, "MAX_IMAGE_PIXELS", 100)
    with pytest.raises(storage.UploadRejected, match="too large"):
        _save(_image("PNG", size=(50, 50)), "scan.png")


def test_png_with_corrupt_pixel_data_is_refused():
    png = bytearray(_image("PNG"))
    start = png.index(b"IDAT") + 4
    png[start:start + 8] = zlib.compress(b"junk")[:8]
    with pytest.raises(storage.UploadRejected, match="damaged"):
        _save(bytes(png), "scan.png")


@pytest.mark.parametrize("name", ["../secret.pdf", "abc.pdf", "0" * 32 + ".exe", "0" * 32 + ".pdf/../x", ""])
def test_certificate_path_rejects_unexpected_names(name):
    assert storage.certificate_path(name) is None


def test_certificate_path_accepts_generated_names():
    assert storage.certificate_path("0123456789abcdef" * 2 + ".pdf") is not None
