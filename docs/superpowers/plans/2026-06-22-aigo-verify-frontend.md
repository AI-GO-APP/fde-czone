# aigo 驗證前端 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 aigo custom app 上做一個最小驗證前端:輸入車號+重量+操作員 → 呼叫 `weigh` action 寫進 `x_czone_weighing` → 顯示回應並列出最近紀錄。

**Architecture:** React app(`aigo-app/vfs/src/`),用平台注入的 `window.__APP_TOKEN__/__API_BASE__/__APP_ID__/__IS_EXTERNAL__` 以 `fetch` 直接打 aigo REST(模式 A)。寫入一律經 `weigh` action。由 `scripts/deploy.py` 上傳 VFS → 平台 compile → publish。

**Tech Stack:** TypeScript + React 18;測試 vitest + tsc(本機 node v24.17.0,以 `npm.cmd`/`npx.cmd` 執行);部署用既有 `deploy.py`;端到端用既有 `agent/lib/AigoClient.ps1`(PowerShell)。

## Global Constraints

- 機制模式 A:`window.__APP_TOKEN__`(Bearer)、`window.__API_BASE__`(預設 `/api/v1`)、`window.__APP_ID__`、`window.__IS_EXTERNAL__`;`fetch` 帶 `Authorization: Bearer` 與 `credentials:'include'`。
- **不嵌 admin 金鑰;不連 localhost**(平台 CSP 會擋;本地列印另由 agent server-to-server 拉)。
- 純 React 18(executime 不加 runtime 套件;測試用 devDependencies)。
- 寫入 `x_czone_weighing` **一律經 `weigh` action**,不直接 `POST .../records`。
- weigh 參數:`plate`、`weight`(公噸,數字)、`weigh_operator`、`plate_source:'manual'`、`weight_source:'manual'`。
- action 端點(內部 app):`POST {API_BASE}/actions/apps/{APP_ID}/run/{name}`,body `{params}`,回信封 `{status,result,error}`。
- 紀錄查詢:`GET {API_BASE}/data/objects/{id}/records` → `[{id, data:{...}}]`;`id` 由 `GET {API_BASE}/data/objects` 以 `api_slug` 找。
- 檔案 UTF-8。
- **node 工具鏈**:本機 node 在 `C:\Users\user\tools\node-v24.17.0-win-x64\`;PowerShell 用 `npm.cmd` / `npx.cmd`(`npm.ps1` 被 Restricted 執行原則擋)。`node_modules/` 不入 repo。
- **測試策略**:純邏輯(URL 組合、信封解封、紀錄對應)用 vitest 單元測試 + `tsc --noEmit` 型別檢查(本機可跑);UI 行為(平台 compile 後)用「部署 + 瀏覽器操作 + PowerShell 整合查核(確認同一 `ticket_no` 進 DB)」驗證。

---

### Task 1: 前端測試工具與專案設定

**Files:**
- Modify: `aigo-app/vfs/package.json`(加 vitest 與 scripts)
- Create: `aigo-app/vfs/tsconfig.json`
- Modify: `.gitignore`(加 `node_modules/`)

**Interfaces:**
- Produces:可執行 `npm.cmd run test`(vitest)、`npm.cmd run typecheck`(tsc)。

- [ ] **Step 1: 改寫 `aigo-app/vfs/package.json`**

```json
{
  "name": "xinrong-weighbridge",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "test": "vitest run",
    "typecheck": "tsc --noEmit"
  },
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0"
  },
  "devDependencies": {
    "@types/react": "^18.2.0",
    "@types/react-dom": "^18.2.0",
    "typescript": "^5.0.0",
    "vitest": "^2.1.0"
  }
}
```

- [ ] **Step 2: 建立 `aigo-app/vfs/tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "jsx": "react-jsx",
    "strict": true,
    "skipLibCheck": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"]
  },
  "include": ["src"]
}
```

- [ ] **Step 3: `.gitignore` 加一行 `node_modules/`**

於 `/c/Users/user/Desktop/fde-czone/.gitignore` 的「Python」區塊前或後加:
```
# Node
node_modules/
```

- [ ] **Step 4: 安裝相依**

Run:
```bash
cd "/c/Users/user/Desktop/fde-czone/aigo-app/vfs"
"C:/Users/user/tools/node-v24.17.0-win-x64/npm.cmd" install
```
Expected:`node_modules/` 產生,結尾顯示 `added N packages`,無 error。

- [ ] **Step 5: Commit**

```bash
cd /c/Users/user/Desktop/fde-czone
git add aigo-app/vfs/package.json aigo-app/vfs/tsconfig.json .gitignore
git -c user.email='philosophysis@gmail.com' -c user.name='philosophysis' commit -m "chore(aigo-fe): vitest + tsconfig 測試設定"
```

---

### Task 2: aigoClient.ts(後端溝通薄層,含單元測試)

**Files:**
- Create: `aigo-app/vfs/src/aigoClient.ts`
- Create: `aigo-app/vfs/src/aigoClient.test.ts`

**Interfaces:**
- Produces:
  - `buildActionUrl(name: string): string`
  - `unwrapEnvelope(env: any): any`
  - `mapRecord(raw: any): WeighingRow`
  - `callAction(name: string, params?: Record<string, any>): Promise<any>`
  - `getObjectId(slug: string): Promise<string>`
  - `listWeighings(): Promise<WeighingRow[]>`
  - `interface WeighingRow { id; ticket_no; plate; weigh_operator; status; gross_weight; net_weight; at }`

- [ ] **Step 1: 寫失敗測試 `aigo-app/vfs/src/aigoClient.test.ts`**

```ts
import { describe, it, expect, beforeEach } from "vitest";
import { buildActionUrl, unwrapEnvelope, mapRecord } from "./aigoClient";

