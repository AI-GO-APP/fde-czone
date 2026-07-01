"""寫入/更新目前即時磅重(單筆 x_czone_live_weight，key='current')。
server_at 由本 action 以伺服器台灣時間蓋章，供前端判斷新鮮度(不信任現場時鐘)。"""
from datetime import datetime, timedelta

TABLE = "x_czone_live_weight"
KEY = "current"
TW_OFFSET = timedelta(hours=8)


def _server_now(ctx):
    return ctx.params.get("now") or (datetime.utcnow() + TW_OFFSET).isoformat()


def _find_current(ctx):
    for r in ctx.db.query_object(TABLE, limit=10):
        if r.get("key") == KEY:
            return r
    return None


def execute(ctx):
    p = ctx.params
    weight = p.get("weight")
    state = p.get("state")
    if weight is None or not state:
        ctx.response.json({"error": "缺少 weight 或 state"})
        return
    server_at = _server_now(ctx)
    data = {
        "key": KEY,
        "weight": float(weight),
        "state": state,
        "at": p.get("at") or server_at,
        "server_at": server_at,
    }
    cur = _find_current(ctx)
    if cur:
        ctx.db.update_object(slug=TABLE, record_id=cur["id"], data=data)
    else:
        ctx.db.insert_object(slug=TABLE, data=data)
    ctx.response.json({"ok": True})
