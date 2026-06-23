# 本地列印畫面(撈 aigo 紀錄 → 選 → 預覽/列印)— 設計

> 日期:2026-06-22
> 狀態:設計核可,待寫實作計畫
> 分支:`feat/local-print-screen`

## 1. 目的與範圍

現場 PC 上的本地 agent 需要一個操作畫面:**列出 aigo `x_czone_weighing` 最近過磅紀錄 → 操作員選一筆 → 預覽 PDF 或直接列印三聯地磅單**(EPSON LQ-690CII)。

資料真實來源是 aigo 雲端(輸入端由 aigo custom app / 之後真實設備產生)。本地 agent 的角色是「**抓 + 印**」,對 aigo **唯讀**。本案完成「本地拉資料 → 列印」這一段。

承接既有成果:`agent/lib/AigoClient.ps1`(登入/撈紀錄)、`agent/lib/PrintEngine.ps1`(對應 + GDI 渲染)、`agent/Start-Agent.ps1`(HttpListener)、`WeighTicketPrint/`(列印引擎、薪榮校正、硬體邊界補償)皆已存在並驗證過。

## 2. 架構

擴充現有 `agent/`,不另起爐灶:
- 本地 HttpListener(localhost)服務一個網頁 + JSON 端點。
- 網頁(瀏覽器,本機)列出紀錄、選取、觸發預覽/列印。
- 列印走既有 GDI 路徑(含硬體邊界補償 + 薪榮版面校正)。
- 對 aigo **唯讀**:只 `GET` 撈紀錄,不回寫。

## 3. 對應修正(PrintEngine,配合目前 aigo 資料)

目前 `x_czone_weighing` 紀錄欄位(實測):`customer_name`、`material_name`(文字,有值)、`gross/tare/net_weight`(KG,float 如 `14540.0`)、`weigh_operator`、`ticket_no`、`plate`、`first/second_weigh_at`(UTC+8)、`status`。

- `ConvertFrom-WeighingData` 改對應:
  - `customer_name` → `SR_Customer`(取代原本 `customer_id`)
  - `material_name` → `SR_Material`(取代原本 `material_id`)
  - 其餘不變:`ticket_no`→SR_SN、`plate`→SR_CarNo、`weigh_operator`→SR_User、`second_weigh_at` 優先否則 `first_weigh_at`→SR_DatetimeG、`gross/tare/net`→毛/空/淨。
- **重量整數化**:float 為整數值時去小數,`14540.0` → `14540`(套版面後為 `14540 KG`)。
- 註:`車行`(SR_Traffic)、`車次`(SR_Times)aigo 無對應資料,留白(可接受)。

## 4. agent 端點(Start-Agent.ps1)

- `GET /records` → 最近 **N=50** 筆(新到舊)JSON:`id, ticket_no, plate, customer_name, material_name, weigh_operator, gross_weight, net_weight, status, at`。(撈回後依 `at` 新到舊排序取前 50;`Resolve-AigoWeighings` 已回全部,於 agent 端排序截斷。)
- `POST /print-record` `{ id, mode: "pdf"|"print" }` → 用 `Resolve-AigoWeighings` 撈回清單後**以 `id` 比對取該筆**(清單不大,免額外端點)→ `ConvertFrom-WeighingData` → `mode=pdf` 出 `out/preview.pdf` 並回 `pdfUrl`;`mode=print` 走 `Invoke-TicketPrint` 送印。`mode` 預設 `pdf`。
- 保留 `GET /health`、`GET /preview.pdf`。
- **移除**舊的手動輸入表單流程(舊 `POST /print` 與舊 index.html 手填表單),改為列表畫面。

## 5. 前端(index.html 改寫)

- 紀錄表格(最近 N、新到舊):單號 / 車號 / 客戶 / 料種 / 操作員 / 毛重 / 淨重 / 狀態 / 時間。
- 「重新整理」鈕(手動)。
- 點一列 = 選取;選取後出現「**預覽 PDF**」「**列印真紙**」兩鈕(列印真紙需 `confirm`)。
- 顯示操作結果訊息;預覽以 iframe 顯示 `pdfUrl`。
- 字型微軟正黑體。

## 6. 資料流

```
index.html  GET /records
   → 表格(最近 N)
   → 操作員點一列(取得 id)
   → POST /print-record { id, mode }
        → agent 依 id 撈該筆 (AigoClient)
        → ConvertFrom-WeighingData → .frx 資料字典
        → mode=pdf: Export-TicketPdf → 回 pdfUrl(iframe 顯示)
        → mode=print: Invoke-TicketPrint → 送 EPSON
```

## 7. 錯誤處理

- aigo 登入/網路失敗、找不到該 `id`、找不到印表機 → 回 JSON `{ok:false, reason}`,前端顯示訊息。
- token 過期:`Resolve-*` 既有自動重登一次。

## 8. 測試

- **單元**(零安裝 PowerShell 測試,`agent/tests/Run-Tests.ps1`):`ConvertFrom-WeighingData` — `customer_name`/`material_name` 正確對應、重量 `14540.0`→`"14540"`、日期 `d`/時間 `HH:mm`、second 優先 first。
- **端到端**:啟動 agent → 開本地畫面 → 列表出現 aigo 最新一筆(例 `20260622-001` / 測試環保 / 王小明)→ 預覽 PDF 對版面 → 列印真紙(人工確認紙張)。

## 9. 範圍外(另案)

- 回寫「已列印」狀態到 aigo。
- 自動輪詢(本案只做手動重新整理)。
- 手動輸入表單(本案移除)。
- 真實設備(地磅 + 攝影機)輸入端(由 aigo 側處理)。
