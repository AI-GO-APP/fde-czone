# aigo 手動過磅表單補欄位 + CSS 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 aigo 手動過磅表單補「客戶名稱、料種」兩個手填欄並帶到列印 payload，且把樣式改成 Shadow DOM 相容的 CSS。

**Architecture:** 前端 React custom app（薄層 fetch + 平台注入 token）呼叫後端 `weigh` action；後端寫入 `x_czone_weighing` custom object 並回 `print_payload`。客戶/料種以文字欄儲存（不接主檔關聯）。

**Tech Stack:** Python(action, pytest)、React+TypeScript(vitest)、aigo Custom App REST。

## Global Constraints

- Action 呼叫 body 必為 `{"params": {...}}`；回應信封 `{status, result, error}`，成功取 `result`。
- x_ 自建表用 `ctx.db.query_object/insert_object/update_object`；新欄位建立後需跑 `deploy.py` 設 AppDataReference 授權。
- 所有文字 UTF-8；中文不可被轉成 `?`。
- 前端在 Shadow DOM：CSS 頂層選擇器用 `:host, :root`，元件用 className，`main.tsx` 以 `import "./App.css"` 載入。
- 不做：扣水份、扣雜物、車行（印單留白）。空重/淨重不手填（`weigh.py` 以車號配對自動算）。
- 後端測試：`cd aigo-app && python3 -m pytest tests/<file> -v`。
- 前端測試：`cd aigo-app/vfs && npm test`；型別檢查：`cd aigo-app/vfs && npm run typecheck`。

---

### Task 1: 後端 weigh action 帶 customer/material 進紀錄與 payload

**Files:**
- Modify: `aigo-app/vfs/actions/weigh.py`（`build_first_record`、`build_print_payload`、`execute`）
- Test: `aigo-app/tests/test_print_payload.py`、`aigo-app/tests/test_weigh_execute.py`

**Interfaces:**
- Produces: `build_first_record(..., customer_name="", material_name="")` 回的 dict 含 `customer_name`/`material_name`；`build_print_payload(record, direction)` 回的 dict 含 `SR_Customer`、`SR_Material`。

- [ ] **Step 1: 寫 failing test（payload 補 SR_Customer）**

在 `aigo-app/tests/test_print_payload.py` 末尾加：
```python
def test_payload_maps_customer_name():
    record = {"customer_name": "測試環保", "material_name": "廢木料-棧板"}
    payload = build_print_payload(record, "進")
    assert payload["SR_Customer"] == "測試環保"
    assert payload["SR_Material"] == "廢木料-棧板"

def test_payload_customer_defaults_to_empty():
    assert build_print_payload({}, "進")["SR_Customer"] == ""
```

- [ ] **Step 2: 寫 failing test（execute 存 customer/material 並回 payload）**

在 `aigo-app/tests/test_weigh_execute.py` 末尾加：
```python
def test_first_weigh_stores_customer_and_material():
    db = FakeDB(weighing=[], vehicle=[])
    ctx = FakeCtx({"plate": "ABC-1234", "weight": 25.0, "weigh_operator": "王小明",
                   "customer": "測試環保", "material": "廢木料-棧板",
                   "now": "2026-06-02T11:57:18"}, db=db)
    weigh.execute(ctx)
    rec = db.inserted[0][1]
    assert rec["customer_name"] == "測試環保"
    assert rec["material_name"] == "廢木料-棧板"
    pp = ctx.response.body["print_payload"]
    assert pp["SR_Customer"] == "測試環保"
    assert pp["SR_Material"] == "廢木料-棧板"

def test_second_weigh_keeps_first_customer_material():
    open_rec = {"id": "rec-1", "plate": "ABC-1234", "status": "open",
                "gross_weight": 25.0, "ticket_no": "20260602-001",
                "customer_name": "測試環保", "material_name": "廢木料-棧板",
                "first_weigh_at": "2026-06-02T11:57:18"}
    db = FakeDB(weighing=[open_rec], vehicle=[])
    ctx = FakeCtx({"plate": "ABC-1234", "weight": 10.0, "weigh_operator": "王小明",
                   "now": "2026-06-02T12:05:54"}, db=db)
    weigh.execute(ctx)
    pp = ctx.response.body["print_payload"]
    assert pp["SR_Customer"] == "測試環保"
    assert pp["SR_Material"] == "廢木料-棧板"
```

- [ ] **Step 3: 跑測試確認失敗**

Run: `cd aigo-app && python3 -m pytest tests/test_print_payload.py tests/test_weigh_execute.py -v`
Expected: 新增的 4 個 test FAIL（`KeyError: 'SR_Customer'` / `customer_name` 不存在）。

