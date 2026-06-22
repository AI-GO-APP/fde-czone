# aigo 手動過磅表單補欄位 + CSS — 設計

> 2026-06-22。在既有 aigo custom app 前端的手動過磅表單上補「客戶名稱、料種」兩個手填欄，一路帶到列印 `print_payload`；並把樣式從 inline 改為 sc1984 既有的 Shadow-DOM 相容 CSS 做法。

## 目標與範圍

過磅人員在 aigo 前端表單手動填一張磅單並過磅。本次：
- **補欄位**：客戶名稱、料種（純手打文字，不接 legacy 主檔下拉）。
- **CSS**：改用 sc1984 既有的 `import App.css` + `:host,:root` 做法，讓樣式在 Shadow DOM 下生效。
- **不做**：扣水份、扣雜物、車行（開會明確排除，印單留白）。
- **不手填（自動）**：序號(ticket_no)、日期、時間、空重、淨重、車次。

## 欄位分類（依實體三聯磅單 14 格）

| 類別 | 欄位 | 來源 |
|---|---|---|
| 手填（已有） | 車號、重量、會磅員 | 表單 input |
| 手填（**本次新增**） | 客戶名稱、料種 | 表單 input（純文字） |
| 自動 | 序號(=ticket_no)、日期、時間、空重、淨重、車次 | weigh action |
| 留白不做 | 扣水份、扣雜物、車行 | — |

## 淨重/空重自動機制（已存在，不改）

`weigh.py` 以車號配對一磅/二磅：
- 一磅（無 open 紀錄）：當下重量存 `gross_weight`。
- 二磅（同車號有 open 紀錄）：當下重量存 `tare_weight`，`net_weight = gross − tare` 自動算。

表單只輸入「當下重量」一個數字，不做空重/淨重輸入框。
（假設第一次過磅為重車；順序顛倒會得負淨重，本次不處理。）

## 前端

### `aigo-app/vfs/src/App.tsx`
- 新增 state：`customer`、`material`，各一個文字 input。
- `submit()` 的 `callAction("weigh", {...})` 多帶 `customer`、`material`。
- 「最近紀錄」表格新增「客戶 / 料種」兩欄（核對用）。
- 移除 inline `style={{...}}`，改用 `className`（見 CSS）。

### `aigo-app/vfs/src/aigoClient.ts`
- `WeighingRow` 型別加 `customer_name?`、`material_name?`（顯示用）。
- `callAction` / `listWeighings` 不變。

### CSS（reference: sc1984 `vfs/ordering`）
- 新增 `aigo-app/vfs/src/App.css`，`main.tsx` `import "./App.css"`。
- 頂層選擇器用 `:host, :root { ... }`（`:host` 套 Shadow DOM、`:root` 退回一般環境）。
- 元件改用 class（如 `.wp-form`、`.wp-grid`、`.wp-field`、`.wp-btn`、`.wp-table`）。
- 驗證：實作後用 playwright 確認 shadow root 內確實有 `<style>`、樣式生效。

## 後端 `aigo-app/vfs/actions/weigh.py`

- `execute`：`params` 收 `customer`、`material`（字串）。
- `build_first_record`：新增 `customer_name`、`material_name` 欄位儲存（文字，不走關聯 id）。
- `build_print_payload`：補 `SR_Customer`（取 `customer_name`）、`SR_Material`（取 `material_name`）。
- 二磅沿用一磅已存的 `customer_name`/`material_name`。

## 資料模型 `x_czone_weighing`

- 新增文字欄 `customer_name`、`material_name`（與既有 `customer_id`/`material_id` 並存；手打先用文字欄，日後接主檔再升級關聯）。
- 若需在平台建欄：循 `scripts/setup_tables.py` 既有冪等流程。

## 測試

- **後端 TDD**（`tests/test_weigh_execute.py` / `test_print_payload.py`）：
  - 填 `customer`/`material` → 紀錄含 `customer_name`/`material_name`。
  - `build_print_payload` 輸出含 `SR_Customer`、`SR_Material`。
  - 二磅沿用一磅的 customer/material。
- **前端**：`aigoClient.test.ts` 既有；playwright 線上填表（含客戶/料種）→ 送出 → 確認 `print_payload` 兩欄有值、CSS 生效。

## 不在本次範圍

- legacy 主檔（客戶 72/料種 7/車籍 360）匯入與下拉選。
- 客戶由車牌自動帶。
- 扣水份/扣雜物/車行採集。
- 一磅/二磅順序顛倒的負淨重防呆。
