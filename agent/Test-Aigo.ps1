# Test-Aigo.ps1 - 驗證「本機 ↔ aigo」串接
#   -Mode check : 只登入 + 列出資料表 (唯讀, 不改任何資料) — 先用這個確認連得上、表存在
#   -Mode weigh : 呼叫 weigh action + 用回傳 print_payload 出 PDF (會在 aigo 新增一筆過磅紀錄)
#
# 啟動: powershell -NoProfile -Command "& ([ScriptBlock]::Create((Get-Content -Raw -Encoding UTF8 '.\Test-Aigo.ps1'))) check"
param([ValidateSet('check','weigh')][string]$Mode = 'check')

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 經 scriptblock 執行時 $PSScriptRoot 為空, 用 AGENT_DIR 後援。
if (-not $PSScriptRoot) {
    $PSScriptRoot = if ($env:AGENT_DIR) { $env:AGENT_DIR } else { 'C:\Users\user\Desktop\fde-czone\agent' }
}

# 在頂層 dot-source scriptblock (函式內 dot-source 會落在函式 scope, 函式回傳即消失)。
. ([ScriptBlock]::Create((Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot 'lib\AigoClient.ps1'))))
. ([ScriptBlock]::Create((Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot 'lib\PrintEngine.ps1'))))

$cfg = Get-Content (Join-Path $PSScriptRoot 'config.local.json') -Raw -Encoding UTF8 | ConvertFrom-Json

Write-Host ("登入 {0} (帳號 {1}) ..." -f $cfg.aigoBaseUrl, $cfg.email) -ForegroundColor Cyan
$token = Connect-Aigo $cfg
Write-Host ("✓ 登入成功, token 長度 {0}" -f $token.Length) -ForegroundColor Green

if ($Mode -eq 'check') {
    # 唯讀: 列出 Custom Object, 確認 x_czone_* 表存在
    $resp = Invoke-WebRequest -Method Get -Uri "$($cfg.aigoBaseUrl)/api/v1/data/objects" `
        -Headers @{ Authorization = "Bearer $token" } -UseBasicParsing
    $objs = [System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) | ConvertFrom-Json
    Write-Host "資料表 (Custom Object):" -ForegroundColor Cyan
    $objs | Where-Object { $_.api_slug -like 'x_czone*' } | ForEach-Object {
        Write-Host ("  ✓ {0}  ({1})  id={2}" -f $_.api_slug, $_.name, $_.id) -ForegroundColor Green
    }
    Write-Host "✓ check 完成 (未改動任何資料)" -ForegroundColor Green
}
elseif ($Mode -eq 'weigh') {
    # 呼叫 weigh: 手動 plate+weight (不需影像)。注意: 會在 aigo 新增/更新過磅紀錄。
    $params = @{ plate = 'KEP-2758'; weight = 14.54; weigh_operator = '王小明';
                 plate_source = 'manual'; weight_source = 'manual' }
    Write-Host "呼叫 weigh action ..." -ForegroundColor Cyan
    $r = Resolve-AigoWeigh $cfg $params
    Write-Host "✓ 回應:" -ForegroundColor Green
    Write-Host ("  ticket_no={0}  event={1}  net={2}" -f $r.ticket_no, $r.event, $r.net_weight)
    Write-Host "  print_payload:" -ForegroundColor Cyan
    $r.print_payload.PSObject.Properties | ForEach-Object { Write-Host ("    {0} = {1}" -f $_.Name, $_.Value) }

    # 用 print_payload 出 PDF (對應表已支援 SR_Sn/SR_Tn/SR_Date/SR_GwTon...)
    Initialize-PrintEngine -WeighTicketRoot (Join-Path (Split-Path $PSScriptRoot -Parent) 'WeighTicketPrint')
    $layout = Get-TicketLayout -FrxPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'WeighTicketPrint\template\rptWeight廣達昌.frx')
    $data = ConvertTo-TicketData $r.print_payload
    $pdf = Export-TicketPdf $layout $data (Join-Path $PSScriptRoot 'out\aigo_weigh_preview.pdf')
    Write-Host ("✓ 已用 aigo 回傳資料出 PDF: {0}" -f $pdf) -ForegroundColor Green
}
