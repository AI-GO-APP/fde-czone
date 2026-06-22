# WeighTicketPrint - 單元測試 (純邏輯, 零安裝)
#   測: 座標換算 / 日期(d)時間(HH:mm)格式化 / 重量 KG 字面 / 中文代換 / .frx 解析 / 三聯水平平移
# 用法: powershell -NoProfile -File Run-Tests.ps1
param(
    [string]$ProjectRoot,
    [string]$FrxPath
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 路徑解析: 一般用 -File 執行時取 $PSScriptRoot; 透過 -Command/iex 執行時退回絕對路徑。
if (-not $ProjectRoot) {
    if ($PSScriptRoot) { $ProjectRoot = Split-Path -Parent $PSScriptRoot }
    else { $ProjectRoot = "C:\Users\user\Desktop\fde-czone\WeighTicketPrint" }
}
if (-not $FrxPath) { $FrxPath = Join-Path $ProjectRoot "template\rptWeight廣達昌.frx" }

$logic = Join-Path $ProjectRoot "src\Logic.cs"
Add-Type -Path $logic -ReferencedAssemblies System.Xml

# ---- 迷你斷言框架 ----
$script:pass = 0
$script:fail = 0
function Assert-Equal($expected, $actual, $msg) {
    if ([string]$expected -ceq [string]$actual) {
        Write-Host ("  PASS  " + $msg) -ForegroundColor Green; $script:pass++
    } else {
        Write-Host ("  FAIL  " + $msg + "  | expected=[$expected] actual=[$actual]") -ForegroundColor Red; $script:fail++
    }
}
function Assert-Near($expected, $actual, $tol, $msg) {
    if ([math]::Abs([double]$expected - [double]$actual) -le $tol) {
        Write-Host ("  PASS  " + $msg) -ForegroundColor Green; $script:pass++
    } else {
        Write-Host ("  FAIL  " + $msg + "  | expected~=$expected actual=$actual tol=$tol") -ForegroundColor Red; $script:fail++
    }
}

$tw = [System.Globalization.CultureInfo]::GetCultureInfo("zh-TW")

Write-Host "[1] 座標換算 PxToMm" -ForegroundColor Cyan
Assert-Near 25.4   ([WeighTicket.Units]::PxToMm(96))    1e-9 "96px = 25.4mm"
Assert-Near 22.5   ([WeighTicket.Units]::PxToMm(85.04)) 0.01 "資料欄 85.04px = 22.5mm"
Assert-Near 162.5  ([WeighTicket.Units]::PxToMm(614.2)) 0.01 "淨重列 614.2px = 162.5mm"
Assert-Near 96     ([WeighTicket.Units]::MmToPx(25.4))  1e-9 "反向 25.4mm = 96px"

Write-Host "[2] 資料格式化 Formatter" -ForegroundColor Cyan
$data = New-Object 'System.Collections.Generic.Dictionary[string,object]'
$data["SR_Customer"]    = "測試環保"
$data["SR_Traffic"]     = "大發車行"
$data["SR_Times"]       = [int16]3
$data["SR_GrossWeight"] = [int]14540
$data["SR_DatetimeG"]   = [datetime]"2026-06-22 14:05:00"

function New-Field($text, $fmtKind, $fmtStr) {
    $f = New-Object WeighTicket.FieldDef
    $f.Text = $text
    $f.FormatKind = $fmtKind
    $f.FormatString = $fmtStr
    return $f
}

$fDate = New-Field "[Query.SR_DatetimeG]" ([WeighTicket.FmtKind]::Date) "d"
Assert-Equal "2026/6/22" ([WeighTicket.Formatter]::Resolve($fDate, $data, $tw)) "日期格式 d"

$fTime = New-Field "[Query.SR_DatetimeG]" ([WeighTicket.FmtKind]::Time) "HH:mm"
Assert-Equal "14:05" ([WeighTicket.Formatter]::Resolve($fTime, $data, $tw)) "時間格式 HH:mm"

$fGross = New-Field "[Query.SR_GrossWeight] KG" ([WeighTicket.FmtKind]::None) ""
Assert-Equal "14540 KG" ([WeighTicket.Formatter]::Resolve($fGross, $data, $tw)) "重量保留樣板的 ' KG' 字面"

$fCust = New-Field "[Query.SR_Customer]" ([WeighTicket.FmtKind]::None) ""
Assert-Equal "測試環保" ([WeighTicket.Formatter]::Resolve($fCust, $data, $tw)) "中文欄位代換"

$fTimes = New-Field "[Query.SR_Times]" ([WeighTicket.FmtKind]::None) ""
Assert-Equal "3" ([WeighTicket.Formatter]::Resolve($fTimes, $data, $tw)) "次數 (整數) 代換"

$fHdr = New-Field "薪榮環保股份有限公司" ([WeighTicket.FmtKind]::None) ""
Assert-Equal "薪榮環保股份有限公司" ([WeighTicket.Formatter]::Resolve($fHdr, $data, $tw)) "純文字抬頭原樣輸出"

$fMissing = New-Field "[Query.SR_Note]" ([WeighTicket.FmtKind]::None) ""
Assert-Equal "" ([WeighTicket.Formatter]::Resolve($fMissing, $data, $tw)) "缺資料 -> 空字串"

Write-Host "[3] .frx 解析 + 三聯結構" -ForegroundColor Cyan
if (Test-Path -LiteralPath $FrxPath) {
    $layout = [WeighTicket.FrxParser]::Parse($FrxPath)
    Assert-Near 242 $layout.PaperWidthMm  0.001 "紙張寬 242mm"
    Assert-Near 178 $layout.PaperHeightMm 0.001 "紙張高 178mm"

    $hdr = [WeighTicket.PanelOps]::HeaderLefts($layout, "薪榮環保股份有限公司")
    Assert-Equal 3 $hdr.Count "抬頭出現 3 次 (三聯)"

    # 量測三聯水平基準 (px) 與間距, 記錄供校準參考
    $p1 = $hdr[0]; $p2 = $hdr[1]; $p3 = $hdr[2]
    Write-Host ("        三聯抬頭 Left(px) = {0:N2} / {1:N2} / {2:N2}" -f $p1,$p2,$p3) -ForegroundColor DarkGray
    Write-Host ("        三聯抬頭間距(px)  = {0:N2} / {1:N2}" -f ($p2-$p1),($p3-$p2)) -ForegroundColor DarkGray

    Write-Host "[4] 三聯水平平移 PanelOps.ShiftedCopy" -ForegroundColor Cyan
    $base = New-Object WeighTicket.FieldDef
    $base.LeftPx = 85.04; $base.TopPx = 283.49
    $shifted = [WeighTicket.PanelOps]::ShiftedCopy($base, 272.13)
    Assert-Near 357.17 $shifted.LeftPx 0.001 "平移 +272.13px -> 357.17px (第二聯資料欄)"
    Assert-Near 283.49 $shifted.TopPx  0.001 "平移不改變 Top"
    Assert-Near 85.04  $base.LeftPx    0.001 "原物件不被改動 (回傳複本)"
} else {
    Write-Host "  SKIP  找不到 .frx: $FrxPath" -ForegroundColor Yellow
}

Write-Host ""
Write-Host ("結果: PASS=$script:pass  FAIL=$script:fail") -ForegroundColor (@{$true="Green";$false="Red"}[$script:fail -eq 0])
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
