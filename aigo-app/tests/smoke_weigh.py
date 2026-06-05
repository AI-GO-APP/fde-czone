"""手動整合 smoke test：登入後連呼叫 weigh 兩次（同車牌），驗證一磅→二磅→淨重，
最後刪除測試紀錄保持 live 表乾淨。

前置：已跑過 setup_tables.py（建表）+ deploy.py（上傳 action、設授權）。
用法：set -a && source .env && set +a && python3 aigo-app/tests/smoke_weigh.py
"""
import json, os, sys, urllib.request, urllib.error

API = "https://ai-go.app/api/v1"
WEIGH_OBJ_SLUG = "x_czone_weighing"


def req(method, path, headers, data=None):
    body = json.dumps(data).encode() if data is not None else None
    r = urllib.request.Request(f"{API}{path}", data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(r, timeout=40) as resp:
            return resp.status, json.loads(resp.read() or b"null")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"null")
        except Exception:
            return e.code, "<non-json>"


def main():
    app_id = os.environ["AIGO_APP_ID"]
    s, b = req("POST", "/auth/login", {"Content-Type": "application/json"},
               {"email": os.environ["AIGO_EMAIL"], "password": os.environ["AIGO_PASSWORD"]})
    h = {"Authorization": f"Bearer {b['access_token']}", "Content-Type": "application/json"}
    run = f"/actions/apps/{app_id}/run/weigh"

    # 注意：run 端點需 {"params": {...}} 包裝（見 PLATFORM_NOTES.md）
    s, first = req("POST", run, h, {"params": {
        "plate": "SMOKE-001", "weight": 25.0, "weigh_operator": "smoke", "now": "2026-06-05T09:00:00"}})
    s, second = req("POST", run, h, {"params": {
        "plate": "SMOKE-001", "weight": 10.0, "weigh_operator": "smoke", "now": "2026-06-05T09:30:00"}})

    r1, r2 = first.get("result") or {}, second.get("result") or {}
    print("一磅:", first.get("status"), r1.get("event"), "ticket=", r1.get("ticket_no"))
    print("二磅:", second.get("status"), r2.get("event"), "net_weight=", r2.get("net_weight"))

    ok = (first.get("status") == "success" and r1.get("event") == "first"
          and second.get("status") == "success" and r2.get("event") == "second"
          and r2.get("net_weight") == 15.0)

    # 清除測試紀錄
    obj_id = None
    s, objs = req("GET", "/data/objects", h)
    for o in (objs if isinstance(objs, list) else []):
        if o.get("api_slug") == WEIGH_OBJ_SLUG:
            obj_id = o["id"]
    if obj_id:
        s, recs = req("GET", f"/data/objects/{obj_id}/records", h)
        for it in (recs if isinstance(recs, list) else []):
            if str(it.get("data", {}).get("plate", "")).startswith("SMOKE-"):
                req("DELETE", f"/data/records/{it['id']}", h)

    print("✅ smoke 通過" if ok else "❌ smoke 失敗")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
