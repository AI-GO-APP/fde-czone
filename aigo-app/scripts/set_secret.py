# aigo-app/scripts/set_secret.py
"""設定 App Secret（可重複執行：已存在就更新值）。
用法：set -a && source .env && set +a && SECRET_NAME=gemini_key SECRET_VALUE=xxx python3 aigo-app/scripts/set_secret.py
（SECRET_VALUE 建議用 $(cat 檔案) 帶入，避免明碼留在 shell history）"""
import json, sys, os, urllib.request, urllib.error

API_BASE = "https://ai-go.app/api/v1"


def _req(method, url, headers, data=None, timeout=30):
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())


def _env(key):
    val = os.environ.get(key, "").strip()
    if not val:
        sys.exit(f"❌ 環境變數 {key} 未設定")
    return val


def main():
    email, password, app_id = _env("AIGO_EMAIL"), _env("AIGO_PASSWORD"), _env("AIGO_APP_ID")
    name, value = _env("SECRET_NAME"), _env("SECRET_VALUE")

    s, b = _req("POST", f"{API_BASE}/auth/login",
                {"Content-Type": "application/json"},
                {"email": email, "password": password})
    if s != 200 or not b.get("access_token"):
        sys.exit(f"❌ 登入失敗：{s} {b}")
    h = {"Authorization": f"Bearer {b['access_token']}", "Content-Type": "application/json"}

    s, existing = _req("GET", f"{API_BASE}/actions/apps/{app_id}/secrets", h)
    found = next((x for x in (existing if s == 200 else []) if x.get("key_name") == name), None)
    if found:
        s2, r = _req("PUT", f"{API_BASE}/actions/secrets/{found['id']}", h, {"value": value})
        print(f"🔄 更新既有 secret [{name}]：{s2}")
    else:
        s2, r = _req("POST", f"{API_BASE}/actions/apps/{app_id}/secrets", h,
                     {"key_name": name, "value": value, "description": "Gemini 視覺模型 API 金鑰（磅數 OCR）"})
        print(f"✅ 建立 secret [{name}]：{s2}")
    if s2 not in (200, 201):
        sys.exit(f"❌ 設定失敗：{r}")
    print("完成。")


if __name__ == "__main__":
    main()
