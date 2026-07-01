# 設計:aigo 即時磅重看板

- 日期:2026-07-01
- 狀態:設計中(待使用者審查)
- 相關:[[LiveWeightReader]](現場讀取 agent)、`aigo-app/`(雲端 app)

## 1. 目標與範圍

把地磅管理系統(ScalesManager)畫面上**即時跳動的磅重**,送上 aigo 雲端,讓遠端網頁能**即時**看到當下重量。

**第一版範圍(MVP):**
- 網頁顯示**一個大大的即時重量數字** + 單位(kg) + 最後更新時間。
- 資料過期/離線時顯示「⚠️ 離線」。
- 磅上無車(0)時顯示「0 kg / 待命」。

**不在本版範圍(YAGNI,日後可加):**
- 車牌 / 客戶 / 料種等情境資訊(reader 讀得到,但先不做)。
- 結合最近磅單清單(`x_czone_weighing`)。
- WebSocket/SSE 推播(aigo 目前為 request/response,見 §9)。
- 任何認證 / 權限改動。

## 2. 總體架構

四個角色接力,分屬三個位置。**只有跨到雲端的兩條線是「打 API」**(標 🔴):

```
┌──────────────── 🏭 現場(地磅這台電腦)────────────────┐
│  地磅螢幕 ─▶ reader(讀+抄)─▶ current-weight.json     │
│                                        │                │
│                                 pusher(讀檔+回報)      │
└─────────────────────────────────────────┼──────────────┘
                                           │ 🔴 打 API(推送 update_live_weight)
┌──────────────────── ☁️ aigo ────────────▼──────────────┐
│   Custom Object x_czone_live_weight(單筆)             │
│   action: update_live_weight(寫) / get_live_weight(讀) │
└─────────────────────────────────────────▲──────────────┘
                                           │ 🔴 打 API(輪詢 get_live_weight)
┌──────────────── 💻 瀏覽器(任何人)──────┼──────────────┐
│   即時磅重看板:每 1~2 秒輪詢 → 顯示大數字             │
└─────────────────────────────────────────────────────────┘
```

**設計原則:讀取與推送解耦。** reader 只負責「看地磅、抄到本機檔案」(純本機、最穩);pusher 負責「讀檔、回報雲端」(碰網路)。這台電腦網路不穩又偶發斷電,拆開後即使回報卡住,現場讀取也不受影響。

## 3. 元件與職責

| 元件 | 位置 | 現況 | 本版要做 |
|---|---|---|---|
| `reader`(`LiveWeightReader/Read-LiveWeight.ps1`) | 現場 | 已完成:讀即時重量、記 log | **多寫一個 `current-weight.json`** |
| `pusher`(新增 `LiveWeightReader/Push-LiveWeight.ps1`) | 現場 | 無 | **新增**:讀檔 → 按策略推 aigo |
| `AigoClient.ps1` | 現場 | 有 weigh 相關函式 | **加通用 action 呼叫 + 推即時重量** |
| Custom Object `x_czone_live_weight` | aigo | 無 | **新增**(單筆) |
| action `update_live_weight` / `get_live_weight` | aigo | 無 | **新增** |
| `refs.py` / `setup_tables.py` | aigo | 有 | **加新 slug 授權 + 建表** |
| 前端看板 | 瀏覽器 | 無 | **新增** view + `getLiveWeight()` |

## 4. 資料模型

### 4.1 現場本機檔案 `current-weight.json`(reader 寫)
reader 每次重量變動時寫入;即使沒變動,**至少每 5 秒改寫一次**(讓 `at` 反映 reader 還活著):
```json
{
  "weight": 4830,
  "at": "2026-07-01T14:03:13+08:00",
  "state": "weighing"
}
```
- `weight`:目前重量(整數,kg)。
- `at`:reader 讀到的時間(台灣本地時間 ISO8601)。
- `state`:`"weighing"`(重量≠0)或 `"idle"`(0)。

### 4.2 aigo Custom Object `x_czone_live_weight`(單筆)
永遠只有一筆,用固定 `key` 定位:

| 欄位 | 型別 | 說明 |
|---|---|---|
| `key` | text | 固定 `"current"`,用來找那唯一一筆 |
| `weight` | number | 目前重量(kg) |
| `at` | text | reader 讀到的時間(ISO8601,台灣本地)—**僅供顯示參考** |
| `server_at` | text | aigo 收到這筆更新的**伺服器時間**—**新鮮度以此為準** |
| `state` | text | `weighing` / `idle` |

> **為什麼要 `server_at`?** 現場電腦偶發斷電後,主機板 RTC 時鐘可能跑掉(曾出現「2125 年」)。若用現場時間判斷離線,時鐘一錯就失準。改由 **aigo 伺服器在收到更新時自己蓋時間戳**,新鮮度判斷就完全不受現場時鐘影響。

> 依 [[PLATFORM_NOTES]]:x_ 表為 Custom Object,用 `query_object/insert_object/update_object`,且須在 `refs.py` 授權。

## 5. 推送策略(pusher,事件觸發 + 心跳)

pusher **每 1 秒讀一次本機 `current-weight.json`**(純本機,不算 API),再決定要不要推雲端:

| 情況 | 推送行為 |
|---|---|
| `state=weighing`(有車) | 有變動就推,最快每 1 秒一筆 |
| 剛從有車→歸零 | 推最後一筆 `0`,轉入閒置 |
| `state=idle` 持續中 | **每 60 秒**推一筆「心跳」(`0` + 目前時間) |
| 檔案 `at` 已過時(> 15 秒沒更新 = reader 疑似掛了) | **停止推送**(讓雲端 `at` 凍結 → 前端判為離線) |