- [ ] **Step 4: 改 `weigh.py`**

`build_first_record` 簽名末尾加兩參數，回傳 dict 加兩欄：
```python
def build_first_record(ticket_no, plate, customer_id, weight, now_iso,
                       plate_source, plate_confidence, weight_source,
                       weigh_operator, image_ref, customer_name="", material_name=""):
    """一磅：建立新過磅紀錄的完整欄位 dict。"""
    return {
        "ticket_no": ticket_no,
        "plate": plate,
        "customer_id": customer_id,
        "customer_name": customer_name,
        "material_id": None,
        "material_name": material_name,
        "gross_weight": float(weight),
        "tare_weight": None,
        "net_weight": None,
        "unit_price": None,
        "amount": None,
        "first_weigh_at": now_iso,
        "second_weigh_at": None,
        "status": STATUS_OPEN,
        "has_manifest": False,
        "settle_status": "unsettled",
        "settled_at": None,
        "weigh_operator": weigh_operator,
        "plate_source": plate_source,
        "plate_confidence": plate_confidence,
        "weight_source": weight_source,
        "image_ref": image_ref,
        "note": "",
    }
```

`build_print_payload` 加 `SR_Customer`（`SR_Material` 已存在）：
```python
def build_print_payload(record, direction):
    """組三聯磅單列印 payload（對齊 Fast Report SR_ 欄位）。"""
    return {
        "company": "薪榮環保股份有限公司",
        "SR_Sn": record.get("ticket_no"),
        "SR_Tn": record.get("plate"),
        "SR_Date": record.get("second_weigh_at") or record.get("first_weigh_at"),
        "SR_User": record.get("weigh_operator"),
        "SR_Direction": direction,
        "SR_Customer": record.get("customer_name") or "",
        "SR_Material": record.get("material_name") or "",
        "SR_GwTon": record.get("gross_weight"),
        "SR_TwTon": record.get("tare_weight"),
        "SR_NwTon": record.get("net_weight"),
    }
```

`execute` 的 first 分支，`build_first_record` 呼叫末尾加 customer/material：
```python
        rec = build_first_record(
            ticket_no, plate, customer_id, weight, now,
            p.get("plate_source", "manual"), p.get("plate_confidence"),
            p.get("weight_source", "manual"), p.get("weigh_operator", ""),
            p.get("image_ref"),
            p.get("customer", ""), p.get("material", ""),
        )
```
（second 分支不需改：`merged = {**open_rec, **upd}` 會帶出一磅已存的 `customer_name`/`material_name`。）

- [ ] **Step 5: 跑測試確認通過**

Run: `cd aigo-app && python3 -m pytest tests/ -v`
Expected: 全部 PASS（含原有測試不被破壞）。

- [ ] **Step 6: Commit**

```bash
git add aigo-app/vfs/actions/weigh.py aigo-app/tests/test_print_payload.py aigo-app/tests/test_weigh_execute.py
git commit -m "feat(weigh): 過磅紀錄存客戶/料種文字並帶進列印 payload

print_payload 補 SR_Customer、SR_Material；一磅手填、二磅沿用。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: 資料表 x_czone_weighing 加 customer_name / material_name 欄

**Files:**
- Modify: `aigo-app/scripts/setup_tables.py`（`TABLES` 的 `x_czone_weighing` 欄位清單）

**Interfaces:**
- Produces: 線上 `x_czone_weighing` 多兩個 text 欄 `customer_name`、`material_name`，並有讀寫授權。

- [ ] **Step 1: 改 TABLES 加兩欄**

在 `x_czone_weighing` 欄位清單中，`weigh_operator` 那行後面加一行：
```python
        ("weigh_operator", "過磅人員", "text"),
        ("customer_name", "客戶名稱", "text"), ("material_name", "料種", "text"),
        ("plate_source", "車牌來源", "text"), ("plate_confidence", "辨識信心", "number"),
```

- [ ] **Step 2: 跑建表腳本（冪等，只新增缺的欄）**

Run: `cd /home/username/桌面/fde-czone && set -a && source .env && set +a && python3 aigo-app/scripts/setup_tables.py`
Expected: 輸出 `過磅紀錄(x_czone_weighing) 已存在 id=...` 且 `欄位：新增 2，既有 N`。

- [ ] **Step 3: 跑 deploy.py 確保新欄授權**

Run: `cd /home/username/桌面/fde-czone && set -a && source .env && set +a && python3 aigo-app/scripts/deploy.py`
Expected: 無 403/授權錯誤；`ensure_references` 對 `x_czone_weighing` 設定 read/create/update 成功。

- [ ] **Step 4: Commit**

```bash
git add aigo-app/scripts/setup_tables.py
git commit -m "feat(schema): x_czone_weighing 加 customer_name/material_name 文字欄

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: 前端 aigoClient 帶出 customer_name / material_name

