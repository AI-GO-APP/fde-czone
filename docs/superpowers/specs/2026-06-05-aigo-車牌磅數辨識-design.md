# aigo 端：車牌 + 磅數辨識地基 — 設計文件

> 日期：2026-06-05
> 範圍：薪榮環保地磅系統的 **aigo 雲端端「離線可完成的地基」**。
> 對應工單：`車牌+磅數辨識_開發工單`（第 0、2 節）。
> 平台：AI GO Custom App（參考桌面 `fde-sc1984` 的部署模式）。

---

## 1. 這份文件的範圍

這次**只做 aigo 端、且離線就能完成、不卡客戶**的地基：

- 資料模型（Odoo 系統表對應 + 兩張自建表）
- 三支 Action 骨架：`recognize_plate`、`read_weight`、`weigh`
- agent ↔ aigo 的請求/回應契約
- 列印 payload 契約（對齊 Fast Report 欄位）
- 寫回路徑的設計（API Key），確切平台路徑列為 Spike 驗證

**明確不在這次範圍**（工程師現場也是這樣分期的）：
管理 / 查詢 UI、電子發票、廢棄物自動申報、庫存 / 出貨平衡、標案爬蟲、現場 agent 程式本體、印表機實體串接。

---

## 2. 業務脈絡（來自 launch meeting 逐字稿）

薪榮環保是**廢棄物處理公司**：廢木材進廠 → 破碎分選 → 木屑成品出廠。**金流是反的**——別人把廢木材送來，薪榮跟對方**收處理費**，主要業務在「進料」這側。

**地磅核心流程**：
1. 車載料進場 → 第一次過磅 = **毛重**（重車）
2. 進場倒料
3. 倒完空車出場 → 第二次過磅 = **空重**
4. **淨重 = 毛重 − 空重**

地磅顯示器的自動回傳**壞了一年多**，目前全靠人工讀數字、人工 key 表並印三聯磅單。本案就是要把「讀車牌 + 讀重量 + 配對 + 印單」自動化。

**關鍵業務規則**（影響資料模型與邏輯）：

| 規則 | 內容 |
|---|---|
| 料種二磅後才知道 | 分「棧板料」「裝潢料」兩種、單價不同；**二次過磅後由人員點選 / 修正**，可給廠商預設值 |
| 車號 ≠ 死綁客戶 | 給「車號→預設客戶」當預設值，但要能人工改「這車今天的料其實是 B 家」。原則：**料配客戶，不要車死綁客戶** |
| 車頭車尾 | 拖車進場拍車尾、出場拍車頭 → 車牌不同 → 配對會失敗。做到 90%，例外標記人工處理 |
| 單價 | 大多固定（一季動一次），需留人工干預（單次某車加價）；最好能回溯歷史 |
| 結帳 | 多數月結（月底，一家 25 號）；也有單車「當下結帳付錢走」。結過的月結時篩掉 |
| 隨車聯單 | 廢棄物申報用，只人工勾「有沒有單」、不掃描；後期自動加總申報 |

---

## 3. 資料模型

**原則：能貼 Odoo 系統表就貼，貼不上才自建。** 已於 2026-06-05 登入 czone（`admin@czone.com`）實際驗證下列 Odoo 表皆存在。

### 3.1 主檔走 Odoo 系統表（已驗證存在）

| 薪榮概念 | Odoo 表 | 採用欄位 |
|---|---|---|
| 客戶 / 廠商 | `customers` | `name`、`vat`(統編)、`customer_type`、`payment_term`(結帳條件)、`short_name`、`phone`、`contact_person` |
| 料種（棧板 / 裝潢） | `product_templates` + `product_products` | `name`、`categ_id`、`standard_price`、`uom_id`(公噸) |
| 預設單價（客戶×料種） | `product_supplierinfo` | `partner_id`/`supplier_id`、`product_id`、`price`、`date_start`/`date_end`(時效) |
| 月結 / 發票（phase 2-3） | `sale_orders` + `sale_order_lines` | 結帳時生成 |

> 註：每張 Odoo 表都有 `custom_data`(JSON) 欄位，但 proxy 能否讀寫尚未驗證，**本案不依賴它**。

### 3.2 自建表（Odoo 無對應，必須自建）

只有兩張。x_ 表走 `ctx.db.query_object` / `ctx.db.insert`，不需 AppDataReference 授權層（tenant 共用）。

#### `x_czone_weighing`（過磅紀錄 — 核心）

過磅生命週期：一磅(只有毛重+車號) → 倒料 → 二磅(空重) → 點料種 → 結帳。在一磅當下還沒客戶確認、沒料種、沒單價，硬塞 `sale_orders`（需 `customer_id`、`state` 被 Odoo 鎖）會打架，故自建；**結帳時再生成 `sale_orders`**。

