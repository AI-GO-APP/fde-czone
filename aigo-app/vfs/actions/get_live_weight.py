"""讀目前即時磅重(單筆 x_czone_live_weight)，並附上伺服器時間 server_now，
讓前端以同一時間基準(server_now - server_at)判斷新鮮度。"""
from datetime import datetime, timedelta

TABLE = "x_czone_live_weight"
KEY = "current"
TW_OFFSET = timedelta(hours=8)


def _server_now(ctx):
    return ctx.params.get("now") or (datetime.utcnow() + TW_OFFSET).isoformat()


def execute(ctx):
    server_now = _server_now(ctx)
    cur = None
    for r in ctx.db.query_object(TABLE, limit=10):
        if r.get("key") == KEY:
            cur = r
            break
    if not cur:
        ctx.response.json({"weight": None, "state": "idle", "at": None,
                           "server_at": None, "server_now": server_now})
        return
    ctx.response.json({
        "weight": cur.get("weight"),
        "state": cur.get("state", "idle"),
        "at": cur.get("at"),
        "server_at": cur.get("server_at"),
        "server_now": server_now,
    })
