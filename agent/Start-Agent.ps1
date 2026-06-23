# Start-Agent.ps1 - 磅單列印現場 agent (本機 HttpListener 服務)
# 列出 aigo 紀錄 -> 選 -> 預覽/列印。
# 架構: PowerShell 5.1 + HttpListener(localhost) + 重用 WeighTicketPrint 列印引擎。
#
# 啟動: 用同目錄的 start.cmd (繞過 Restricted 執行原則 + UTF-8)。
#       或: powershell -NoProfile -Command "& ([ScriptBlock]::Create((Get-Content -Raw -Encoding UTF8 '.\Start-Agent.ps1')))"

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 經 scriptblock 執行時 $PSScriptRoot 為空, 用 AGENT_DIR 後援 (start.cmd 會設)。
# $script:AgentDir 確保函式內也能讀到正確路徑 (PS5.1 scriptblock 不繼承 $PSScriptRoot)。
if ($PSScriptRoot) {
    $script:AgentDir = $PSScriptRoot
} elseif ($env:AGENT_DIR) {
    $script:AgentDir = $env:AGENT_DIR
} else {
    $script:AgentDir = 'C:\Users\user\Desktop\fde-czone\agent'
}

# ---- 載入 lib (頂層 dot-source scriptblock; 不受 Restricted 執行原則限制) ----
# 注意: 必須在頂層 dot-source, 若包進函式內 dot-source, 函式回傳後定義就消失。
. ([ScriptBlock]::Create((Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $script:AgentDir 'lib\PrintEngine.ps1'))))
. ([ScriptBlock]::Create((Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $script:AgentDir 'lib\AigoClient.ps1'))))

# ---- 設定 ----
function Get-AgentConfig {
    $p = Join-Path $script:AgentDir 'config.local.json'
    if (-not (Test-Path $p)) { throw "config.local.json 不存在 — 請從 config.example.json 複製並填值" }
    Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
}
$cfg = Get-AgentConfig

$Port    = if ($cfg.port)    { [int]$cfg.port }       else { 9180 }
$Printer = if ($cfg.printer) { [string]$cfg.printer } else { 'EPSON LQ-690CII' }
$Font    = if ($cfg.font)    { [string]$cfg.font }    else { '新細明體' }

$WeighTicketRoot = if ($cfg.weighTicketRoot) { [string]$cfg.weighTicketRoot } `
                   else { Join-Path (Split-Path $script:AgentDir -Parent) 'WeighTicketPrint' }
$FrxPath = if ($cfg.frxPath) { [string]$cfg.frxPath } `
           else { Join-Path $WeighTicketRoot 'template\rptWeight廣達昌.frx' }
$WebDir  = Join-Path $script:AgentDir 'web'
$OutDir  = Join-Path $script:AgentDir 'out'
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

# ---- 初始化列印引擎 (載入 C# + 解析+校正版面一次) ----
Initialize-PrintEngine -WeighTicketRoot $WeighTicketRoot
$layout = Get-TicketLayout -FrxPath $FrxPath
Write-Host ("引擎就緒: 紙張 {0}x{1}mm, 欄位 {2}, 印表機 '{3}'" -f `
    $layout.PaperWidthMm, $layout.PaperHeightMm, $layout.Fields.Count, $Printer) -ForegroundColor Green

# ---- HTTP 輔助 ----
function Write-Json($resp, $obj, [int]$code) {
    $resp.StatusCode = $code
    $resp.ContentType = 'application/json; charset=utf-8'
    $b = [System.Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Depth 8 -Compress))
    $resp.OutputStream.Write($b, 0, $b.Length)
}
function Write-Bytes($resp, [byte[]]$bytes, [string]$ctype, [int]$code) {
    $resp.StatusCode = $code
    $resp.ContentType = $ctype
    $resp.OutputStream.Write($bytes, 0, $bytes.Length)
}
function Read-Body($req) {
    $sr = New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)
    try { $sr.ReadToEnd() } finally { $sr.Dispose() }
}

# ---- 啟動 listener ----
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
try {
    $listener.Start()
} catch {
    Write-Host "HttpListener 啟動失敗。若是權限問題, 用系統管理員執行一次:" -ForegroundColor Red
    Write-Host "  netsh http add urlacl url=http://localhost:$Port/ user=$env:USERNAME" -ForegroundColor Yellow
    throw
}
Write-Host ("現場 agent 已啟動 -> http://localhost:{0}/  (Ctrl+C 結束)" -f $Port) -ForegroundColor Cyan

# listener 已就緒, 此時開瀏覽器最準 (由 start.cmd 設 AGENT_OPEN_BROWSER=1 觸發)
if ($env:AGENT_OPEN_BROWSER -eq '1') {
    try { Start-Process ("http://localhost:{0}/" -f $Port) } catch {}
}

while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $req = $ctx.Request
    $resp = $ctx.Response
    try {
        $path = $req.Url.AbsolutePath
        $method = $req.HttpMethod

        if ($method -eq 'GET' -and ($path -eq '/' -or $path -eq '/index.html')) {
            $html = [System.IO.File]::ReadAllBytes((Join-Path $WebDir 'index.html'))
            Write-Bytes $resp $html 'text/html; charset=utf-8' 200
        }
        elseif ($method -eq 'GET' -and $path -eq '/health') {
            Write-Json $resp @{ ok = $true; printer = $Printer; port = $Port; fields = $layout.Fields.Count } 200
        }
        elseif ($method -eq 'GET' -and $path -eq '/preview.pdf') {
            $pdf = Join-Path $OutDir 'preview.pdf'
            if (Test-Path $pdf) { Write-Bytes $resp ([System.IO.File]::ReadAllBytes($pdf)) 'application/pdf' 200 }
            else { Write-Json $resp @{ ok = $false; reason = '尚無預覽, 請先按產生PDF' } 404 }
        }
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
        else {
            Write-Json $resp @{ ok = $false; reason = 'not found' } 404
        }
    } catch {
        try { Write-Json $resp @{ ok = $false; reason = "$($_.Exception.Message)" } 500 } catch {}
    } finally {
        $resp.OutputStream.Close()
    }
}
