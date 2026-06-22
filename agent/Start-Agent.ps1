# Start-Agent.ps1 - 磅單列印現場 agent (本機 HttpListener 服務)
# 階段一: 手動輸入 -> /print -> GDI 印三聯磅單 (或先出 PDF 預覽)。
# 架構: PowerShell 5.1 + HttpListener(localhost) + 重用 WeighTicketPrint 列印引擎。
#
# 啟動: 用同目錄的 start.cmd (繞過 Restricted 執行原則 + UTF-8)。
#       或: powershell -NoProfile -Command "& ([ScriptBlock]::Create((Get-Content -Raw -Encoding UTF8 '.\Start-Agent.ps1')))"

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 經 scriptblock 執行時 $PSScriptRoot 為空, 用 AGENT_DIR 後援 (start.cmd 會設)。
if (-not $PSScriptRoot) {
    $PSScriptRoot = if ($env:AGENT_DIR) { $env:AGENT_DIR } else { 'C:\Users\user\Desktop\fde-czone\agent' }
}

# ---- 載入 lib (頂層 dot-source scriptblock; 不受 Restricted 執行原則限制) ----
# 注意: 必須在頂層 dot-source, 若包進函式內 dot-source, 函式回傳後定義就消失。
. ([ScriptBlock]::Create((Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot 'lib\PrintEngine.ps1'))))
. ([ScriptBlock]::Create((Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot 'lib\AigoClient.ps1'))))

# ---- 設定 ----
function Get-AgentConfig {
    $p = Join-Path $PSScriptRoot 'config.local.json'
    if (-not (Test-Path $p)) { throw "config.local.json 不存在 — 請從 config.example.json 複製並填值" }
    Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
}
$cfg = Get-AgentConfig

$Port    = if ($cfg.port)    { [int]$cfg.port }       else { 9180 }
$Printer = if ($cfg.printer) { [string]$cfg.printer } else { 'EPSON LQ-690CII' }
$Font    = if ($cfg.font)    { [string]$cfg.font }    else { '新細明體' }

$WeighTicketRoot = if ($cfg.weighTicketRoot) { [string]$cfg.weighTicketRoot } `
                   else { Join-Path (Split-Path $PSScriptRoot -Parent) 'WeighTicketPrint' }
$FrxPath = if ($cfg.frxPath) { [string]$cfg.frxPath } `
           else { Join-Path $WeighTicketRoot 'template\rptWeight廣達昌.frx' }
$WebDir  = Join-Path $PSScriptRoot 'web'
$OutDir  = Join-Path $PSScriptRoot 'out'
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
        else {
            Write-Json $resp @{ ok = $false; reason = 'not found' } 404
        }
    } catch {
        try { Write-Json $resp @{ ok = $false; reason = "$($_.Exception.Message)" } 500 } catch {}
    } finally {
        $resp.OutputStream.Close()
    }
}
