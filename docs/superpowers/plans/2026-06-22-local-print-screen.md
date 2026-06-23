# 本地列印畫面 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 本地 agent 提供畫面:列出 aigo `x_czone_weighing` 最近 50 筆 → 選一筆 → 預覽 PDF 或直接列印三聯磅單。

**Architecture:** 擴充現有 `agent/`(PowerShell 5.1 HttpListener + 既有 PrintEngine GDI + AigoClient)。對 aigo 唯讀。前端網頁列表→選→呼叫本地端點→GDI 列印。

**Tech Stack:** Windows PowerShell 5.1、System.Net.HttpListener、既有 WeighTicketPrint GDI 引擎;前端純 HTML/JS(無框架)。

## Global Constraints

- 平台:Windows PowerShell 5.1,系統編碼 cp950(Big5),執行原則 Restricted。
- 執行 .ps1:用 scriptblock 包裝 `& ([ScriptBlock]::Create((Get-Content -Raw -Encoding UTF8 '<file>')))`(或 `agent/start.cmd`);**勿用 `-ExecutionPolicy Bypass`、勿改系統執行原則**。
- 檔案一律 UTF-8(.ps1 建議含 BOM;`index.html` UTF-8)。中文檔內容用 Write 工具寫,之後若要可加 BOM。
- agent 對 aigo **唯讀**(只 `GET` 撈,不回寫);憑證在 `agent/config.local.json`(gitignore,已存在)。
- 列印:`EPSON LQ-690CII`,走既有 `Invoke-TicketPrint`(GDI + 硬體邊界補償 + 薪榮版面校正)。
- 對應修正:`customer_name`→`SR_Customer`、`material_name`→`SR_Material`;重量 float(如 `14540.0`)→整數 `14540`(套版面後 `14540 KG`)。
- 列表:最近 **50** 筆,依時間(second 優先否則 first)**新到舊**。
- 重用既有函式:`Resolve-AigoWeighings $cfg`(回 `[{id, data:{...}}]`)、`Get-TicketLayout`、`ConvertFrom-WeighingData`、`Export-TicketPdf`、`Invoke-TicketPrint`、`ConvertTo-FieldValue`、`ConvertTo-TicketData`。
- 分支:`feat/local-print-screen`。git commit 用 `git -c user.email='philosophysis@gmail.com' -c user.name='philosophysis' commit`。

---

### Task 1: PrintEngine 對應修正(customer_name/material_name + 重量整數化)+ 單元測試

**Files:**
- Modify: `agent/lib/PrintEngine.ps1`(`ConvertFrom-WeighingData` 改用 name;`ConvertTo-FieldValue` 重量改 double→int)
- Create: `agent/tests/Run-Tests.ps1`

**Interfaces:**
- Produces:`ConvertFrom-WeighingData($Data)` → `Dictionary[string,object]`,其中 `SR_Customer=customer_name`、`SR_Material=material_name`、`SR_GrossWeight/SR_EmptyWeight/SR_NetWeight` 為整數。

- [ ] **Step 1: 建立失敗測試 `agent/tests/Run-Tests.ps1`**

