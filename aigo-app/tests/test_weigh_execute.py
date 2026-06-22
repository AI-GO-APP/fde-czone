import weigh
from conftest import FakeCtx, FakeDB

def test_first_weigh_inserts_open_record_with_default_customer():
    db = FakeDB(weighing=[], vehicle=[{"plate": "ABC-1234", "default_customer_id": "cust-1"}])
    ctx = FakeCtx({"plate": "ABC-1234", "weight": 25.0, "weigh_operator": "王小明",
                   "now": "2026-06-02T11:57:18"}, db=db)
    weigh.execute(ctx)
    assert ctx.response.body["event"] == "first"
    assert ctx.response.body["ticket_no"] == "20260602-001"
    assert ctx.response.body["customer_id"] == "cust-1"
    assert len(db.inserted) == 1
    assert db.inserted[0][1]["status"] == "open"

def test_second_weigh_updates_matching_open_record():
    open_rec = {"id": "rec-1", "plate": "ABC-1234", "status": "open",
                "gross_weight": 25.0, "ticket_no": "20260602-001",
                "first_weigh_at": "2026-06-02T11:57:18"}
    db = FakeDB(weighing=[open_rec], vehicle=[])
    ctx = FakeCtx({"plate": "ABC-1234", "weight": 10.0, "weigh_operator": "王小明",
                   "now": "2026-06-02T12:05:54"}, db=db)
    weigh.execute(ctx)
    assert ctx.response.body["event"] == "second"
    assert ctx.response.body["net_weight"] == 15.0
    assert db.updated[0][1] == "rec-1"
    assert db.updated[0][2]["status"] == "done"
    assert ctx.response.body["needs_manual"] == ["material"]

def test_missing_weight_returns_error():
    ctx = FakeCtx({"plate": "ABC-1234", "weigh_operator": "王小明"})
    weigh.execute(ctx)
    assert ctx.response.body["error"]

def test_first_weigh_without_known_vehicle_flags_manual_customer():
    db = FakeDB(weighing=[], vehicle=[])
    ctx = FakeCtx({"plate": "NEW-9999", "weight": 20.0, "weigh_operator": "王",
                   "now": "2026-06-02T09:00:00"}, db=db)
    weigh.execute(ctx)
    assert ctx.response.body["customer_id"] is None
    assert ctx.response.body["needs_manual"] == ["customer"]

def test_first_weigh_stores_customer_and_material():
    db = FakeDB(weighing=[], vehicle=[])
    ctx = FakeCtx({"plate": "ABC-1234", "weight": 25.0, "weigh_operator": "王小明",
                   "customer": "測試環保", "material": "廢木料-棧板",
                   "now": "2026-06-02T11:57:18"}, db=db)
    weigh.execute(ctx)
    rec = db.inserted[0][1]
    assert rec["customer_name"] == "測試環保"
    assert rec["material_name"] == "廢木料-棧板"
    pp = ctx.response.body["print_payload"]
    assert pp["SR_Customer"] == "測試環保"
    assert pp["SR_Material"] == "廢木料-棧板"

def test_second_weigh_keeps_first_customer_material():
    open_rec = {"id": "rec-1", "plate": "ABC-1234", "status": "open",
                "gross_weight": 25.0, "ticket_no": "20260602-001",
                "customer_name": "測試環保", "material_name": "廢木料-棧板",
                "first_weigh_at": "2026-06-02T11:57:18"}
    db = FakeDB(weighing=[open_rec], vehicle=[])
    ctx = FakeCtx({"plate": "ABC-1234", "weight": 10.0, "weigh_operator": "王小明",
                   "now": "2026-06-02T12:05:54"}, db=db)
    weigh.execute(ctx)
    pp = ctx.response.body["print_payload"]
    assert pp["SR_Customer"] == "測試環保"
    assert pp["SR_Material"] == "廢木料-棧板"
