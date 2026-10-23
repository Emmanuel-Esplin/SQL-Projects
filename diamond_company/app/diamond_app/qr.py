"""QR codes for diamond labels (SVG, so labels print sharply at any size)."""

import io

import qrcode
from qrcode.image.svg import SvgPathImage

from .config import get_settings


def lookup_url(code: str) -> str:
    return f"{get_settings().base_url.rstrip('/')}/d/{code}"


def qr_svg(code: str) -> bytes:
    # Error correction M survives a scratched or partly covered label
    qr = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M, border=2, image_factory=SvgPathImage)
    qr.add_data(lookup_url(code))
    qr.make(fit=True)
    buffer = io.BytesIO()
    qr.make_image().save(buffer)
    return buffer.getvalue()
