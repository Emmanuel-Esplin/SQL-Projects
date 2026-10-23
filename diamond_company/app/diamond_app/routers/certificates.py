from datetime import date

from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, RedirectResponse

from .. import catalog
from ..db import call_procedure, connect, fetch_all, fetch_one
from ..forms import clean
from ..security import SAFE_KEEPER, CurrentUser, get_current_user, require_roles
from ..storage import UploadRejected, certificate_path, delete_stored, save_certificate
from ..templating import flash, render

router = APIRouter()


@router.get("/certificates")
def list_certificates(request: Request, q: str = "", user: CurrentUser = Depends(get_current_user)):
    with connect(user.username) as conn:
        rows = fetch_all(
            conn,
            "SELECT c.certificate_id, c.lab, c.report_number, c.issue_date, c.uploaded_at, "
            "d.diamond_id, d.sku, d.shape, d.carat, u.full_name AS uploaded_by_name "
            "FROM CERTIFICATES c JOIN DIAMONDS d ON d.diamond_id = c.diamond_id "
            "JOIN APP_USERS u ON u.user_id = c.uploaded_by "
            "WHERE (:q = '' OR c.report_number LIKE :like OR d.sku LIKE :like) "
            "ORDER BY c.certificate_id DESC LIMIT 200",
            q=q.strip(), like=f"%{q.strip()}%",
        )
    return render(request, "certificates/list.html", section="certificates", title="Certificates", rows=rows, q=q)


@router.post("/diamonds/{diamond_id}/certificates")
async def upload_certificate(
    request: Request,
    diamond_id: int,
    lab: str = Form("GIA"),
    report_number: str = Form(""),
    issue_date: str = Form(""),
    file: UploadFile = File(None),
    user: CurrentUser = Depends(require_roles(SAFE_KEEPER)),
):
    back = RedirectResponse(f"/diamonds/{diamond_id}", status_code=303)
    lab = lab if lab in catalog.CERT_LABS else "Other"
    report = clean(report_number)
    if not report or len(report) > 64:
        flash(request, "Enter the report number printed on the certificate (up to 64 characters).", "error")
        return back
    issued = None
    if clean(issue_date):
        try:
            issued = date.fromisoformat(issue_date.strip())
        except ValueError:
            flash(request, "Enter the issue date as a valid date.", "error")
            return back
    if file is None:
        flash(request, "Choose a certificate file to upload.", "error")
        return back
    try:
        stored = await save_certificate(file)
    except UploadRejected as exc:
        flash(request, str(exc), "error")
        return back

    with connect(user.username) as conn:
        result = call_procedure(
            conn, "sp_add_certificate",
            [diamond_id, lab, report, issued, stored.stored_filename, stored.original_filename,
             stored.mime_type, stored.sha256, user.user_id],
            ["p_certificate_id", "p_success", "p_error_message"],
        )
    if result.ok:
        flash(request, f"{lab} report {report} saved.")
    else:
        delete_stored(stored.stored_filename)
        flash(request, result.error, "error")
    return back


def _certificate(conn, certificate_id: int) -> dict:
    row = fetch_one(
        conn,
        "SELECT c.*, d.sku, d.diamond_id, u.full_name AS uploaded_by_name FROM CERTIFICATES c "
        "JOIN DIAMONDS d ON d.diamond_id = c.diamond_id JOIN APP_USERS u ON u.user_id = c.uploaded_by "
        "WHERE c.certificate_id = :id",
        id=certificate_id,
    )
    if not row:
        raise HTTPException(404, "That certificate does not exist.")
    return row


@router.get("/certificates/{certificate_id}")
def certificate_detail(request: Request, certificate_id: int, user: CurrentUser = Depends(get_current_user)):
    with connect(user.username) as conn:
        cert = _certificate(conn, certificate_id)
    return render(request, "certificates/detail.html", section="certificates",
                  title=f"{cert['lab']} {cert['report_number']}", cert=cert)


@router.get("/certificates/{certificate_id}/file")
def certificate_file(certificate_id: int, download: bool = False, user: CurrentUser = Depends(get_current_user)):
    with connect(user.username) as conn:
        cert = _certificate(conn, certificate_id)
    path = certificate_path(cert["stored_filename"])
    if not path or not path.is_file():
        raise HTTPException(404, "The certificate file is missing from storage.")
    return FileResponse(
        path,
        media_type=cert["mime_type"],
        filename=cert["original_filename"],
        content_disposition_type="attachment" if download else "inline",
        # Content is verified PDF/JPEG/PNG; a minimal policy keeps built-in PDF viewers working
        headers={"Cache-Control": "private, no-store",
                 "Content-Security-Policy": "frame-ancestors 'self'; script-src 'none'"},
    )
