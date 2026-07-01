import update_live_weight
import get_live_weight
from conftest import FakeCtx, FakeDB


def test_update_inserts_when_empty():
    db = FakeDB(live=[])
    ctx = FakeCtx({"weight": 4830, "state": "weighing", "at": "2026-07-01T14:03:13",
                   "now": "2026-07-01T14:03:14"}, db=db)
    update_live_weight.execute(ctx)
    assert ctx.response.body == {"ok": True}
    assert len(db.inserted) == 1
    slug, row = db.inserted[0]
    assert slug == "x_czone_live_weight"
    assert row["key"] == "current"
    assert row["weight"] == 4830
    assert row["state"] == "weighing"
    assert row["server_at"] == "2026-07-01T14:03:14"


def test_update_updates_existing_current():
    cur = {"id": "rec-1", "key": "current", "weight": 0, "state": "idle",
           "at": "old", "server_at": "old"}
    db = FakeDB(live=[cur])
    ctx = FakeCtx({"weight": 12000, "state": "weighing",
                   "now": "2026-07-01T14:05:00"}, db=db)
    update_live_weight.execute(ctx)
    assert db.updated[0][0] == "x_czone_live_weight"
    assert db.updated[0][1] == "rec-1"
    assert db.updated[0][2]["weight"] == 12000
    assert db.updated[0][2]["server_at"] == "2026-07-01T14:05:00"
    assert len(db.inserted) == 0


def test_update_missing_fields_returns_error():
    ctx = FakeCtx({"state": "weighing"})  # 缺 weight
    update_live_weight.execute(ctx)
    assert ctx.response.body["error"]