```powershell
# agent/tests/Run-Tests.ps1 — PrintEngine 純邏輯測試 (零安裝)
param([string]$AgentDir)
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
if (-not $AgentDir) {
    if ($PSScriptRoot) { $AgentDir = Split-Path -Parent $PSScriptRoot }
    else { $AgentDir = "C:\Users\user\Desktop\fde-czone\agent" }
}
. ([ScriptBlock]::Create((Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $AgentDir "lib\PrintEngine.ps1"))))

$script:pass = 0; $script:fail = 0
function Assert-Equal($expected, $actual, $msg) {
    if ([string]$expected -ceq [string]$actual) { Write-Host "  PASS  $msg" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "  FAIL  $msg | expected=[$expected] actual=[$actual]" -ForegroundColor Red; $script:fail++ }
}

# 模擬 aigo x_czone_weighing 紀錄的 .data
$data = [pscustomobject]@{
    ticket_no = "20260622-001"; plate = "KEP-2758"
    customer_name = "測試環保"; material_name = "一般事業廢棄物"
    weigh_operator = "王小明"
    gross_weight = 14540.0; tare_weight = 10540.0; net_weight = 4000.0
    first_weigh_at = "2026-06-22T17:38:00"; second_weigh_at = "2026-06-22T17:38:20"
}
$d = ConvertFrom-WeighingData $data

Write-Host "[1] ConvertFrom-WeighingData 對應" -ForegroundColor Cyan
Assert-Equal "測試環保"        $d["SR_Customer"] "customer_name -> SR_Customer"
Assert-Equal "一般事業廢棄物"  $d["SR_Material"] "material_name -> SR_Material"
Assert-Equal "KEP-2758"        $d["SR_CarNo"]    "plate -> SR_CarNo"
Assert-Equal "20260622-001"    $d["SR_SN"]       "ticket_no -> SR_SN"
Assert-Equal "王小明"          $d["SR_User"]     "weigh_operator -> SR_User"

Write-Host "[2] 重量整數化" -ForegroundColor Cyan
Assert-Equal "14540" $d["SR_GrossWeight"] "gross 14540.0 -> 14540"
Assert-Equal "10540" $d["SR_EmptyWeight"] "tare 10540.0 -> 10540"
Assert-Equal "4000"  $d["SR_NetWeight"]   "net 4000.0 -> 4000"
if ($d["SR_GrossWeight"] -is [int]) { Write-Host "  PASS  SR_GrossWeight 型別為 int" -ForegroundColor Green; $script:pass++ }
else { Write-Host "  FAIL  SR_GrossWeight 型別非 int (是 $($d['SR_GrossWeight'].GetType().Name))" -ForegroundColor Red; $script:fail++ }

Write-Host "[3] 日期取二磅優先" -ForegroundColor Cyan
if ($d["SR_DatetimeG"] -is [datetime] -and $d["SR_DatetimeG"] -eq [datetime]"2026-06-22T17:38:20") {
    Write-Host "  PASS  second_weigh_at 優先" -ForegroundColor Green; $script:pass++
} else { Write-Host "  FAIL  日期未取 second_weigh_at" -ForegroundColor Red; $script:fail++ }

Write-Host "[4] ConvertTo-FieldValue 重量 float" -ForegroundColor Cyan
Assert-Equal "14540" (ConvertTo-FieldValue "SR_GrossWeight" "14540.0") "ConvertTo-FieldValue 14540.0 -> 14540"

Write-Host ""
Write-Host "結果: PASS=$script:pass FAIL=$script:fail" -ForegroundColor (@{$true="Green";$false="Red"}[$script:fail -eq 0])
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
```

- [ ] **Step 2: 跑測試確認失敗**

Run:
```bash
powershell.exe -NoProfile -Command "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; & ([ScriptBlock]::Create((Get-Content -Raw -Encoding UTF8 -LiteralPath 'C:\Users\user\Desktop\fde-czone\agent\tests\Run-Tests.ps1')))"
```
Expected:FAIL(目前 `ConvertFrom-WeighingData` 用 `customer_id`/`material_id`→SR_Customer/SR_Material 為空;重量 `14540.0` 經 `[int]::TryParse` 失敗→字串 `"14540.0"`)。

- [ ] **Step 3: 修 `ConvertFrom-WeighingData`(改用 name)**

把 `agent/lib/PrintEngine.ps1` 中這兩行:
```powershell
        material = $Data.material_id
        customer = $Data.customer_id
```
改為:
```powershell
        material = $Data.material_name
        customer = $Data.customer_name
```

- [ ] **Step 4: 修 `ConvertTo-FieldValue`(重量 double→int)**

