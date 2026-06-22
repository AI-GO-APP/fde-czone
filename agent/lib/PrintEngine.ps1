# PrintEngine.ps1 - 共用列印引擎
# 重用 WeighTicketPrint 的 Logic.cs / Renderer.cs (GDI 列印, 不引用 FastReport)。
# 提供: 載入引擎 / 取得已校正版面 / 契約 payload -> .frx 資料字典(對應表) / 渲染(PDF/列印)。
# 全部為可重用函式, 供 Start-Agent.ps1 與 tests 共用。

$ErrorActionPreference = 'Stop'

# ---- 薪榮表單校正 (與 WeighTicketPrint\Print-Ticket.ps1 一致) ----
$script:TopCalibMm = @{
    'SR_Customer' = 39.3   # 客戶名稱
    'SR_Field1'   = 49.8   # 扣水份
    'SR_Traffic'  = 70.8   # 車行
    'SR_Times'    = 81.3   # 車次
    'SR_User'     = 91.8   # 會磅員
}
$script:DataColsPx = @(85.04, 357.17, 633.07)   # 三聯資料欄 X(px) = 22.5/94.5/167.5mm

# ---- 欄位別名對應表 ----
# 把「友善名(階段一手動表單) / aigo 契約 payload 名 / .frx 原綁定名」都對到 .frx 綁定。
# 契約: company,SR_Sn,SR_Tn,SR_Date,SR_User,SR_Direction,SR_Material,SR_GwTon,SR_TwTon,SR_NwTon
$script:Alias = @{
    # 友善名 (index.html 手動表單)
    'customer' = 'SR_Customer'; 'traffic' = 'SR_Traffic'; 'times' = 'SR_Times'
    'operator' = 'SR_User';     'datetime' = 'SR_DatetimeG'; 'sn' = 'SR_SN'
    'material' = 'SR_Material';  'carno' = 'SR_CarNo'
    'gross' = 'SR_GrossWeight';  'empty' = 'SR_EmptyWeight'; 'net' = 'SR_NetWeight'
    'field1' = 'SR_Field1'
    # aigo 契約 payload 名 (註: PS 雜湊不分大小寫, SR_Sn 會命中下方 SR_SN, 故不重列)
    'SR_Tn' = 'SR_CarNo'; 'SR_Date' = 'SR_DatetimeG'
    'SR_GwTon' = 'SR_GrossWeight'; 'SR_TwTon' = 'SR_EmptyWeight'; 'SR_NwTon' = 'SR_NetWeight'
    # .frx 原綁定名 (直通)
    'SR_Customer' = 'SR_Customer'; 'SR_Traffic' = 'SR_Traffic'; 'SR_Times' = 'SR_Times'
    'SR_User' = 'SR_User'; 'SR_DatetimeG' = 'SR_DatetimeG'; 'SR_SN' = 'SR_SN'
    'SR_Material' = 'SR_Material'; 'SR_CarNo' = 'SR_CarNo'
    'SR_GrossWeight' = 'SR_GrossWeight'; 'SR_EmptyWeight' = 'SR_EmptyWeight'; 'SR_NetWeight' = 'SR_NetWeight'
    'SR_Field1' = 'SR_Field1'
    # 註: company(抬頭) 與 SR_Direction(進/出) 在此薪榮 .frx 無對應欄位, 暫不列印。
}

function Initialize-PrintEngine {
    param([Parameter(Mandatory)][string]$WeighTicketRoot)
    if (-not ('WeighTicket.TicketRenderer' -as [type])) {
        $src = @(
            (Join-Path $WeighTicketRoot 'src\Logic.cs'),
            (Join-Path $WeighTicketRoot 'src\Renderer.cs')
        )
        Add-Type -Path $src -ReferencedAssemblies System.Xml, System.Drawing
    }
}

function Get-TicketLayout {
    # 解析 .frx 並套用薪榮校正 (上半段行位 + 水平左緣對齊)。下半段表格維持原座標。
    param([Parameter(Mandatory)][string]$FrxPath)
    $layout = [WeighTicket.FrxParser]::Parse($FrxPath)
    foreach ($f in $layout.Fields) {
        foreach ($k in $script:TopCalibMm.Keys) {
            if ($f.Text -match $k) { $f.TopPx = $script:TopCalibMm[$k] * 96.0 / 25.4 }
        }
        if ($f.Text -match 'SR_Customer' -or $f.Text -match 'SR_Field1') {
            $best = $script:DataColsPx[0]
            foreach ($c in $script:DataColsPx) {
                if ([math]::Abs($c - $f.LeftPx) -lt [math]::Abs($best - $f.LeftPx)) { $best = $c }
            }
            $f.LeftPx = $best
        }
    }
    return $layout
}