**Files:**
- Modify: `aigo-app/vfs/src/aigoClient.ts`（`WeighingRow`、`mapRecord`）
- Test: `aigo-app/vfs/src/aigoClient.test.ts`

**Interfaces:**
- Consumes: `mapRecord(raw)`（既有）。
- Produces: `WeighingRow` 多 `customer_name: string`、`material_name: string`；`mapRecord` 填這兩欄。

- [ ] **Step 1: 寫 failing test**

在 `aigo-app/vfs/src/aigoClient.test.ts` 的 `describe("mapRecord", ...)` 區塊內加（若無該 describe 則在檔末新增）：
```typescript
describe("mapRecord 客戶/料種", () => {
  it("帶出 customer_name 與 material_name", () => {
    const row = mapRecord({ id: "1", data: { customer_name: "測試環保", material_name: "廢木料-棧板" } });
    expect(row.customer_name).toBe("測試環保");
    expect(row.material_name).toBe("廢木料-棧板");
  });
  it("缺欄位時回空字串", () => {
    const row = mapRecord({ id: "2", data: {} });
    expect(row.customer_name).toBe("");
    expect(row.material_name).toBe("");
  });
});
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `cd aigo-app/vfs && npm test`
Expected: 新測試 FAIL（`row.customer_name` 是 `undefined`）。

- [ ] **Step 3: 改 `aigoClient.ts`**

`WeighingRow` interface 加兩欄：
```typescript
export interface WeighingRow {
  id: string; ticket_no: string; plate: string; weigh_operator: string;
  status: string; gross_weight: number | null; net_weight: number | null; at: string;
  customer_name: string; material_name: string;
}
```
`mapRecord` 回傳物件加兩欄（放在 `weigh_operator` 後）：
```typescript
    weigh_operator: d.weigh_operator || "",
    customer_name: d.customer_name || "",
    material_name: d.material_name || "",
```

- [ ] **Step 4: 跑測試確認通過**

Run: `cd aigo-app/vfs && npm test`
Expected: 全部 PASS。

- [ ] **Step 5: Commit**

```bash
git add aigo-app/vfs/src/aigoClient.ts aigo-app/vfs/src/aigoClient.test.ts
git commit -m "feat(frontend): WeighingRow/mapRecord 帶出 customer_name/material_name

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: 前端 App.tsx 加客戶/料種輸入與表格欄

**Files:**
- Modify: `aigo-app/vfs/src/App.tsx`

**Interfaces:**
- Consumes: `callAction("weigh", {...})`、`WeighingRow`（含 customer_name/material_name）。

- [ ] **Step 1: 加 state 與兩個 input，submit 帶入，表格加兩欄**