把 `agent/lib/PrintEngine.ps1` 中 `switch ($Binding)` 的三個重量分支:
```powershell
        'SR_GrossWeight' { $n = 0; if ([int]::TryParse($s, [ref]$n)) { return [int]$n }; return $s }
        'SR_EmptyWeight' { $n = 0; if ([int]::TryParse($s, [ref]$n)) { return [int]$n }; return $s }
        'SR_NetWeight'   { $n = 0; if ([int]::TryParse($s, [ref]$n)) { return [int]$n }; return $s }
```
改為(先 double 再四捨五入成 int,才能吃 `14540.0`):
```powershell
        'SR_GrossWeight' { $g = 0.0; if ([double]::TryParse($s, [ref]$g)) { return [int][math]::Round($g) }; return $s }
        'SR_EmptyWeight' { $g = 0.0; if ([double]::TryParse($s, [ref]$g)) { return [int][math]::Round($g) }; return $s }
        'SR_NetWeight'   { $g = 0.0; if ([double]::TryParse($s, [ref]$g)) { return [int][math]::Round($g) }; return $s }
```
並把 `ConvertFrom-WeighingData` 上方註解「customer_id / material_id ... 之後需 join」更新為「使用 customer_name / material_name 文字欄」。

- [ ] **Step 5: 跑測試確認通過**

Run:
```bash
powershell.exe -NoProfile -Command "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; & ([ScriptBlock]::Create((Get-Content -Raw -Encoding UTF8 -LiteralPath 'C:\Users\user\Desktop\fde-czone\agent\tests\Run-Tests.ps1')))"
```
Expected:`結果: PASS=11 FAIL=0`(全綠)。

- [ ] **Step 6: Commit**

```bash
cd /c/Users/user/Desktop/fde-czone
git add agent/lib/PrintEngine.ps1 agent/tests/Run-Tests.ps1
git -c user.email='philosophysis@gmail.com' -c user.name='philosophysis' commit -m "feat(agent): 列印對應改用 customer_name/material_name + 重量整數化 + 單元測試"
```

---

### Task 2: Start-Agent.ps1 端點(GET /records + POST /print-record;移除手動 /print、/weigh)

**Files:**
- Modify: `agent/Start-Agent.ps1`(路由區塊)

**Interfaces:**
- Consumes:`Resolve-AigoWeighings $cfg`、`ConvertFrom-WeighingData`、`Export-TicketPdf`、`Invoke-TicketPrint`、`$layout`、`$Printer`、`$Font`、`$OutDir`、`Write-Json`、`Read-Body`、`Write-Bytes`(皆已存在於 Start-Agent.ps1)。
- Produces:`GET /records` → `{ok:true, records:[{id,ticket_no,plate,customer_name,material_name,weigh_operator,gross_weight,net_weight,status,at}]}`;`POST /print-record {id,mode}` → `{ok,mode,pdfUrl|printer,...}`。

- [ ] **Step 1: 替換路由中的 `/print` 與 `/weigh` 兩個 elseif 區塊**