beforeEach(() => {
  (globalThis as any).window = { __API_BASE__: "/api/v1", __APP_ID__: "APP1", __IS_EXTERNAL__: false };
});

describe("buildActionUrl", () => {
  it("內部 app", () => {
    expect(buildActionUrl("weigh")).toBe("/api/v1/actions/apps/APP1/run/weigh");
  });
  it("外部 app", () => {
    (globalThis as any).window.__IS_EXTERNAL__ = true;
    expect(buildActionUrl("weigh")).toBe("/api/v1/ext/actions/run/weigh");
  });
});

describe("unwrapEnvelope", () => {
  it("成功回 result", () => {
    expect(unwrapEnvelope({ status: "success", result: { a: 1 } })).toEqual({ a: 1 });
  });
  it("失敗丟錯", () => {
    expect(() => unwrapEnvelope({ status: "error", error: "壞了" })).toThrow("壞了");
  });
  it("無信封原樣回", () => {
    expect(unwrapEnvelope({ a: 1 })).toEqual({ a: 1 });
  });
});

describe("mapRecord", () => {
  it("二磅時間優先, null 處理", () => {
    const row = mapRecord({ id: "r1", data: {
      ticket_no: "20260622-002", plate: "KEP-2758", weigh_operator: "王小明",
      status: "done", gross_weight: 14.54, net_weight: 6.34,
      first_weigh_at: "2026-06-22T04:00:00", second_weigh_at: "2026-06-22T05:00:00" } });
    expect(row).toEqual({
      id: "r1", ticket_no: "20260622-002", plate: "KEP-2758", weigh_operator: "王小明",
      status: "done", gross_weight: 14.54, net_weight: 6.34, at: "2026-06-22T05:00:00" });
  });
  it("一磅時 fallback first, 缺值補空/null", () => {
    const row = mapRecord({ id: "r2", data: { ticket_no: "20260622-003", plate: "ABC", first_weigh_at: "2026-06-22T06:00:00" } });
    expect(row.at).toBe("2026-06-22T06:00:00");
    expect(row.weigh_operator).toBe("");
    expect(row.net_weight).toBeNull();
  });
});
```

- [ ] **Step 2: 跑測試確認失敗**

Run:
```bash
cd "/c/Users/user/Desktop/fde-czone/aigo-app/vfs"
"C:/Users/user/tools/node-v24.17.0-win-x64/npx.cmd" vitest run
```
Expected:FAIL(`aigoClient` 模組或匯出不存在)。

- [ ] **Step 3: 寫實作 `aigo-app/vfs/src/aigoClient.ts`**

```ts
// aigo-app/vfs/src/aigoClient.ts
// 與 aigo 平台後端溝通的薄層 (模式 A): 平台注入的 window 全域 + fetch。

function apiBase(): string { return (window as any).__API_BASE__ || "/api/v1"; }
function appId(): string { return (window as any).__APP_ID__ || ""; }
function headers(): Record<string, string> {
  const h: Record<string, string> = { "Content-Type": "application/json" };
  const t = (window as any).__APP_TOKEN__ || "";
  if (t) h["Authorization"] = "Bearer " + t;
  return h;
}

// 內部 app: /actions/apps/{app_id}/run/{name} (此 app 後端已實測可用)
// 外部 app: /ext/actions/run/{name}
export function buildActionUrl(name: string): string {
  const isExternal = !!(window as any).__IS_EXTERNAL__;
  return isExternal
    ? apiBase() + "/ext/actions/run/" + name
    : apiBase() + "/actions/apps/" + appId() + "/run/" + name;
}

// action 回信封 {status, result, error}: 成功回 result, 否則丟錯。
export function unwrapEnvelope(env: any): any {
  if (env && env.status && env.status !== "success") {
    throw new Error(env.error || "action 失敗");
  }
  return env && Object.prototype.hasOwnProperty.call(env, "result") ? env.result : env;
}

