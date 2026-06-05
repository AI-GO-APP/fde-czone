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
                       weigh_operator, image_ref):
    """一磅：建立新過磅紀錄的完整欄位 dict。"""
    return {
        "ticket_no": ticket_no,
        "plate": plate,
        "customer_id": customer_id,
        "material_id": None,
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
        "SR_Material": record.get("material_name") or "",
        "SR_GwTon": record.get("gross_weight"),
        "SR_TwTon": record.get("tare_weight"),
        "SR_NwTon": record.get("net_weight"),
    }