在 `agent/Start-Agent.ps1` 中,刪除這兩段(現有的手動 `/print` 與 stub `/weigh`):
```powershell
        elseif ($method -eq 'POST' -and $path -eq '/print') {
            # body: { ...欄位..., mode: 'pdf'|'print' }  (mode 預設 pdf, 省紙)
            $body = Read-Body $req | ConvertFrom-Json
            $mode = if ($body.mode) { [string]$body.mode } else { 'pdf' }
            $data = ConvertTo-TicketData $body
            if ($mode -eq 'print') {
                Invoke-TicketPrint $layout $data $Printer $Font
                Write-Json $resp @{ ok = $true; mode = 'print'; printer = $Printer } 200
            } else {
                $pdf = Export-TicketPdf $layout $data (Join-Path $OutDir 'preview.pdf') $Font
                Write-Json $resp @{ ok = $true; mode = 'pdf'; pdfUrl = "/preview.pdf?t=$([guid]::NewGuid().ToString('N'))" } 200
            }
        }
        elseif ($method -eq 'POST' -and $path -eq '/weigh') {
            # 階段二: 呼叫 aigo 取得 print_payload。階段一先停用以免誤打雲端。
            Write-Json $resp @{ ok = $false; reason = 'weigh(接 aigo) 為階段二功能, 尚未啟用' } 501
        }
```
換成以下兩段:
```powershell
        elseif ($method -eq 'GET' -and $path -eq '/records') {
            # 撈 aigo 最近 50 筆 (新到舊) 供列表
            $rows = Resolve-AigoWeighings $cfg
            $list = @($rows) | ForEach-Object {
                $d = $_.data
                [pscustomobject]@{
                    id             = $_.id
                    ticket_no      = $d.ticket_no
                    plate          = $d.plate
                    customer_name  = $d.customer_name
                    material_name  = $d.material_name
                    weigh_operator = $d.weigh_operator
                    gross_weight   = $d.gross_weight
                    net_weight     = $d.net_weight
                    status         = $d.status
                    at             = if ($d.second_weigh_at) { $d.second_weigh_at } else { $d.first_weigh_at }
                }
            } | Sort-Object at -Descending | Select-Object -First 50
            Write-Json $resp @{ ok = $true; records = @($list) } 200
        }
        elseif ($method -eq 'POST' -and $path -eq '/print-record') {
            # body: { id, mode: 'pdf'|'print' } — 依 id 撈該筆 aigo 紀錄 -> 預覽/列印
            $body = Read-Body $req | ConvertFrom-Json
            $id = [string]$body.id
            $mode = if ($body.mode) { [string]$body.mode } else { 'pdf' }
            $rows = Resolve-AigoWeighings $cfg
            $rec = @($rows) | Where-Object { $_.id -eq $id } | Select-Object -First 1
            if (-not $rec) {
                Write-Json $resp @{ ok = $false; reason = "找不到紀錄 id=$id" } 404
            } else {
                $data = ConvertFrom-WeighingData $rec.data
                if ($mode -eq 'print') {
                    Invoke-TicketPrint $layout $data $Printer $Font
                    Write-Json $resp @{ ok = $true; mode = 'print'; printer = $Printer; ticket_no = $rec.data.ticket_no } 200
                } else {
                    Export-TicketPdf $layout $data (Join-Path $OutDir 'preview.pdf') $Font | Out-Null
                    Write-Json $resp @{ ok = $true; mode = 'pdf'; pdfUrl = "/preview.pdf?t=$([guid]::NewGuid().ToString('N'))" } 200
                }
            }
        }
```
同時把檔頭註解第 2 行「階段一: 手動輸入 -> /print ...」更新為「列出 aigo 紀錄 -> 選 -> 預覽/列印」。

- [ ] **Step 2: 整合驗證 — 啟動 agent 並打端點**

背景啟動 agent:
```bash
powershell.exe -NoProfile -Command "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; \$env:AGENT_DIR='C:\Users\user\Desktop\fde-czone\agent'; & ([ScriptBlock]::Create((Get-Content -Raw -Encoding UTF8 -LiteralPath 'C:\Users\user\Desktop\fde-czone\agent\Start-Agent.ps1')))"
```
(用 Bash 的 run_in_background 啟動;看到「現場 agent 已啟動」後)另開一次呼叫:
```bash
powershell.exe -NoProfile -Command "(Invoke-WebRequest -UseBasicParsing http://localhost:9180/records).Content | Out-Host"
```
Expected:JSON `{"ok":true,"records":[...]}`,至少含一筆(例 ticket_no `20260622-001`、customer_name `測試環保`)。
再測預覽(不印真紙):
```bash
powershell.exe -NoProfile -Command "\$id=((Invoke-RestMethod http://localhost:9180/records).records[0].id); (Invoke-WebRequest -UseBasicParsing -Method Post -Uri http://localhost:9180/print-record -Body (@{id=\$id;mode='pdf'}|ConvertTo-Json) -ContentType 'application/json').Content | Out-Host"
```
Expected:`{"ok":true,"mode":"pdf","pdfUrl":"/preview.pdf?t=..."}`,且 `agent/out/preview.pdf` 已產生。
驗證後停止背景 agent(結束該背景工作)。

- [ ] **Step 3: Commit**

```bash
cd /c/Users/user/Desktop/fde-czone
git add agent/Start-Agent.ps1
git -c user.email='philosophysis@gmail.com' -c user.name='philosophysis' commit -m "feat(agent): 加 GET /records 與 POST /print-record, 移除手動 /print 與 /weigh stub"
```