`App.tsx` 改為（完整檔，className 留待 Task 5，此步先用既有 inline 風格新增欄位）：
```tsx
// aigo-app/vfs/src/App.tsx
import { useEffect, useState } from "react";
import { callAction, listWeighings, WeighingRow } from "./aigoClient";

export default function App() {
  const [plate, setPlate] = useState("KEP-2758");
  const [weight, setWeight] = useState("14.54");
  const [operator, setOperator] = useState("王小明");
  const [customer, setCustomer] = useState("測試環保");
  const [material, setMaterial] = useState("一般事業廢棄物");
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState("");
  const [payload, setPayload] = useState<any>(null);
  const [rows, setRows] = useState<WeighingRow[]>([]);

  async function refresh() {
    try { setRows(await listWeighings()); }
    catch (e: any) { setMsg("讀取紀錄失敗: " + e.message); }
  }
  useEffect(() => { refresh(); }, []);

  async function submit() {
    setBusy(true); setMsg(""); setPayload(null);
    try {
      const r = await callAction("weigh", {
        plate, weight: parseFloat(weight), weigh_operator: operator,
        customer, material,
        plate_source: "manual", weight_source: "manual",
      });
      setPayload(r.print_payload);
      setMsg("成功: " + r.ticket_no + " (" + (r.event === "second" ? "二磅" : "一磅") + ")"
        + (r.needs_manual && r.needs_manual.length ? "  需補: " + r.needs_manual.join(",") : ""));
      await refresh();
    } catch (e: any) { setMsg("過磅失敗: " + e.message); }
    finally { setBusy(false); }
  }

  const cell: any = { border: "1px solid #ccc", padding: 6 };
  const inp: any = { width: "100%" };
  return (
    <div style={{ fontFamily: '"微軟正黑體", "Microsoft JhengHei", sans-serif', padding: 24, maxWidth: 860, margin: "0 auto" }}>
      <h2>薪榮地磅 — 驗證輸入</h2>
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 12 }}>
        <label>車號<input value={plate} onChange={e => setPlate(e.target.value)} style={inp} /></label>
        <label>重量(公噸)<input value={weight} onChange={e => setWeight(e.target.value)} style={inp} /></label>
        <label>會磅員<input value={operator} onChange={e => setOperator(e.target.value)} style={inp} /></label>
        <label>客戶名稱<input value={customer} onChange={e => setCustomer(e.target.value)} style={inp} /></label>
        <label>料種<input value={material} onChange={e => setMaterial(e.target.value)} style={inp} /></label>
      </div>
      <div style={{ marginTop: 12 }}>
        <button onClick={submit} disabled={busy} style={{ padding: "8px 18px" }}>{busy ? "處理中…" : "過磅"}</button>
        <span style={{ marginLeft: 12 }}>{msg}</span>
      </div>
      {payload && (
        <pre style={{ background: "#f4f6f8", padding: 12, marginTop: 12, whiteSpace: "pre-wrap" }}>
          {JSON.stringify(payload, null, 2)}
        </pre>
      )}
      <h3 style={{ marginTop: 24 }}>最近紀錄</h3>
      <table style={{ borderCollapse: "collapse", width: "100%" }}>
        <thead><tr>
          <th style={cell}>單號</th><th style={cell}>車號</th><th style={cell}>客戶</th><th style={cell}>料種</th>
          <th style={cell}>會磅員</th><th style={cell}>狀態</th><th style={cell}>毛重</th><th style={cell}>淨重</th><th style={cell}>時間</th>
        </tr></thead>
        <tbody>
          {rows.map(r => (
            <tr key={r.id}>
              <td style={cell}>{r.ticket_no}</td><td style={cell}>{r.plate}</td>
              <td style={cell}>{r.customer_name}</td><td style={cell}>{r.material_name}</td>
              <td style={cell}>{r.weigh_operator}</td><td style={cell}>{r.status}</td>
              <td style={cell}>{r.gross_weight ?? ""}</td><td style={cell}>{r.net_weight ?? ""}</td><td style={cell}>{r.at}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
```

- [ ] **Step 2: 型別檢查**

Run: `cd aigo-app/vfs && npm run typecheck`
Expected: 無錯誤。

- [ ] **Step 3: Commit**