| 欄位 | 型別 | 說明 |
|---|---|---|
| `ticket_no` | string | 單號，如 `20260602-001` |
| `plate` | string | 車號（辨識帶入 / 人工） |
| `customer_id` | string→customers.id | 客戶（預設帶入、可人工改） |
| `material_id` | string→product_products.id | 料種（二磅後人工點選，前期為 null） |
| `gross_weight` | number | 毛重（一磅） |
| `tare_weight` | number? | 空重（二磅前 null） |
| `net_weight` | number? | 淨重 = 毛 − 空（自動算） |
| `unit_price` | number? | 單價（結帳當下快照，可改；phase 2） |
| `amount` | number? | 金額 = 淨重 × 單價（phase 2） |
| `first_weigh_at` | datetime | 進場時間 |
| `second_weigh_at` | datetime? | 出場時間 |
| `status` | string | `open`(待二磅) / `done`(已完成) |
| `has_manifest` | bool | 是否有隨車聯單 |
| `settle_status` | string | `unsettled` / `settled`（phase 2） |
| `settled_at` | datetime? | 結帳時間 |
| `weigh_operator` | string | 過磅人員 |
| `plate_source` | string | `alpr` / `manual`（車牌來源） |
| `plate_confidence` | number? | 辨識信心 |
| `weight_source` | string | `ocr` / `manual`（重量來源） |
| `image_ref` | string? | 車牌 / 畫面影像連結（留存） |
| `note` | string | 備註 |

#### `x_czone_vehicle`（車籍 — 車號→預設客戶）

| 欄位 | 型別 | 說明 |
|---|---|---|
| `plate` | string (unique) | 車號 |
| `default_customer_id` | string→customers.id | 預設客戶 |
| `default_material_id` | string→product_products.id? | 預設常見料種 |
| `manual_only` | bool | 一律人工處理（車頭車尾例外的車） |
| `note` | string | 備註 |
| `active` | bool | 是否啟用 |

> 待驗證：czone 租戶建立 x_ 自建表的方式（平台 UI 或 Custom Table API）；沿用 sc1984 既有 x_ 表的建立慣例。

---

## 4. 資料流（白話）

以「一台車進場到出場」走一遍：

**第一次過磅（重車）**
1. 過磅人員按按鈕，現場 agent 拍畫面（含車牌，盡量含地磅顯示器數字）。
2. agent 用 API Key 把畫面（必要時附人工讀數）送上 aigo。
3. aigo：讀車牌 → 讀重量（讀不到請人員補）→ 查車籍帶預設客戶 → 判斷「無未完成紀錄 = 第一次」→ 開新單記毛重、單號、客戶、進場時間。
4. 回傳結果 + 列印 payload，agent 印磅單。

**第二次過磅（空車）**
5. 倒完料回到地磅，再按一次、再拍照上傳。
6. aigo 讀車牌，發現「有未完成紀錄 = 第二次」→ 填空重、算淨重、標 `done`。
7. 人員此時點選料種（棧板/裝潢）。
8. 回傳結果 + 列印 payload，印最終磅單。

---

## 5. 三支 Action（這次做骨架）

**拆三支、各自單一職責，好測好換。** 辨識先 mock，金鑰 / OCR 到位再換真呼叫。

### 5.1 `recognize_plate`（車牌辨識）
- input：圖片　output：`{plate, confidence}`
- `httpx` 打 Plate Recognizer，金鑰走 `ctx.secrets.get("alpr_key")`
- **這次先 mock 固定回傳**，沒金鑰也能跑；Spike 直接測這支

### 5.2 `read_weight`（磅數 OCR）
- input：圖片（地磅顯示器區域）　output：`{weight, confidence}`
- 七段顯示器 OCR；**可行性待客戶提供清晰畫面驗證（工單第 5 節）**
- **這次先 mock**；OCR 失敗 / 未啟用時，由 `weigh` 改吃人工輸入的 `weight`

### 5.3 `weigh`（過磅配對 — 核心業務邏輯，也是對 agent 的入口）
- input：`{image, weight?, manual_plate?, weigh_operator}`（即第 6 節 agent 送的請求）
- **內部編排**：先呼叫 `recognize_plate` 取車牌（`manual_plate` 有給就用人工值）、呼叫 `read_weight` 取重量（OCR 失敗 / 未啟用則用人工 `weight`），再執行下方配對狀態機。
- 狀態機：

| 該車號目前 | 判定 | 動作 |
|---|---|---|
| 無 `open` 紀錄 | **一磅**（重車） | 建新紀錄：產生單號、`gross_weight=weight`、`customer_id`=查車籍預設、`first_weigh_at`、`status=open` |
| 有 `open` 紀錄 | **二磅**（空車） | 更新該筆：`tare_weight=weight`、`net_weight=gross−tare`、`second_weigh_at`、`status=done` |

- output：整筆紀錄 + 列印 payload + `needs_manual`（哪些欄位要人工補）

**配對邊界情況**：