---

### Task 3: index.html 改寫(列表 → 選 → 預覽/列印)

**Files:**
- Modify: `agent/web/index.html`(整檔替換)

**Interfaces:**
- Consumes:`GET /records`、`POST /print-record`、`GET /preview.pdf`(Task 2)。

- [ ] **Step 1: 整檔替換 `agent/web/index.html`**

```html
<!DOCTYPE html>
<html lang="zh-Hant">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>地磅單列印 — 現場 agent</title>
<style>
  body { font-family: "微軟正黑體", "Microsoft JhengHei", sans-serif; margin: 0; background:#f4f6f8; color:#222; }
  .wrap { max-width: 1000px; margin: 0 auto; padding: 20px; }
  h1 { font-size: 20px; margin: 8px 0 4px; }
  .sub { color:#667; font-size:13px; margin-bottom:14px; }
  .bar { margin: 10px 0; }
  button { font-family:inherit; font-size:15px; padding:8px 16px; border-radius:8px; border:0; cursor:pointer; }
  .btn-refresh { background:#475569; color:#fff; }
  .btn-pdf { background:#2563eb; color:#fff; }
  .btn-print { background:#dc2626; color:#fff; }
  button:disabled { opacity:.4; cursor:not-allowed; }
  table { border-collapse:collapse; width:100%; background:#fff; }
  th,td { border:1px solid #dde; padding:6px 8px; font-size:14px; text-align:left; }
  th { background:#eef2f7; }
  tr.sel { background:#fde68a; }
  tbody tr { cursor:pointer; }
  #msg { margin-left:12px; font-size:14px; }
  .ok { color:#15803d; } .err { color:#b91c1c; }
  iframe { width:100%; height:460px; border:1px solid #ccd; border-radius:8px; margin-top:12px; background:#fff; display:none; }
</style>
</head>
<body>
<div class="wrap">
  <h1>地磅單列印 — 現場 agent</h1>
  <div class="sub">從 aigo 撈最近過磅紀錄,點一列選取,再「預覽 PDF」或「列印真紙」。</div>
  <div class="bar">
    <button class="btn-refresh" onclick="load()">重新整理</button>
    <button class="btn-pdf" id="btnPdf" onclick="doPrint('pdf')" disabled>預覽 PDF</button>
    <button class="btn-print" id="btnPrint" onclick="doPrint('print')" disabled>列印真紙</button>
    <span id="msg"></span>
  </div>
  <table>
    <thead><tr>
      <th>單號</th><th>車號</th><th>客戶</th><th>料種</th><th>操作員</th><th>毛重</th><th>淨重</th><th>狀態</th><th>時間</th>
    </tr></thead>
    <tbody id="rows"><tr><td colspan="9">載入中…</td></tr></tbody>
  </table>
  <iframe id="pv" title="PDF 預覽"></iframe>
</div>
<script>
let selectedId = null;
function setMsg(t, ok){ const m=document.getElementById('msg'); m.textContent=t; m.className = ok?'ok':'err'; }
function fmt(v){ return (v===null||v===undefined) ? '' : v; }

async function load(){
  setMsg('載入中…', true);
  selectedId = null;
  document.getElementById('btnPdf').disabled = true;
  document.getElementById('btnPrint').disabled = true;
  try{
    const j = await (await fetch('/records')).json();
    if(!j.ok){ setMsg('讀取失敗: '+(j.reason||''), false); return; }
    const tb = document.getElementById('rows');
    tb.innerHTML = '';
    for(const r of j.records){
      const tr = document.createElement('tr');
      tr.innerHTML = `<td>${fmt(r.ticket_no)}</td><td>${fmt(r.plate)}</td><td>${fmt(r.customer_name)}</td>`
        + `<td>${fmt(r.material_name)}</td><td>${fmt(r.weigh_operator)}</td><td>${fmt(r.gross_weight)}</td>`
        + `<td>${fmt(r.net_weight)}</td><td>${fmt(r.status)}</td><td>${fmt(r.at)}</td>`;
      tr.onclick = () => {
        selectedId = r.id;
        for(const x of tb.children) x.classList.remove('sel');
        tr.classList.add('sel');
        document.getElementById('btnPdf').disabled = false;
        document.getElementById('btnPrint').disabled = false;
        setMsg('已選: '+fmt(r.ticket_no), true);
      };
      tb.appendChild(tr);
    }
    setMsg('共 '+j.records.length+' 筆', true);
  }catch(e){ setMsg('連線錯誤: '+e.message, false); }
}

async function doPrint(mode){
  if(!selectedId){ setMsg('請先點一列選取', false); return; }
  if(mode==='print' && !confirm('確定要列印真紙(三聯磅單)嗎?')) return;
  setMsg(mode==='print'?'送印中…':'產生預覽中…', true);
  try{
    const j = await (await fetch('/print-record', {method:'POST', headers:{'Content-Type':'application/json'},
      body: JSON.stringify({ id: selectedId, mode })})).json();
    if(!j.ok){ setMsg('失敗: '+(j.reason||''), false); return; }
    if(mode==='pdf'){
      const pv=document.getElementById('pv'); pv.style.display='block'; pv.src=j.pdfUrl;
      setMsg('PDF 已產生,確認版面後再列印真紙', true);
    } else {
      setMsg('已送印至 '+fmt(j.printer)+(j.ticket_no?(' ('+j.ticket_no+')'):''), true);
    }
  }catch(e){ setMsg('連線錯誤: '+e.message, false); }
}

load();
</script>
</body>
</html>
```

