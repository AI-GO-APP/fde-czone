# aigo custom app 驗證前端 — 設計

> 日期:2026-06-22
> 狀態:設計核可,待寫實作計畫
> 範圍:**只做 aigo 平台上的「驗證用」輸入前端**。本地列印畫面為後續另一份 spec。

## 1. 背景與目的

薪榮地磅專案要把「過磅資料 → 印三聯磅單」自動化。資料的真實來源是 aigo 雲端資料表
`x_czone_weighing`;本地 agent 負責「從 aigo 撈資料 → GDI 列印」(已驗證可行,另案)。

本前端的目的:在 aigo custom app 上提供一個**最小輸入畫面**,讓人手動產生過磅資料寫進
`x_czone_weighing`,以便:
1. 驗證 aigo 前端 → 後端 action → 資料表 的寫入鏈;
2. 產生真實流程的資料,供本地 agent 撈取 + 列印,完成端到端驗證。

**此畫面為驗證/暫時性**:之後真實資料來源(地磅 + 攝影機/OCR 或上游匯入)就緒後會移除。
因此投入以「夠驗證、低成本」為原則。

## 2. 架構與平台機制(模式 A)

- 前端是 React app,位於 `aigo-app/vfs/src/`,由 `scripts/deploy.py` 上傳 VFS → compile → publish,
  執行在 aigo 平台(此為平台首次發布前端,須處理首發流程,見 §7)。
- 呼叫後端用**平台注入的全域變數**(非 npm SDK):
  - `window.__APP_TOKEN__`:登入使用者的 Bearer token
  - `window.__API_BASE__`:API 基底(預設 `/api/v1`)
  - `window.__APP_ID__`:custom app id
  - `window.__IS_EXTERNAL__`:是否外部 app(決定 action URL 前綴)
- 以原生 `fetch` 帶 `Authorization: Bearer ${__APP_TOKEN__}` 與 `credentials:'include'` 打 REST。
  **不嵌 admin 金鑰,不連 localhost**(平台 CSP 會擋 localhost;本地列印另由 agent server-to-server 拉)。

## 3. 元件 / 檔案

```
aigo-app/vfs/src/
├─ aigoClient.ts   手寫薄層 (仿 sc1984 db.ts), 包 fetch
├─ App.tsx         驗證畫面: 輸入表單 + 最近紀錄列表
└─ main.tsx        現有, 不動
```

### `aigoClient.ts`(單一後端入口)
- `callAction(name, params)`:`POST {API_BASE}/actions/apps/{APP_ID}/run/{name}`,body `{params}`。
  - 此路徑已在本專案後端實測可用(`Test-Aigo`/`deploy.py`)。
  - 若平台前端實際走 `/actions/run/{app_id}/{name}` 或外部 `/ext/actions/run/{name}`,於首次部署時驗證並切換(見 §8)。
- `getObjectId(slug)`:`GET {API_BASE}/data/objects`,快取 `api_slug → id`。
- `listRecords(slug)`:`GET {API_BASE}/data/objects/{id}/records`,回 `[{id, data:{...}}]`。
- 統一錯誤處理:非 2xx 或 weigh 信封 `status!=='success'` 時拋出可顯示訊息。

### `App.tsx`
- **輸入表單**:車號 `plate`、重量 `weight`(公噸)、操作員 `weigh_operator`;
  送出時固定帶 `plate_source:'manual'`、`weight_source:'manual'`。
- **「過磅」按鈕** → `callAction('weigh', {...})` → 顯示回應:單號 `ticket_no`、`event`(first 一磅 / second 二磅)、
  毛/空/淨重、`needs_manual`(如 `["customer"]`)。
- **最近紀錄列表**:`listRecords('x_czone_weighing')`,顯示 單號 / 車號 / 操作員 / 狀態 / 毛重 / 淨重 / 時間;
  送出成功後自動刷新。

## 4. 寫入路徑決策:用 `weigh` action(非直接 insert)

表單 → `weigh` action(`vfs/actions/weigh.py` 已存在):自動判一磅/二磅、產生單號 `YYYYMMDD-NNN`、
配對算淨重、寫 `x_czone_weighing`、回 `print_payload`。
- 優點:同時驗證真實業務邏輯;本地 agent 撈到的就是真實流程資料。
- 不採直接 `POST .../records`(會繞過單號/淨重/配對邏輯,較不真實)。

## 5. 資料流

```
使用者輸入(車號+重量+操作員)
   → callAction('weigh')  ── 寫 x_czone_weighing + 回 print_payload
   → 前端顯示回應 + 刷新最近紀錄列表
   ⋯(獨立)本地 agent 之後 server-to-server 從 x_czone_weighing 撈同一筆 → GDI 列印
```

## 6. 錯誤處理

- action 回信封 `{status, result, error}`:`status!=='success'` → 顯示 `error`。
- 網路 / 401:顯示明確訊息(token 由平台注入,過期則提示重新整理/重新登入)。
- 中文:瀏覽器 `fetch` 原生 UTF-8,無 PowerShell 5.1 的編碼問題。

## 7. 部署 / 測試(驗證準則)

- 部署:`set -a && source .env && set +a && python3 aigo-app/scripts/deploy.py`
  (上傳 VFS → compile → publish)。此為平台**首次發布前端**,須確認 compile/publish 流程
  (PLATFORM_NOTES §6:全新 app 首發前 compile 會 404,需處理首發)。
- 端到端驗證:開 app → 送一筆(例 車號 KEP-2758、重量 14.54、操作員 王小明)→
  最近紀錄出現該筆 → 用本地 `Test-Aigo`/agent 撈到同一筆並出 PDF。三者一致即通過。

## 8. 開放項目(實作時確認,不阻擋設計)

- **action URL 形式**:前端用 `/actions/apps/{app_id}/run/{name}`(後端已測)還是 `/actions/run/{app_id}/{name}` /
  `/ext/actions/run/{name}`(視 `__IS_EXTERNAL__`)— 首次部署實測決定,client 預留 fallback。
- 首次 compile/publish 是否需額外步驟(見 §7)。

## 9. 範圍外(後續另案)

- 本地列印畫面(列出雲端紀錄 → 選 → 預覽 → 列印)。
- 時區(UTC → +8)、公噸 ↔ KG 單位顯示、`customer_id`/`material_id` → 名稱(join 車籍/料種)。
- 真實資料來源(地磅 + 攝影機/OCR)取代本驗證表單。