function ConvertTo-FieldValue {
    # 依目標綁定做型別轉換: 日期->DateTime, 次數->Int16, 重量->Int; 其餘字串。空值回 $null。
    param([string]$Binding, $Value)
    if ($null -eq $Value) { return $null }
    $s = ([string]$Value).Trim()
    if ($s -eq '') { return $null }
    switch ($Binding) {
        'SR_DatetimeG'   { try { return [datetime]$s } catch { return $s } }
        'SR_Times'       { $n = 0; if ([int]::TryParse($s, [ref]$n)) { return [int16]$n }; return $s }
        'SR_GrossWeight' { $n = 0; if ([int]::TryParse($s, [ref]$n)) { return [int]$n }; return $s }
        'SR_EmptyWeight' { $n = 0; if ([int]::TryParse($s, [ref]$n)) { return [int]$n }; return $s }
        'SR_NetWeight'   { $n = 0; if ([int]::TryParse($s, [ref]$n)) { return [int]$n }; return $s }
        default          { return $s }
    }
}

function ConvertTo-TicketData {
    # 純邏輯: 任意輸入(hashtable 或 PSCustomObject, 友善名/契約名/綁定名混用) -> .frx 資料字典。
    param([Parameter(Mandatory)] $Values)
    $pairs = @{}
    if ($Values -is [System.Collections.IDictionary]) {
        foreach ($e in $Values.GetEnumerator()) { $pairs[$e.Key] = $e.Value }
    } else {
        foreach ($p in $Values.PSObject.Properties) { $pairs[$p.Name] = $p.Value }
    }
    $d = New-Object 'System.Collections.Generic.Dictionary[string,object]'
    foreach ($k in $pairs.Keys) {
        if (-not $script:Alias.ContainsKey($k)) { continue }
        $bind = $script:Alias[$k]
        $cv = ConvertTo-FieldValue $bind $pairs[$k]
        if ($null -ne $cv) { $d[$bind] = $cv }
    }
    return , $d
}

function ConvertFrom-WeighingData {
    # 把 aigo x_czone_weighing 紀錄的 .data 轉成 .frx 資料字典。
    # DB 欄位 -> 友善名 -> (ConvertTo-TicketData) -> .frx 綁定。日期取二磅優先, 否則一磅。
    # 註: customer_id / material_id 目前是 id, 之後需 join 車籍/料種表換成名稱。
    param([Parameter(Mandatory)] $Data)
    $dt = if ($Data.second_weigh_at) { $Data.second_weigh_at } else { $Data.first_weigh_at }
    $inp = @{
        sn       = $Data.ticket_no
        carno    = $Data.plate
        operator = $Data.weigh_operator
        gross    = $Data.gross_weight
        empty    = $Data.tare_weight
        net      = $Data.net_weight
        material = $Data.material_id
        customer = $Data.customer_id
        datetime = $dt
    }
    return ConvertTo-TicketData $inp
}

function New-TicketRenderer {
    param($Layout, $Data, [string]$Font = '新細明體', [double]$OffsetXmm = 0, [double]$OffsetYmm = 0)
    $r = New-Object WeighTicket.TicketRenderer($Layout, $Data, $Font)
    $r.OffsetXmm = $OffsetXmm
    $r.OffsetYmm = $OffsetYmm
    return $r
}

function Export-TicketPdf {
    # 省紙: 輸出尺寸正確的 PDF 預覽 (MediaBox 242x178mm)。
    param($Layout, $Data, [Parameter(Mandatory)][string]$Path,
          [string]$Font = '新細明體', [double]$OffsetXmm = 0, [double]$OffsetYmm = 0)
    $r = New-TicketRenderer $Layout $Data $Font $OffsetXmm $OffsetYmm
    if (Test-Path $Path) { Remove-Item $Path -Force }
    $r.SaveExactSizePdf($Path, 200)
    return $Path
}

function Invoke-TicketPrint {
    # 真實列印到指定印表機 (GDI + 硬體邊界補償)。
    param($Layout, $Data, [Parameter(Mandatory)][string]$Printer,
          [string]$Font = '新細明體', [double]$OffsetXmm = 0, [double]$OffsetYmm = 0)
    $r = New-TicketRenderer $Layout $Data $Font $OffsetXmm $OffsetYmm
    $r.PrinterSettings.PrinterName = $Printer
    if (-not $r.PrinterSettings.IsValid) { throw "找不到印表機: $Printer" }
    $r.ApplyPaper()
    $r.Print()
}
