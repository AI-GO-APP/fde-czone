# WeighTicketPrint — 三聯地磅單列印（薪榮環保 / czone）

自寫的列印程式，**取代舊系統 ScalesManager 的「印磅單」這一步**。一張橫向紙印三聯，
套印「公司抬頭＋過磅數值」到 EPSON LQ-690CII 點陣印表機。

## 設計決策（重要）
1. **不引用、不執行 FastReport 任何 DLL。** `.frx` 只當「版面座標藍圖」用 `System.Xml` 解析，
   不載入 FastReport（其商業授權綁原開發商，第三方另寫程式引用有授權風險）。
2. **不手刻 ESC/P2 文字指令。** 這台點陣機無內建中文字庫，純文字模式印不出中文。
3. **走 Windows GDI 系統列印**（`System.Drawing.Printing`）：自己畫版面 → 印到
   `EPSON LQ-690CII` 驅動 → 中文交給 Windows 字型、由驅動轉點陣。座標以實體 mm 定位。
   零安裝，只用內建 .NET Framework。

## 目錄
```
WeighTicketPrint/
├─ src/
│  ├─ Logic.cs       純邏輯：座標換算 / 資料格式化 / .frx XML 解析 / 三聯平移（無繪圖、無 FastReport）
│  └─ Renderer.cs    GDI 渲染：System.Drawing.Printing，畫到印表機 / PDF / 點陣圖
├─ tests/
│  └─ Run-Tests.ps1  單元測試（零框架、零安裝）：座標換算、日期/時間格式、KG、中文代換、三聯平移
├─ template/
│  └─ rptWeight廣達昌.frx   版面藍圖（唯讀解析用；抬頭為「薪榮環保」）
├─ out/              產出（preview.pdf / preview.png）
├─ Print-Ticket.ps1  主程式
├─ coordinates.md    解析出的三聯座標表
└─ README.md
```

## 使用
> 本機 PowerShell 執行原則為 Restricted、預設編碼為 Big5。所有 .ps1/.cs 已存為 **UTF-8 with BOM**，
> 故可用 `-File` 直接執行；若原則擋檔，改用下方「ScriptBlock 包裝」方式（不更動系統設定）。

產生 PDF 預覽（預設，**省紙**）：
```
powershell -NoProfile -File Print-Ticket.ps1
```
產生 PNG 預覽：
```
powershell -NoProfile -File Print-Ticket.ps1 -Mode png
```
跑單元測試：
```
powershell -NoProfile -File tests\Run-Tests.ps1
```
若執行原則擋住 `-File`（不改系統設定的替代法）：
```
powershell -NoProfile -Command "& ([ScriptBlock]::Create((Get-Content -Raw -Encoding UTF8 '.\Print-Ticket.ps1')))"
```

真實列印（**人工確認 PDF 對齊後才做**）：
```
powershell -NoProfile -File Print-Ticket.ps1 -Mode printer -ConfirmRealPrint
```

## 省紙鐵則
- 預設 `-Mode pdf`，輸出 `out/preview.pdf` 給人看。
- `-Mode printer` 一定要再加 `-ConfirmRealPrint`，否則程式拒印。**版面對齊確認 OK 前，不印真紙。**

## 假資料
目前 `Print-Ticket.ps1` 內為寫死的測試資料（客戶=測試環保、車號=KEP-2758、毛重 14540、空重 8200、淨重 6340…）。
真實資料之後由上游帶入（替換 `$data` 字典即可）。

## 待校準
- PDF/PNG 對齊確認後，於真紙上微調：可在 `Renderer.DrawAll` 或座標來源加全域 X/Y 偏移量，對齊預印格。
- `.frx` 標示 `PaperSource=261`（連續紙/牽引），真實列印時的進紙來源待現場確認。
