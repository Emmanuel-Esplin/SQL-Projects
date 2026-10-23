"""End-to-end: rough stone -> polishing -> certificate -> sale -> delivery."""

import re

from diamond_app.db import connect, fetch_one

PDF = b"%PDF-1.4\n1 0 obj << /Type /Catalog >> endobj\ntrailer << /Root 1 0 R >>\n%%EOF\n"


def _stone(code: str) -> dict:
    with connect() as conn:
        return fetch_one(conn, "SELECT * FROM DIAMONDS WHERE sku = :c", c=code)


def _register(keeper, **fields) -> str:
    data = {"shape": "Other", "origin": "NATURAL", "color_type": "WHITE", "polish_state": "UNPOLISHED",
            "carat": "2.50", **fields}
    response = keeper.post("/diamonds", data)
    assert response.status_code == 303, response.text
    detail = keeper.get(response.headers["location"])
    return re.search(r"DC-\d{2}-[0-9A-HJKMNP-TV-Z]{6}", detail.text).group(0)


def test_register_validates_gia_rules(client_for):
    keeper = client_for("keeper")
    response = keeper.post("/diamonds", {"shape": "Round", "origin": "NATURAL", "color_type": "WHITE",
                                         "polish_state": "POLISHED", "carat": "abc"})
    assert response.status_code == 422
    assert "There is a problem" in response.text
    assert "weight in carats as a number" in response.text
    assert "color grade of the polished stone" in response.text
    assert "clarity grade of the polished stone" in response.text

    response = keeper.post("/diamonds", {"shape": "Cushion", "origin": "NATURAL", "color_type": "FANCY",
                                         "polish_state": "UNPOLISHED", "carat": "1.00"})
    assert response.status_code == 422
    assert "fancy color hue" in response.text


def test_register_fancy_and_lab_grown(client_for):
    keeper = client_for("keeper")
    code = _register(keeper, shape="Pear", origin="LAB_GROWN", color_type="FANCY", fancy_hue="Blue",
                     fancy_intensity="Fancy Vivid", polish_state="POLISHED", carat="0.80",
                     clarity_grade="VS1", price_usd="12500")
    stone = _stone(code)
    assert (stone["origin"], stone["fancy_hue"], stone["color_grade"], float(stone["price_usd"])) == \
           ("LAB_GROWN", "Blue", None, 12500.0)