| 情況 | 處理 |
|---|---|
| 連續車交錯 | OK：每車號同時最多一筆 `open`，車號即可配對 |
| 同車一天多次 | OK：每次 open→done 一循環，下次新單 |
| 車頭車尾車牌不同 | ⚠️ 已知限制：會變兩筆 open → 標記 `manual_only` + 管理 UI 人工處理 |

**單號規則**：`YYYYMMDD-NNN`（當日流水號，於建立一磅紀錄時產生）。

---

## 6. agent ↔ aigo 契約

### 請求（過磅事件）
agent 用 self_built 整合產生的 **API Key** 呼叫 aigo：

```json
{
  "image": "<base64 或 URL>",
  "weight": 25.0,
  "weigh_operator": "王小明",
  "manual_plate": "ABC-1234"
}
```
- `image` 必填（車牌必含，磅數顯示器盡量含）
- `weight` 選填：OCR 失敗 / 未啟用時的人工讀數
- `manual_plate` 選填：辨識失敗時人工指定

### 回應
```json
{
  "ticket_no": "20260602-001",
  "event": "first",
  "plate": "ABC-1234",
  "customer_name": "○○環保",
  "gross_weight": 25.0,
  "tare_weight": null,
  "net_weight": null,
  "print_payload": { "...": "見第 7 節" },
  "needs_manual": ["weight"]
}
```

### 寫回路徑
- 契約：**agent 只透過 API Key 呼叫 aigo，不直接碰資料表**——配對 / 算淨重 / 產單號等業務邏輯集中在 aigo。
- 確切平台路徑（Open Proxy 寫表 vs API Key 觸發 action）有平台細節，**列為 Spike 驗證項**，不卡這次骨架。

---

## 7. 列印 payload 契約（對齊 Fast Report）

依桌面 `車牌辨識/fast_report.webp`（三聯磅單版面）的 `SR_` 欄位命名：

```json
{
  "company": "薪榮環保股份有限公司",
  "SR_Sn": "20260602-001",
  "SR_Tn": "ABC-1234",
  "SR_Date": "2026-06-02 11:57:18",
  "SR_User": "王小明",
  "SR_Direction": "進",
  "SR_Material": "廢木料-棧板",
  "SR_GwTon": 25.0,
  "SR_TwTon": 10.0,
  "SR_NwTon": 15.0
}
```
> 確切欄位清單與版面以客戶提供的 Fast Report `.fr3/.frx` **原檔**為準（工單第 5 節，仍卡客戶）。上表為依截圖推得的初版契約。

---

## 8. 已驗證的事實（2026-06-05 登入 czone）

- App：`薪榮內部應用`，`app_id = 09718e5c-121d-4e09-af24-8fb3dab5b037`，`slug = 7280f9ec3093`
- Odoo 表 `customers`、`suppliers`、`product_templates`、`product_products`、`product_supplierinfo`、`sale_orders`、`sale_order_lines`、`uom_uom`、`product_categories`、`purchase_orders` 皆存在且欄位齊全
- 部署模式沿用 sc1984：登入取 JWT → `ensure_references` → 上傳 VFS → 編譯 → 發布

> 憑證不入 repo / 文件；金鑰放 aigo secrets（`ctx.secrets`）。

---

## 9. 測試素材（桌面 `車牌辨識/`）

| 檔案 | 內容 | 用途 |
|---|---|---|
| `line_oa_chat_260602_164553.webp` | 「進車過磅畫面」(一磅，車尾朝鏡頭) | Plate Recognizer Spike |
| `line_oa_chat_260602_164557.webp` | 「下料後過磅畫面」(二磅) | Plate Recognizer Spike |
| `fast_report.webp` | 三聯磅單 Fast Report 版面 | 列印 payload 欄位來源 |

**觀察到的真實風險**：車離鏡頭遠、車牌偏小；進場那張車尾朝鏡頭。**辨識率能否達 90% 須以 Spike 實測**；磅數顯示器未清楚入鏡，**磅數 OCR 可行性仍未定**。

---

## 10. 已知限制與待客戶輸入

- **車頭車尾**：少數車兩次車牌不同，配對失敗 → 人工處理（`manual_only`）。
- **磅數 OCR**：需客戶「夠近夠清晰的磅數畫面」才能定可行性（工單第 5 節）。
- **Fast Report `.fr3/.frx` 原檔**：列印精確版面所需（工單第 5 節）。
- **Plate Recognizer 金鑰**：使用者註冊取得後放 aigo secrets，辨識 Spike 才能真跑。
- **x_ 自建表建立方式**：部署時驗證 czone 租戶的建立流程。

---

## 11. 後續分期（工程師現場共識）

1. **第 1 個月（~1.5 月）**：車牌辨識 + 印磅單 + 資料進系統 ← 本地基支撐這塊
2. **+0.5~1 月**：電子發票串接（財政部）
3. **第 2~3 月**：月結 + 當車三件事（選料種、當下結帳、勾隨車聯單）
4. **後期**：廢棄物自動申報、標案爬蟲、統計分析
