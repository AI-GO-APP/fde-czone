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