def test_full_lifecycle(client_for):
    keeper, polisher, seller = client_for("keeper"), client_for("polisher"), client_for("seller")

    code = _register(keeper, rough_id="1")
    stone = _stone(code)
    sid = stone["diamond_id"]

    # Unique code + QR label
    qr = keeper.get(f"/diamonds/{sid}/qr.svg")
    assert qr.status_code == 200 and qr.headers["content-type"].startswith("image/svg+xml") and b"<svg" in qr.content
    assert code in keeper.get(f"/diamonds/{sid}/label").text
    assert keeper.get(f"/d/{code.lower()}").headers["location"] == f"/diamonds/{sid}"
    assert keeper.get(f"/search?code=http://x/d/{code}").headers["location"] == f"/diamonds/{sid}"

    # Wrong weight is refused at the safe
    response = keeper.post("/safe/check-out", {"code": code, "purpose": "POLISHING", "holder_employee_id": "1",
                                               "weight_carat": "2.70"})
    assert response.status_code == 422 and "Weight mismatch" in response.text

    # Out to the polisher
    response = keeper.post("/safe/check-out", {"code": code, "purpose": "POLISHING", "holder_employee_id": "1",
                                               "weight_carat": "2.50", "notes": "Round brilliant"})
    assert response.status_code == 303
    assert _stone(code)["status"] == "IN_POLISHING"
    assert code in polisher.get("/polishers/1").text
    assert code in keeper.get("/").text  # dashboard "out of the safe"

    # Certificates need a polished stone
    response = keeper.post(f"/diamonds/{sid}/certificates", {"lab": "GIA", "report_number": "111"},
                           files={"file": ("c.pdf", PDF, "application/pdf")})
    assert "polished" in keeper.get(response.headers["location"]).text

    # Back heavier: refused as a possible swap
    response = keeper.post("/safe/check-in", {"code": code, "weight_carat": "2.80"})
    assert response.status_code == 422 and "Possible swap" in response.text

    # Polished without clarity: refused
    response = keeper.post("/safe/check-in", {"code": code, "weight_carat": "1.10", "mark_polished": "on",
                                              "color_grade": "F"})
    assert response.status_code == 422 and "clarity grade" in response.text

    # Back polished and graded
    response = keeper.post("/safe/check-in", {"code": code, "weight_carat": "1.10", "mark_polished": "on",
                                              "color_grade": "F", "clarity_grade": "VVS2", "cut_grade": "Excellent"})
    assert response.status_code == 303
    stone = _stone(code)
    assert (stone["status"], stone["polish_state"], float(stone["carat"]), stone["clarity_grade"]) == \
           ("AVAILABLE", "POLISHED", 1.10, "VVS2")
    detail = keeper.get(f"/diamonds/{sid}").text
    assert "1.40 ct" in detail  # weight removed by polishing (2.50 -> 1.10)
    assert "Master Polisher A" in detail

    # Price it from the 4Cs
    keeper_page = client_for("admin")
    keeper_page.post(f"/diamonds/{sid}/price", {"price_usd": "9800"})
    assert float(_stone(code)["price_usd"]) == 9800.0

    # Certificate upload: wrong type refused, PDF accepted, duplicate refused
    response = keeper.post(f"/diamonds/{sid}/certificates", {"lab": "GIA", "report_number": "2141438167"},
                           files={"file": ("c.pdf", b"<html>not a pdf</html>", "application/pdf")})
    assert "PDF, JPEG or PNG" in keeper.get(response.headers["location"]).text
    response = keeper.post(f"/diamonds/{sid}/certificates", {"lab": "GIA", "report_number": "2141438167",
                                                             "issue_date": "2026-10-01"},
                           files={"file": ("report.pdf", PDF, "application/pdf")})
    assert "saved" in keeper.get(response.headers["location"]).text
    cert_id = fetch_one_cert(sid)
    file_response = polisher.get(f"/certificates/{cert_id}/file")
    assert file_response.status_code == 200 and file_response.content == PDF
    assert _stone(code)["certified"] == 1
    response = keeper.post(f"/diamonds/{sid}/certificates", {"lab": "GIA", "report_number": "2141438167"},
                           files={"file": ("again.pdf", PDF, "application/pdf")})
    assert "already on file" in keeper.get(response.headers["location"]).text

    # Sell: reserve -> being sold -> paid
    with connect() as conn:
        customer = fetch_one(conn, "SELECT customer_id FROM CUSTOMERS LIMIT 1")["customer_id"]
    assert seller.post("/sales/reserve", {"code": code, "customer_id": str(customer)}).status_code == 303
    assert _stone(code)["status"] == "RESERVED"
    order = re.search(r"/sales/orders/(\d+)/status", seller.get("/sales").text).group(1)
    assert seller.post(f"/sales/orders/{order}/status", {"status": "PAID"}).status_code == 303
    assert _stone(code)["status"] == "SOLD"

    # Hand over to the buyer: it leaves the safe and is not "out" afterwards
    assert keeper.post("/safe/check-out", {"code": code, "purpose": "SALE", "weight_carat": "1.10"}).status_code == 303
    assert code not in keeper.get("/safe").text.split("Out of the safe now")[1]
    assert "handed over to the buyer" in keeper.get(f"/safe?code={code}").text


def fetch_one_cert(diamond_id: int) -> int:
    with connect() as conn:
        return fetch_one(conn, "SELECT certificate_id FROM CERTIFICATES WHERE diamond_id = :d", d=diamond_id)["certificate_id"]


def test_split_creates_lineage(client_for):
    keeper = client_for("keeper")
    code = _register(keeper, carat="3.00")
    sid = _stone(code)["diamond_id"]
    response = keeper.post(f"/diamonds/{sid}/split", {"child_weights": "1.60, 1.10"})
    assert response.status_code == 303
    page = keeper.get(f"/diamonds/{sid}").text
    children = re.findall(r'href="/diamonds/(\d+)">(DC-[^<]+)</a>', page)
    assert len({c for c in children if c[1] != code}) >= 2
    assert _stone(code)["status"] == "SPLIT"
    child_id = int(children[0][0])
    child_page = keeper.get(f"/diamonds/{child_id}").text
    assert code in child_page  # child shows its parent in the lineage tree


def test_repair_round_trip(client_for):
    keeper = client_for("keeper")
    code = _register(keeper, shape="Oval", polish_state="POLISHED", color_grade="G", clarity_grade="SI1",
                     carat="1.00", base_price_per_carat="5000")
    response = keeper.post("/safe/check-out", {"code": code, "purpose": "REPAIR", "holder_employee_id": "2",
                                               "weight_carat": "1.00", "notes": "chipped girdle", "return_to": "/repairs"})
    assert response.headers["location"] == "/repairs"
    assert code in keeper.get("/repairs").text
    assert _stone(code)["status"] == "IN_REPAIR"
    assert keeper.post("/safe/check-in", {"code": code, "weight_carat": "0.98"}).status_code == 303
    assert _stone(code)["status"] == "AVAILABLE"
    page = keeper.get("/repairs").text
    in_repair, completed = page.split("In repair now")[1].split("Completed repairs")
    assert code not in in_repair and code in completed
    with connect() as conn:
        audit = fetch_one(conn, "SELECT changed_by FROM AUDIT_LOG WHERE table_name = 'DIAMONDS' "
                                "AND row_id = :id ORDER BY audit_id DESC LIMIT 1", id=_stone(code)["diamond_id"])
    assert audit["changed_by"] == "keeper"  # audit names the logged-in user
