"""建立 x_ 自建表（Custom Object）：過磅紀錄 x_czone_weighing、車籍 x_czone_vehicle。

冪等：已存在的 object / field 會略過。建立後 promote 為 tenant 共用（app_id=null）。
建表後仍需執行 deploy.py（ensure_references 會為這兩張表設 AppDataReference 授權）。

用法：set -a && source .env && set +a && python3 aigo-app/scripts/setup_tables.py
"""
import json, os, sys, urllib.request, urllib.error

API_BASE = "https://ai-go.app/api/v1"

# (api_slug, 顯示名, [(field_key, 顯示名, field_type)])
TABLES = [
    ("x_czone_weighing", "過磅紀錄", [
        ("ticket_no", "單號", "text"), ("plate", "車號", "text"),
        ("customer_id", "客戶", "text"), ("material_id", "料種", "text"),
        ("gross_weight", "毛重", "number"), ("tare_weight", "空重", "number"),
        ("net_weight", "淨重", "number"), ("unit_price", "單價", "number"),
        ("amount", "金額", "number"), ("first_weigh_at", "進場時間", "date"),
        ("second_weigh_at", "出場時間", "date"), ("status", "狀態", "text"),
        ("has_manifest", "隨車聯單", "text"), ("settle_status", "結帳狀態", "text"),
        ("settled_at", "結帳時間", "date"), ("weigh_operator", "過磅人員", "text"),
        ("plate_source", "車牌來源", "text"), ("plate_confidence", "辨識信心", "number"),
        ("weight_source", "重量來源", "text"), ("image_ref", "影像", "text"),
        ("note", "備註", "text"),
    ]),
    ("x_czone_vehicle", "車籍", [
        ("plate", "車號", "text"), ("default_customer_id", "預設客戶", "text"),
        ("default_material_id", "預設料種", "text"), ("manual_only", "人工處理", "text"),
        ("note", "備註", "text"), ("active", "啟用", "text"),
    ]),
]


def _req(method, path, h, data=None, timeout=30):
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(f"{API_BASE}{path}", data=body, headers=h, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read() or b"null")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"null")
        except Exception:
            return e.code, "<non-json>"


def _env(k):
    v = os.environ.get(k, "").strip()
    if not v:
        sys.exit(f"❌ 環境變數 {k} 未設定")
    return v


def main():
    s, b = _req("POST", "/auth/login", {"Content-Type": "application/json"},
                {"email": _env("AIGO_EMAIL"), "password": _env("AIGO_PASSWORD")})
    if s != 200:
        sys.exit(f"❌ 登入失敗：{b}")
    h = {"Authorization": f"Bearer {b['access_token']}", "Content-Type": "application/json"}

    s, objs = _req("GET", "/data/objects", h)
    by_slug = {o["api_slug"]: o for o in (objs if isinstance(objs, list) else [])}

    for slug, name, fields in TABLES:
        if slug in by_slug:
            oid = by_slug[slug]["id"]
            print(f"= {name}({slug}) 已存在 id={oid}")
        else:
            s, b = _req("POST", "/data/objects", h, {"app_id": None, "name": name, "api_slug": slug})
            if s not in (200, 201):
                sys.exit(f"❌ 建立 {name} 失敗：{s} {b}")
            oid = b["id"]
            print(f"+ 建立 {name}({slug}) id={oid}")

        s, existing = _req("GET", f"/data/objects/{oid}/fields", h)
        have = {f.get("field_key") for f in (existing if isinstance(existing, list) else [])}
        added = 0
        for i, (key, fname, ftype) in enumerate(fields):
            if key in have:
                continue
            s, _ = _req("POST", f"/data/objects/{oid}/fields", h,
                        {"name": fname, "field_key": key, "field_type": ftype,
                         "is_required": False, "sequence": i})
            if s in (200, 201):
                added += 1
            else:
                print(f"   ❌ 欄位 {key}: {s}")
        print(f"   欄位：新增 {added}，既有 {len(have)}")

        _req("POST", f"/data/objects/{oid}/promote", h, {})  # 確保 tenant 共用
    print("✅ 自建表就緒（記得再跑 deploy.py 設定 AppDataReference 授權）")


if __name__ == "__main__":
    main()
