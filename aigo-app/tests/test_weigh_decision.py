from weigh import decide_event, build_first_record, build_second_update, STATUS_OPEN, STATUS_DONE

def test_no_open_record_means_first_weigh():
    assert decide_event(None) == "first"

def test_existing_open_record_means_second_weigh():
    assert decide_event({"id": "x", "status": STATUS_OPEN}) == "second"

def test_first_record_holds_gross_and_is_open():
    rec = build_first_record(
        ticket_no="20260602-001", plate="ABC-1234", customer_id="cust-1",
        weight=25.0, now_iso="2026-06-02T11:57:18", plate_source="alpr",
        plate_confidence=0.93, weight_source="manual",
        weigh_operator="王小明", image_ref=None,
    )
    assert rec["gross_weight"] == 25.0
    assert rec["tare_weight"] is None
    assert rec["net_weight"] is None
    assert rec["status"] == STATUS_OPEN
    assert rec["material_id"] is None

def test_second_update_fills_tare_net_and_marks_done():
    open_rec = {"gross_weight": 25.0}
    upd = build_second_update(open_rec, weight=10.0, now_iso="2026-06-02T12:05:54")
    assert upd["tare_weight"] == 10.0
    assert upd["net_weight"] == 15.0
    assert upd["second_weigh_at"] == "2026-06-02T12:05:54"
    assert upd["status"] == STATUS_DONE
