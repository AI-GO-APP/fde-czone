# AI GO 平台實測筆記（czone）

> 2026-06-05 部署 + smoke 過程中實測，與桌面 `fde-sc1984` 舊文件有出入處特別標註。

## 1. Action 執行端點需 `params` 包裝
- 端點：`POST /api/v1/actions/apps/{app_id}/run/{action_name}`（內部 app，Admin Bearer）
- Body 必須是 `{"params": { ... }}`，**不是**平的 `{ ... }`。傳平的會導致 `ctx.params` 收不到值。
- 回應：`{"status": "success"|"error", "result": <ctx.response.json 內容>, "error": <訊息>, "execution_id", "duration_ms"}`

## 2. `ctx.response` 沒有 `.error()`
- 舊文件寫有 `ctx.response.error(msg)`，**實測不存在**（`'ResponseModule' object has no attribute 'error'`）。
- 改用 `ctx.response.json({"error": msg})` 回報錯誤。

## 3. x_ 自建表 = Custom Object，讀寫方法與 Odoo 表不同
| 操作 | Odoo 實體表 | Custom Object（x_，經 /data/objects 建立） |
|---|---|---|
| 讀 | `ctx.db.query(table, ...)` | `ctx.db.query_object(slug, ...)` → **回扁平 dict** |
| 新增 | `ctx.db.insert(table, data)` | `ctx.db.insert_object(slug=..., data=...)` |
| 更新 | `ctx.db.update(table, id, data)` | `ctx.db.update_object(slug=..., record_id=..., data=...)` |
| 刪除 | `ctx.db.remove(table, id)` | `ctx.db.remove_object(slug=..., record_id=...)` |
- 對 Custom Object 用 `ctx.db.insert(slug, ...)` 會組原生 SQL `INSERT INTO <slug>` → `UndefinedTableError: relation does not exist`。
- `query_object` 在 action 內回**扁平** dict（欄位在頂層）；REST `/data/objects/{id}/records` 則是 `{id, data:{...}}` 包裝。

## 4. x_ Custom Object 也需 AppDataReference 授權
- 舊文件稱 x_ 表「不需 ref」，**實測需要**：否則 `query_object` 回 `403 App 未被授權存取表 'x_...'`。
- 解法：把 x_ slug 加進 `vfs/scripts/refs.py` 的 REFS（read/create/update），跑 `deploy.py` 的 `ensure_references`。

## 5. Custom Object 建立流程
- `POST /data/objects` `{app_id: null, name, api_slug}` → 建表（app_id=null 為 tenant 共用；api_slug 不會被改寫）
- `POST /data/objects/{id}/fields` `{name, field_key, field_type: text|number|date|relation, ...}` → 逐欄建立
- `POST /data/objects/{id}/promote` → 確保 tenant 共用
- 見 `scripts/setup_tables.py`（冪等）。

## 6. 前端 compile/publish 對全新 app 會卡，但 Action 不受影響
- `POST /compile/compile/{slug}` 對尚無已發布版的 app 回 `404 App 尚無已發布版 (published_vfs)內容`。
- **Action 上傳 source 後即可執行**，不需 compile/publish。故 `deploy.py` 將 compile/publish 設為 best-effort（失敗僅警告）。
- 待有實際前端 UI 時再處理首次發布流程。