**重點:偵測車子靠「每 1 秒讀本機檔」,很快(1~2 秒內就推上雲);60 秒只用在「一直空著」的保活心跳,不會延遲車子的偵測。**

推送即呼叫 `update_live_weight`,body 依 [[PLATFORM_NOTES]] 為 `{"params": {...}}`;失敗為 **best-effort**(記 log、不 retry 到卡死、不影響 reader)。token 過期自動重登一次(沿用 `AigoClient.ps1` 既有模式)。

## 6. aigo Actions

### 6.1 `update_live_weight`(寫)
- params:`{ weight: number, at: string, state: "weighing"|"idle" }`
- 邏輯:**在 action 內以伺服器時間算出 `server_at`**(`datetime.utcnow()+TW_OFFSET`,同 `weigh.py`);`query_object(x_czone_live_weight)` 找 `key=="current"`,有則 `update_object`、無則 `insert_object`(含 `key:"current"`、`server_at`)。
- 回應:`ctx.response.json({ ok: true })`;缺參數回 `{"error": ...}`(平台無 `ctx.response.error`,見 [[PLATFORM_NOTES]])。

### 6.2 `get_live_weight`(讀)
- params:無。
- 邏輯:讀那唯一一筆,並**附上目前伺服器時間 `server_now`**(讓前端用同一個時間基準算新鮮度)。
- 回應:`{ weight, at, state, server_at, server_now }`;若尚無資料回 `{ weight: null, state: "idle", server_at: null, server_now: <現在> }`。

## 7. 前端看板

- 新增 view(元件 `LiveWeightBoard`),與現有「驗證輸入」表單並存(簡單導覽切換即可)。
- `aigoClient.ts` 新增 `getLiveWeight()` 呼叫 `get_live_weight`。
- **輪詢**:頁面開啟時每 **1.5 秒**呼叫一次 `getLiveWeight()`(頁面切到背景時瀏覽器會自動節流)。
- **顯示邏輯**(新鮮度 = `server_now − server_at`,**全用伺服器時間,不看現場/瀏覽器時鐘**):

| 條件 | 顯示 |
|---|---|
| `server_now − server_at > 90 秒`(或 `server_at` 為 null) | `⚠️ 離線`(灰底) + 「最後更新 HH:mm:ss」 |
| 新鮮 且 `state=weighing` 且 `weight≠0` | **大數字**(如 `4,830 kg`)+ 「更新於 HH:mm:ss」 |
| 新鮮 且 `weight=0`(待命) | `0 kg / 待命` |

## 8. 錯誤處理與韌性

- **現場斷電**:reader 與 pusher 皆停 → 雲端不再更新 → `server_at` 凍結 → 前端 > 90 秒判離線。(reader/pusher 皆由登入自動啟動排程復活,見 [[LiveWeightReader]])
- **reader 掛但 pusher 活**:檔案 `at` 過時 → pusher 停推 → `server_at` 凍結 → 前端離線。
- **網路斷**:pusher 推送失敗僅記 log,不影響現場;網路恢復後下次自然送出。
- **待命 vs 離線**:靠「閒置每 60 秒心跳」區分(心跳在=待命,心跳停=離線)。
- **現場時鐘跑掉**:新鮮度只用伺服器時間(`server_now/server_at`),即使現場 RTC 斷電後亂跳(如 2125 年)也不影響離線判斷;`at` 僅作人看的參考。
- **中文**:pusher 沿用 `AigoClient.ps1` 的 UTF-8 bytes 送法(本版無中文欄位,但沿用同一安全路徑)。

## 9. 未來升級路徑

- 若 aigo 日後支援 SSE/WebSocket → 前端可改推播、免輪詢(後端與資料模型不變)。
- 看板可再加:車牌/客戶/料種、最近磅單、穩定/進出提示。

## 10. 測試策略

- **aigo actions**(pytest,比照現有 `tests/`):`test_live_weight.py` — upsert 邏輯(無資料→insert、有資料→update)、缺參數回錯、`get` 空資料回 null。
- **pusher 決策**(純函式,可測):把「該不該推 / 是否心跳 / 是否判 reader 過時」抽成可測函式,給定 `(state, 上次推送時間, 檔案 at, 現在時間)` 驗證輸出。
- **前端新鮮度分類**(比照 `aigoClient.test.ts`):`classify(server_now, server_at, weight, state)` → `offline | weighing | idle` 的單元測試(含 `server_at=null`、剛好 90 秒邊界)。

## 11. 新增 / 修改檔案清單

**現場(`LiveWeightReader/`):**
- 修改 `Read-LiveWeight.ps1`:新增寫 `current-weight.json`(每次變動 + 至少每 5 秒)。
- 新增 `Push-LiveWeight.ps1`:pusher 主體 + 可測決策函式。
- 新增 `Install-PusherTask.ps1`:pusher 的登入自動啟動排程(比照 reader)。
- 修改 `agent/lib/AigoClient.ps1`:加通用 action 呼叫 + 推即時重量。

**aigo(`aigo-app/`):**
- 新增 `vfs/actions/update_live_weight.py`、`vfs/actions/get_live_weight.py`;更新 `manifest.json`。
- 更新 `vfs/scripts/refs.py`(授權 `x_czone_live_weight`)、`scripts/setup_tables.py`(建表)。
- 新增 `tests/test_live_weight.py`。

**前端(`aigo-app/vfs/src/`):**
- 新增 `LiveWeightBoard` 元件 + 導覽切換。
- `aigoClient.ts` 加 `getLiveWeight()`;對應測試。