```bash
git add aigo-app/vfs/src/App.tsx
git commit -m "feat(frontend): 表單加客戶名稱/料種欄並顯示於最近紀錄

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: CSS — App.css + main.tsx import + App.tsx className

**Files:**
- Create: `aigo-app/vfs/src/App.css`
- Modify: `aigo-app/vfs/src/main.tsx`、`aigo-app/vfs/src/App.tsx`

**Interfaces:**
- Consumes: 無新介面。App.tsx 改用 className 對應 App.css。

- [ ] **Step 1: 建 `aigo-app/vfs/src/App.css`**

```css
/* Shadow DOM 下 :host 生效；一般環境 :root 退回。參考 fde-sc1984 vfs/ordering。 */
:host, :root {
  font-family: "微軟正黑體", "Microsoft JhengHei", system-ui, sans-serif;
  color: #1a1a1a;
}
.wp-root { padding: 24px; max-width: 860px; margin: 0 auto; }
.wp-title { font-size: 20px; margin: 0 0 16px; }
.wp-grid { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 12px; }
.wp-field { display: flex; flex-direction: column; font-size: 14px; gap: 4px; }
.wp-field input { width: 100%; padding: 6px 8px; box-sizing: border-box; border: 1px solid #bbb; border-radius: 4px; }
.wp-actions { margin-top: 16px; display: flex; align-items: center; gap: 12px; }
.wp-btn { padding: 8px 18px; cursor: pointer; border: 1px solid #1769ff; background: #1769ff; color: #fff; border-radius: 6px; }
.wp-btn:hover:not(:disabled) { background: #0f55d6; }
.wp-btn:disabled { opacity: .5; cursor: default; }
.wp-msg { font-size: 14px; }
.wp-payload { background: #f4f6f8; padding: 12px; margin-top: 12px; white-space: pre-wrap; border-radius: 6px; }
.wp-subtitle { margin-top: 24px; font-size: 16px; }
.wp-table { border-collapse: collapse; width: 100%; font-size: 14px; }
.wp-table th, .wp-table td { border: 1px solid #ddd; padding: 6px 8px; text-align: left; }
.wp-table th { background: #fafafa; }
@media (max-width: 640px) { .wp-grid { grid-template-columns: 1fr; } }
```

- [ ] **Step 2: `main.tsx` import CSS**

在 `aigo-app/vfs/src/main.tsx` 頂部（其他 import 之後）加：
```ts
import "./App.css";
```

- [ ] **Step 3: `App.tsx` 改用 className**

把 Task 4 的 `App.tsx` 中的 inline style 換成 class（移除 `cell`/`inp` 物件與各 `style={...}`）：
- 外層 div：`<div className="wp-root">`
- `<h2 className="wp-title">`
- grid：`<div className="wp-grid">`，每個 `<label className="wp-field">`，input 去掉 `style`
- 按鈕列：`<div className="wp-actions">`，按鈕 `className="wp-btn"`，訊息 `<span className="wp-msg">`
- payload：`<pre className="wp-payload">`
- `<h3 className="wp-subtitle">`
- table：`<table className="wp-table">`，移除每個 `<th style={cell}>`/`<td style={cell}>` 的 style（保留文字內容與欄位）

- [ ] **Step 4: 型別檢查與前端測試**

Run: `cd aigo-app/vfs && npm run typecheck && npm test`
Expected: 型別無錯、vitest 全 PASS。

- [ ] **Step 5: Commit**

```bash
git add aigo-app/vfs/src/App.css aigo-app/vfs/src/main.tsx aigo-app/vfs/src/App.tsx
git commit -m "feat(frontend): 改用 App.css(:host,:root) 取代 inline style（Shadow DOM 相容）

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: 部署並以 playwright 端到端驗證

**Files:** 無（部署 + 線上驗證）

- [ ] **Step 1: 部署前端與 action 到 aigo**

Run: `cd /home/username/桌面/fde-czone && set -a && source .env && set +a && python3 aigo-app/scripts/deploy.py`
Expected: action source 上傳成功；前端 source 上傳（compile/publish 為 best-effort，失敗僅警告）。

- [ ] **Step 2: playwright 開頁面，填表送出，驗 payload**

開 `https://ai-go.app/runtime/7280f9ec3093`（需登入，session 過期則請使用者登入），用 `browser_evaluate` 直接呼叫 weigh action 驗證端到端：
```js
async () => {
  const base = window.__API_BASE__ || '/api/v1';
  const appId = window.__APP_ID__;
  const h = {'Authorization':'Bearer '+(window.__APP_TOKEN__||''),'Content-Type':'application/json'};
  const r = await fetch(base+'/actions/apps/'+appId+'/run/weigh', {
    method:'POST', headers:h, credentials:'include',
    body: JSON.stringify({ params: { plate:'TEST-0001', weight:20.5, weigh_operator:'測試員',
      customer:'驗證客戶', material:'驗證料種', plate_source:'manual', weight_source:'manual' } })
  });
  const env = await r.json();
  const pp = (env.result||{}).print_payload || {};
  return { status:r.status, SR_Customer: pp.SR_Customer, SR_Material: pp.SR_Material };
}
```
Expected: `SR_Customer === "驗證客戶"`、`SR_Material === "驗證料種"`。

- [ ] **Step 3: playwright 驗 CSS 在 Shadow DOM 生效**

`browser_navigate` 到 runtime 頁後 `browser_evaluate`：
```js
() => {
  const r = window.__CUSTOM_APP_ROOT__;
  const root = r.getRootNode();
  const styleCount = root.querySelectorAll ? root.querySelectorAll('style').length : 0;
  const btn = root.querySelector ? root.querySelector('.wp-btn') : null;
  const bg = btn ? getComputedStyle(btn).backgroundColor : null;
  return { stylesInShadow: styleCount, btnFound: !!btn, btnBg: bg };
}
```
Expected: `stylesInShadow > 0`、`btnFound: true`、`btnBg` 為藍色（`rgb(23, 105, 255)` 類）→ 證明 App.css 進了 shadow 且 class 生效。

- [ ] **Step 4: 記錄驗證結果**

把 Step 2、3 的實際輸出貼回，確認與 Expected 相符。若 `stylesInShadow === 0`（CSS 沒進 shadow），改用備案：於 `main.tsx` 掛載時把 CSS 字串以 `createElement('style')` 注入 `rootEl.getRootNode()`，重跑 Step 3。
