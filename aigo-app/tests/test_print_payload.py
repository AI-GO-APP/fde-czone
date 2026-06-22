from weigh import build_print_payload

def test_payload_maps_record_to_fast_report_fields():
    record = {
        "ticket_no": "20260602-001", "plate": "ABC-1234",
        "first_weigh_at": "2026-06-02T11:57:18", "second_weigh_at": None,
        "weigh_operator": "王小明", "material_name": "廢木料-棧板",
        "gross_weight": 25.0, "tare_weight": None, "net_weight": None,
    }
    payload = build_print_payload(record, "進")
    assert payload["company"] == "薪榮環保股份有限公司"
    assert payload["SR_Sn"] == "20260602-001"
    assert payload["SR_Tn"] == "ABC-1234"
    assert payload["SR_Date"] == "2026-06-02T11:57:18"
    assert payload["SR_User"] == "王小明"
    assert payload["SR_Direction"] == "進"
    assert payload["SR_Material"] == "廢木料-棧板"
    assert payload["SR_GwTon"] == 25.0

def test_payload_date_prefers_second_weigh_time():
    record = {"first_weigh_at": "A", "second_weigh_at": "B"}
    assert build_print_payload(record, "出")["SR_Date"] == "B"

def test_payload_material_defaults_to_empty():
    assert build_print_payload({}, "進")["SR_Material"] == ""

def test_payload_maps_customer_name():
    record = {"customer_name": "測試環保", "material_name": "廢木料-棧板"}
    payload = build_print_payload(record, "進")
    assert payload["SR_Customer"] == "測試環保"
    assert payload["SR_Material"] == "廢木料-棧板"

def test_payload_customer_defaults_to_empty():
    assert build_print_payload({}, "進")["SR_Customer"] == ""