export async function callAction(name: string, params: Record<string, any> = {}): Promise<any> {
  const resp = await fetch(buildActionUrl(name), {
    method: "POST", headers: headers(), credentials: "include",
    body: JSON.stringify({ params }),
  });
  if (!resp.ok) throw new Error("HTTP " + resp.status);
  return unwrapEnvelope(await resp.json());
}

const _idCache: Record<string, string> = {};
export async function getObjectId(slug: string): Promise<string> {
  if (_idCache[slug]) return _idCache[slug];
  const resp = await fetch(apiBase() + "/data/objects", { headers: headers(), credentials: "include" });
  if (!resp.ok) throw new Error("HTTP " + resp.status);
  const objs = await resp.json();
  const list = Array.isArray(objs) ? objs : [];
  for (const o of list) { if (o.api_slug === slug) { _idCache[slug] = o.id; return o.id; } }
  throw new Error("找不到資料表 " + slug);
}

export interface WeighingRow {
  id: string; ticket_no: string; plate: string; weigh_operator: string;
  status: string; gross_weight: number | null; net_weight: number | null; at: string;
}

export function mapRecord(raw: any): WeighingRow {
  const d = (raw && raw.data) || {};
  return {
    id: raw ? raw.id : "",
    ticket_no: d.ticket_no || "",
    plate: d.plate || "",
    weigh_operator: d.weigh_operator || "",
    status: d.status || "",
    gross_weight: d.gross_weight === undefined ? null : d.gross_weight,
    net_weight: d.net_weight === undefined ? null : d.net_weight,
    at: d.second_weigh_at || d.first_weigh_at || "",
  };
}

export async function listWeighings(): Promise<WeighingRow[]> {
  const oid = await getObjectId("x_czone_weighing");
  const resp = await fetch(apiBase() + "/data/objects/" + oid + "/records", { headers: headers(), credentials: "include" });
  if (!resp.ok) throw new Error("HTTP " + resp.status);
  const rows = await resp.json();
  const arr = Array.isArray(rows) ? rows : [];
  const out = arr.map(mapRecord);
  out.sort((a, b) => (b.at || "").localeCompare(a.at || "")); // 新到舊
  return out;
}
```

- [ ] **Step 4: 跑測試確認通過 + 型別檢查**

Run:
```bash
cd "/c/Users/user/Desktop/fde-czone/aigo-app/vfs"
"C:/Users/user/tools/node-v24.17.0-win-x64/npx.cmd" vitest run
"C:/Users/user/tools/node-v24.17.0-win-x64/npx.cmd" tsc --noEmit
```
Expected:vitest 全 PASS;tsc 無錯誤輸出。

- [ ] **Step 5: Commit**

```bash
cd /c/Users/user/Desktop/fde-czone
git add aigo-app/vfs/src/aigoClient.ts aigo-app/vfs/src/aigoClient.test.ts
git -c user.email='philosophysis@gmail.com' -c user.name='philosophysis' commit -m "feat(aigo-fe): aigoClient 薄層 + 單元測試"
```

---

### Task 3: App.tsx(驗證畫面:表單 + 最近紀錄)

**Files:**
- Modify: `aigo-app/vfs/src/App.tsx`(目前為 placeholder,整檔替換)

**Interfaces:**
- Consumes(Task 2):`callAction`、`listWeighings`、`WeighingRow`。

- [ ] **Step 1: 整檔替換為以下內容**

```tsx
// aigo-app/vfs/src/App.tsx
import { useEffect, useState } from "react";
import { callAction, listWeighings, WeighingRow } from "./aigoClient";

