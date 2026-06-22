"""過磅配對 Action：辨識結果→查車籍→判斷一磅/二磅→配對算淨重→寫表→回列印 payload。"""
from datetime import datetime

WEIGHING_TABLE = "x_czone_weighing"
VEHICLE_TABLE = "x_czone_vehicle"
STATUS_OPEN = "open"
STATUS_DONE = "done"


def make_ticket_no(date_str, seq):
    """date_str='YYYYMMDD'，seq 從 1 起。回 'YYYYMMDD-001'。"""
    return f"{date_str}-{seq:03d}"


def compute_net_weight(gross, tare):
    """淨重 = 毛重 − 空重，單位公噸，取小數 3 位。"""
    return round(float(gross) - float(tare), 3)


def decide_event(open_record):
    """無 open 紀錄→'first'(一磅)；有→'second'(二磅)。"""
    return "second" if open_record else "first"


def build_first_record(ticket_no, plate, customer_id, weight, now_iso,
                       plate_source, plate_confidence, weight_source,
                       weigh_operator, image_ref, customer_name="", material_name=""):
    """一磅：建立新過磅紀錄的完整欄位 dict。"""
    return {
        "ticket_no": ticket_no,
        "plate": plate,
        "customer_id": customer_id,
        "customer_name": customer_name,
        "material_id": None,
        "material_name": material_name,
        "gross_weight": float(weight),
        "tare_weight": None,
        "net_weight": None,
        "unit_price": None,
        "amount": None,
        "first_weigh_at": now_iso,
        "second_weigh_at": None,
        "status": STATUS_OPEN,
        "has_manifest": False,
        "settle_status": "unsettled",
        "settled_at": None,
        "weigh_operator": weigh_operator,
        "plate_source": plate_source,
        "plate_confidence": plate_confidence,
        "weight_source": weight_source,
        "image_ref": image_ref,
        "note": "",
    }


def build_second_update(open_record, weight, now_iso):
    """二磅：回傳要 update 的欄位 dict（空重/淨重/出場時間/完成）。"""
    return {
        "tare_weight": float(weight),
        "net_weight": compute_net_weight(open_record["gross_weight"], weight),
        "second_weigh_at": now_iso,
        "status": STATUS_DONE,
    }


def build_print_payload(record, direction):
    """組三聯磅單列印 payload（對齊 Fast Report SR_ 欄位）。"""
    return {
        "company": "薪榮環保股份有限公司",
        "SR_Sn": record.get("ticket_no"),
        "SR_Tn": record.get("plate"),
        "SR_Date": record.get("second_weigh_at") or record.get("first_weigh_at"),
        "SR_User": record.get("weigh_operator"),
        "SR_Direction": direction,
        "SR_Customer": record.get("customer_name") or "",
        "SR_Material": record.get("material_name") or "",
        "SR_GwTon": record.get("gross_weight"),
        "SR_TwTon": record.get("tare_weight"),
        "SR_NwTon": record.get("net_weight"),
    }


def _today_seq(ctx, date_str):
    rows = ctx.db.query_object(WEIGHING_TABLE, limit=500)
    return sum(1 for r in rows if str(r.get("ticket_no", "")).startswith(date_str)) + 1


def _find_open(ctx, plate):
    rows = ctx.db.query_object(WEIGHING_TABLE, limit=500)
    opens = [r for r in rows if r.get("plate") == plate and r.get("status") == STATUS_OPEN]
    opens.sort(key=lambda r: r.get("first_weigh_at", ""))
    return opens[0] if opens else None


def _lookup_vehicle(ctx, plate):
    for r in ctx.db.query_object(VEHICLE_TABLE, limit=500):
        if r.get("plate") == plate:
            return r
    return None


def execute(ctx):
    p = ctx.params
    plate = p.get("plate")
    weight = p.get("weight")
    if not plate or weight is None:
        ctx.response.json({"error": "缺少 plate 或 weight"})
        return

    now = p.get("now") or datetime.utcnow().isoformat()
    open_rec = _find_open(ctx, plate)

    if decide_event(open_rec) == "first":
        veh = _lookup_vehicle(ctx, plate)
        customer_id = veh.get("default_customer_id") if veh else None
        date_str = now[:10].replace("-", "")
        ticket_no = make_ticket_no(date_str, _today_seq(ctx, date_str))
        rec = build_first_record(
            ticket_no, plate, customer_id, weight, now,
            p.get("plate_source", "manual"), p.get("plate_confidence"),
            p.get("weight_source", "manual"), p.get("weigh_operator", ""),
            p.get("image_ref"),
            p.get("customer", ""), p.get("material", ""),
        )
        ctx.db.insert_object(slug=WEIGHING_TABLE, data=rec)
        ctx.response.json({
            "ticket_no": ticket_no, "event": "first", "plate": plate,
            "customer_id": customer_id, "gross_weight": rec["gross_weight"],
            "tare_weight": None, "net_weight": None,
            "manual_only": bool(veh.get("manual_only")) if veh else False,
            "print_payload": build_print_payload(rec, "進"),
            "needs_manual": [] if customer_id else ["customer"],
        })
    else:
        upd = build_second_update(open_rec, weight, now)
        ctx.db.update_object(slug=WEIGHING_TABLE, record_id=open_rec["id"], data=upd)
        merged = {**open_rec, **upd}
        ctx.response.json({
            "ticket_no": open_rec.get("ticket_no"), "event": "second",
            "plate": plate, "customer_id": open_rec.get("customer_id"),
            "gross_weight": open_rec.get("gross_weight"),
            "tare_weight": upd["tare_weight"], "net_weight": upd["net_weight"],
            "print_payload": build_print_payload(merged, "出"),
            "needs_manual": ["material"],
        })
