# WeighTicketPrint - 主列印程式 (三聯地磅單)
#
# 做法: Windows GDI 系統列印 (System.Drawing.Printing) -> 印到 EPSON LQ-690CII 驅動。
#       中文交給 Windows 字型由驅動轉點陣。不引用 FastReport, 不手刻 ESC/P2。
#
# 省紙鐵則: 預設 -Mode pdf, 先出 PDF 給人確認版面。真實列印需 -Mode printer -ConfirmRealPrint。
#
# 用法範例:
#   產生 PDF 預覽 (預設):   powershell -NoProfile -File Print-Ticket.ps1
#   產生 PNG 預覽:          powershell -NoProfile -File Print-Ticket.ps1 -Mode png
#   真的印 (人工確認後):    powershell -NoProfile -File Print-Ticket.ps1 -Mode printer -ConfirmRealPrint
param(
    [ValidateSet('pdf','png','printer')]
    [string]$Mode = 'pdf',
    [string]$ProjectRoot,
    [string]$FrxPath,
    [string]$Printer = 'EPSON LQ-690CII',
    [string]$Font = '新細明體',
    [string]$OutDir,
    [double]$OffsetXmm = 0,   # 微調: 正值往右, 負值往左
    [double]$OffsetYmm = 0,   # 微調: 正值往下, 負值往上 (目前回報偏下 -> 用負值往上)
    [switch]$ConfirmRealPrint
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ---- 路徑解析 ----
if (-not $ProjectRoot) {
    if ($PSScriptRoot) { $ProjectRoot = $PSScriptRoot }
    else { $ProjectRoot = "C:\Users\user\Desktop\fde-czone\WeighTicketPrint" }
}
if (-not $FrxPath) { $FrxPath = Join-Path $ProjectRoot "template\rptWeight廣達昌.frx" }
if (-not $OutDir)  { $OutDir  = Join-Path $ProjectRoot "out" }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

# ---- 載入程式 (純 XML 解析 + GDI 渲染, 不碰 FastReport) ----
# 兩個 .cs 要一起編譯成同一組件, Renderer 才看得到 Logic 的型別。
$srcFiles = @(
    (Join-Path $ProjectRoot "src\Logic.cs"),
    (Join-Path $ProjectRoot "src\Renderer.cs")
)
Add-Type -Path $srcFiles -ReferencedAssemblies System.Xml, System.Drawing

# ---- 假資料 (這階段寫死; 真實資料之後由上游帶入) ----
$data = New-Object 'System.Collections.Generic.Dictionary[string,object]'
$data['SR_Customer']    = '測試環保'
$data['SR_Traffic']     = '大發環保企業'
$data['SR_Times']       = [int16]3
$data['SR_User']        = '王小明'
$data['SR_DatetimeG']   = [datetime]'2026-06-22 14:05:00'   # 日期欄用 d, 時間欄用 HH:mm
$data['SR_SN']          = 'SN20260622-001'
$data['SR_Material']    = '一般事業廢棄物'
$data['SR_CarNo']       = 'KEP-2758'
$data['SR_GrossWeight'] = [int]14540    # 樣板會自動接 ' KG'
$data['SR_EmptyWeight'] = [int]8200
$data['SR_NetWeight']   = [int]6340
$data['SR_Field1']      = '過磅單'

# ---- 解析版面 + 建立渲染器 ----
$layout = [WeighTicket.FrxParser]::Parse($FrxPath)
Write-Host ("版面來源: {0}" -f $FrxPath) -ForegroundColor DarkGray
Write-Host ("紙張: {0}mm x {1}mm  欄位數: {2}" -f $layout.PaperWidthMm, $layout.PaperHeightMm, $layout.Fields.Count) -ForegroundColor DarkGray

# ---- 薪榮表單「上半段」行位校正 ----
# rptWeight廣達昌.frx 的上半段欄位行距沿用廣達昌表單, 與薪榮實體預印表單不符
# (薪榮上半段為均勻 ~10.5mm 行距: 客戶名稱/扣水份/扣雜物/車行/車次/會磅員)。
# 以實測值覆寫上半段欄位的 Top(mm); 下半段表格(日期~淨重)維持 .frx 原座標(已對準)。
# 量測方法見 coordinates.md (用對準的表格列+格線反推)。
$topCalibMm = @{
    'SR_Customer' = 39.3   # 客戶名稱
    'SR_Field1'   = 49.8   # 扣水份
    'SR_Traffic'  = 70.8   # 車行  (原 75 -> 上移約 4mm, 主要偏差)
    'SR_Times'    = 81.3   # 車次
    'SR_User'     = 91.8   # 會磅員
}
foreach ($f in $layout.Fields) {
    foreach ($k in $topCalibMm.Keys) {
        if ($f.Text -match $k) { $f.TopPx = $topCalibMm[$k] * 96.0 / 25.4 }
    }
}

# 上半段「水平」對齊: 薪榮表單上半段冒號對齊在 ~17.4mm, 值應全部從同一 X 起。
# .frx 把 客戶名稱/扣水份 放在 16mm, 車行/車次/會磅員 在 22.5mm (差 6mm -> 看起來歪)。
# 把 客戶名稱/扣水份 的 Left 對齊到該聯的資料欄 (22.5/94.5/167.5mm), 六值左緣成一條線。
$dataColsPx = @(85.04, 357.17, 633.07)   # 三聯資料欄 X(px) = 22.5/94.5/167.5mm
foreach ($f in $layout.Fields) {
    if ($f.Text -match 'SR_Customer' -or $f.Text -match 'SR_Field1') {
        $best = $dataColsPx[0]
        foreach ($c in $dataColsPx) {
            if ([math]::Abs($c - $f.LeftPx) -lt [math]::Abs($best - $f.LeftPx)) { $best = $c }
        }
        $f.LeftPx = $best
    }
}

$renderer = New-Object WeighTicket.TicketRenderer($layout, $data, $Font)
$renderer.OffsetXmm = $OffsetXmm
$renderer.OffsetYmm = $OffsetYmm
if ($OffsetXmm -ne 0 -or $OffsetYmm -ne 0) {
    Write-Host ("微調位移: X={0}mm Y={1}mm" -f $OffsetXmm, $OffsetYmm) -ForegroundColor DarkGray
}

switch ($Mode) {
    'pdf' {
        # 尺寸正確的影像版 PDF (MediaBox=242x178mm)。不依賴 Microsoft Print to PDF
        # (它會忽略自訂紙張退回 A4); 也不需動印表機伺服器設定。
        $out = Join-Path $OutDir "preview.pdf"
        if (Test-Path $out) { Remove-Item $out -Force }
        $renderer.SaveExactSizePdf($out, 200)
        Write-Host ("[PDF] 已輸出 (MediaBox 242x178mm): {0}" -f $out) -ForegroundColor Green
    }
    'png' {
        $out = Join-Path $OutDir "preview.png"
        $dpi = 300
        $wpx = [int][math]::Round($layout.PaperWidthMm  / 25.4 * $dpi)
        $hpx = [int][math]::Round($layout.PaperHeightMm / 25.4 * $dpi)
        $bmp = New-Object System.Drawing.Bitmap($wpx, $hpx)
        $bmp.SetResolution($dpi, $dpi)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.Clear([System.Drawing.Color]::White)
        $renderer.DrawAll($g)
        $g.Dispose()
        $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        Write-Host ("[PNG] 已輸出: {0} ({1}x{2}px @ {3}dpi)" -f $out, $wpx, $hpx, $dpi) -ForegroundColor Green
    }
    'printer' {
        if (-not $ConfirmRealPrint) {
            throw "安全保護: 真實列印需加 -ConfirmRealPrint。請先用 -Mode pdf/png 確認版面對齊, 經人工確認後再印真紙。"
        }
        $renderer.PrinterSettings.PrinterName = $Printer
        if (-not $renderer.PrinterSettings.IsValid) { throw ("找不到印表機: {0}" -f $Printer) }
        $renderer.ApplyPaper()
        $renderer.Print()
        Write-Host ("[列印] 已送印至: {0}" -f $Printer) -ForegroundColor Yellow
    }
}