export default function App() {
  const [plate, setPlate] = useState("KEP-2758");
  const [weight, setWeight] = useState("14.54");
  const [operator, setOperator] = useState("王小明");
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
  return (
    <div style={{ fontFamily: '"微軟正黑體", "Microsoft JhengHei", sans-serif', padding: 24, maxWidth: 860, margin: "0 auto" }}>
      <h2>薪榮地磅 — 驗證輸入</h2>
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 12 }}>
        <label>車號<input value={plate} onChange={e => setPlate(e.target.value)} style={{ width: "100%" }} /></label>
        <label>重量(公噸)<input value={weight} onChange={e => setWeight(e.target.value)} style={{ width: "100%" }} /></label>
        <label>操作員<input value={operator} onChange={e => setOperator(e.target.value)} style={{ width: "100%" }} /></label>
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
          <th style={cell}>單號</th><th style={cell}>車號</th><th style={cell}>操作員</th>
          <th style={cell}>狀態</th><th style={cell}>毛重</th><th style={cell}>淨重</th><th style={cell}>時間</th>
        </tr></thead>
        <tbody>
          {rows.map(r => (
            <tr key={r.id}>
              <td style={cell}>{r.ticket_no}</td><td style={cell}>{r.plate}</td><td style={cell}>{r.weigh_operator}</td>
              <td style={cell}>{r.status}</td><td style={cell}>{r.gross_weight ?? ""}</td>
              <td style={cell}>{r.net_weight ?? ""}</td><td style={cell}>{r.at}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
```

- [ ] **Step 2: 型別檢查**

Run:
```bash
cd "/c/Users/user/Desktop/fde-czone/aigo-app/vfs"
"C:/Users/user/tools/node-v24.17.0-win-x64/npx.cmd" tsc --noEmit
```
Expected:無錯誤(import 對得上 Task 2 的匯出)。

- [ ] **Step 3: Commit**

```bash
cd /c/Users/user/Desktop/fde-czone
git add aigo-app/vfs/src/App.tsx
git -c user.email='philosophysis@gmail.com' -c user.name='philosophysis' commit -m "feat(aigo-fe): 驗證畫面 表單+最近紀錄"
```

---

### Task 4: 部署、首次發布、端到端驗證

**Files:**
- Use: `aigo-app/scripts/deploy.py`、`aigo-app/vfs/scripts/refs.py`(既有)
- Possibly Create: `aigo-app/vfs/index.html`(僅在首次 compile 失敗且確認缺入口時)

**Interfaces:**
- Consumes:Task 2+3 的 `aigo-app/vfs/src/*`(由 deploy.py 上傳)。

- [ ] **Step 1: 部署(上傳 VFS → compile → publish)**

Run:
```bash
cd /c/Users/user/Desktop/fde-czone
set -a && source .env && set +a && python3 aigo-app/scripts/deploy.py
```
Expected:`上傳: 200`;理想為「編譯:成功」+「發布: 200」。若印「⚠️ 跳過前端 compile/publish(尚無已發布版)」→ 進 Step 2。

- [ ] **Step 2: 首次 compile/publish(僅當 Step 1 出現尚無已發布版/404 時)**

依 PLATFORM_NOTES.md §6,全新 app 首發前 compile 會 404。處理:
1. 確認入口:`src/main.tsx` 已掛 `#root`。若平台需要 `index.html` 而 vfs 無,建立:
```html
<!-- aigo-app/vfs/index.html -->
<!DOCTYPE html>
<html lang="zh-Hant"><head><meta charset="utf-8"><title>薪榮地磅</title></head>
<body><div id="root"></div><script type="module" src="/src/main.tsx"></script></body></html>
```
2. 重跑 Step 1。
3. 仍失敗則把平台回傳的 `detail`/`error` 記到 PLATFORM_NOTES.md,並用平台 UI 手動首發一次(之後 deploy.py 即可)。

- [ ] **Step 3: 瀏覽器操作驗證**

開此 app 前端 URL,表單預設(KEP-2758 / 14.54 / 王小明)按「過磅」。
Expected:顯示「成功: YYYYMMDD-NNN (一磅/二磅)」,`print_payload` JSON 顯示 `company=薪榮環保股份有限公司`、`SR_User=王小明`(中文正確),「最近紀錄」新增該筆。

- [ ] **Step 4: PowerShell 整合查核(確認同一筆進 DB)**

Run(`<TICKET>` 換成 Step 3 顯示的單號):
```bash
powershell.exe -NoProfile -Command "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; . ([ScriptBlock]::Create((Get-Content -Raw -Encoding UTF8 -LiteralPath 'C:\Users\user\Desktop\fde-czone\agent\lib\AigoClient.ps1'))); \$cfg=Get-Content 'C:\Users\user\Desktop\fde-czone\agent\config.local.json' -Raw -Encoding UTF8|ConvertFrom-Json; Resolve-AigoWeighings \$cfg | ForEach-Object { '{0}  {1}  {2}' -f \$_.data.ticket_no, \$_.data.plate, \$_.data.weigh_operator }"
```
Expected:清單含 `<TICKET>`、`KEP-2758`、`王小明`(操作員中文正確)→ 前端→action→DB→本地撈取整條一致。

- [ ] **Step 5: Commit(若 Step 2 有新增檔/更新筆記)**

```bash
cd /c/Users/user/Desktop/fde-czone
git add aigo-app/vfs/index.html aigo-app/PLATFORM_NOTES.md
git -c user.email='philosophysis@gmail.com' -c user.name='philosophysis' commit -m "chore(aigo-fe): 首次發布前端 + 驗證筆記"
```
(若 Step 2 未新增任何檔,跳過。)

---

## 完成後

Task 4 Step 3+4 同時通過 = **aigo 前端輸入 → weigh → x_czone_weighing → 本地撈取** 整條打通。
範圍外(另案):本地列印畫面、時區(UTC→+8)、公噸↔KG、customer/material id→名稱、真實資料來源取代驗證表單。
```