- [ ] **Step 2: 靜態自我查核**

- 只呼叫 `/records`、`/print-record`、`/preview.pdf`(Task 2 提供)。
- 表格欄位 = 單號/車號/客戶/料種/操作員/毛重/淨重/狀態/時間。
- 點列選取 → 啟用兩鈕;列印真紙有 `confirm`;預覽以 iframe 顯示 `pdfUrl`。

- [ ] **Step 3: Commit**

```bash
cd /c/Users/user/Desktop/fde-czone
git add agent/web/index.html
git -c user.email='philosophysis@gmail.com' -c user.name='philosophysis' commit -m "feat(agent): index.html 改為紀錄列表→選→預覽/列印"
```

---

### Task 4: 端到端驗證(啟動 agent + 瀏覽器 + 列印)

**Files:** 無(驗證)。

- [ ] **Step 1: 啟動 agent**

```bash
powershell.exe -NoProfile -Command "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; \$env:AGENT_DIR='C:\Users\user\Desktop\fde-czone\agent'; & ([ScriptBlock]::Create((Get-Content -Raw -Encoding UTF8 -LiteralPath 'C:\Users\user\Desktop\fde-czone\agent\Start-Agent.ps1')))"
```
(用 run_in_background)Expected:印出「引擎就緒…」「現場 agent 已啟動 -> http://localhost:9180/」。

- [ ] **Step 2: 瀏覽器驗證(人工)**

開 `http://localhost:9180/`。Expected:看到「地磅單列印 — 現場 agent」,表格列出 aigo 最近紀錄(例 `20260622-001` / 測試環保 / 一般事業廢棄物 / 王小明 / 毛重 14540 / 淨重 4000 / done)。
點該列 → 兩鈕啟用 → 按「預覽 PDF」→ iframe 顯示三聯磅單,客戶=測試環保、料種=一般事業廢棄物、毛重=14540 KG(整數,非 14540.0)。

- [ ] **Step 3: 列印真紙(人工確認紙張後)**

按「列印真紙」→ confirm → Expected:訊息「已送印至 EPSON LQ-690CII (20260622-001)」,印表機出三聯磅單,版面對齊(沿用既有薪榮校正 + 硬體邊界補償)。

- [ ] **Step 4: 停止背景 agent**

結束 Step 1 的背景工作。

---

## 完成後

Task 4 通過 = **本地撈 aigo 紀錄 → 選 → 預覽/列印** 整段可用。
範圍外(另案):回寫「已列印」狀態、自動輪詢、真實設備輸入端。
