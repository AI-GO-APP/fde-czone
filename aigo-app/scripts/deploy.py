# aigo-app/scripts/deploy.py
"""薪榮 aigo 內部應用部署：登入→設 References→上傳 VFS→編譯→發布。
用法：set -a && source .env && set +a && python3 aigo-app/scripts/deploy.py"""
import json, sys, os, urllib.request, urllib.error

API_BASE = "https://ai-go.app/api/v1"
HERE = os.path.dirname(__file__)
VFS_DIR = os.path.join(HERE, "..", "vfs")
sys.path.insert(0, os.path.join(HERE, "..", "vfs", "scripts"))
from refs import REFS


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


def login(email, password):
    s, b = _req("POST", f"{API_BASE}/auth/login",
                {"Content-Type": "application/json"},
                {"email": email, "password": password})
    if s != 200 or not b.get("access_token"):
        sys.exit(f"❌ 登入失敗：{s} {b}")
    return b["access_token"]


def ensure_references(h, app_id):
    s, b = _req("GET", f"{API_BASE}/refs/apps/{app_id}", h)
    existing = {x["table_name"]: x for x in (b if s == 200 else [])}
    for t in REFS:
        tn = t["table_name"]
        if tn in existing:
            s2, _ = _req("PATCH", f"{API_BASE}/refs/{existing[tn]['id']}", h,
                         {"columns": t["columns"], "permissions": t["permissions"]})
        else:
            s2, _ = _req("POST", f"{API_BASE}/refs/apps/{app_id}", h, t)
        print(f"  [{tn}] {s2}")


def read_vfs(vfs_dir):
    vfs = {}
    for root, _, files in os.walk(vfs_dir):
        for fname in files:
            full = os.path.join(root, fname)
            rel = os.path.relpath(full, vfs_dir).replace(os.sep, "/")
            with open(full, "r", encoding="utf-8") as f:
                vfs[rel] = f.read()
    return vfs


def main():
    email, password, app_id = _env("AIGO_EMAIL"), _env("AIGO_PASSWORD"), _env("AIGO_APP_ID")
    print("[1/4] 登入...")
    h = {"Authorization": f"Bearer {login(email, password)}", "Content-Type": "application/json"}
    print("[2/4] 設定 DB References...")
    ensure_references(h, app_id)
    print("[3/4] 上傳 VFS...")
    vfs = read_vfs(VFS_DIR)
    s, b = _req("PUT", f"{API_BASE}/builder/apps/{app_id}/source", h, {"vfs_state": vfs}, timeout=60)
    print(f"  上傳: {s}")
    if s != 200:
        sys.exit(f"❌ 上傳失敗：{b}")
    print("[3.5/4] 編譯...")
    s, b = _req("GET", f"{API_BASE}/builder/apps/{app_id}", h)
    slug = b.get("slug", app_id)
    s2, r = _req("POST", f"{API_BASE}/compile/compile/{slug}", h, {}, timeout=60)
    if not r.get("success"):
        sys.exit(f"❌ 編譯失敗：{r.get('error')}")
    print("  編譯：成功")
    print("[4/4] 發布...")
    s, b = _req("POST", f"{API_BASE}/builder/apps/{app_id}/publish", h, {"published_assets": {}})
    print(f"  發布: {s}")
    if s not in (200, 201):
        sys.exit(f"❌ 發布失敗：{b}")
    print("✅ 部署完成")


if __name__ == "__main__":
    main()
