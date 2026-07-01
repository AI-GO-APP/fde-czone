# LiveWeightReader — 地磅即時重量讀取 agent

讀取地磅管理系統(ScalesManager)畫面上**即時跳動的磅重**,作為推送到 aigo /
網頁即時看板的資料來源。

> 與 `WeighTicketPrint/`(磅單列印 agent)是兩支獨立、職責不同的 agent:
> - `WeighTicketPrint/` — 把**完成的磅單**列印出來
> - `LiveWeightReader/` — 讀取**當下即時的重量數字**(本資料夾)

## 運作方式

- 以 Win32 `WM_GETTEXT` **唯讀**方式讀取 ScalesManager 顯示重量的文字控制項。
  讀到的就是畫面上顯示的同一份文字(非 OCR、非猜測)。
- **自動定位**重量格:找出「曾達 ≥300kg、且會隨磅秤跳動的數字 STATIC」。
  ScalesManager 重開後控制項 handle 會變,程式會自動重新定位,不寫死 handle。
- **只讀不寫**:不送任何輸入給 ScalesManager,不影響地磅正常運作。
- 資源極輕(~75MB RAM、CPU 近 0),每 300ms 取樣一次。

## 檔案

| 檔案 | 用途 |
|------|------|
| `Read-LiveWeight.ps1` | reader 本體(常駐讀取 + 記 log) |
| `Install-WeightReaderTask.ps1` | 建立「登入自動啟動」排程任務 |
| `out/weight-reader.log` | 執行紀錄(已 gitignore,不入版控) |

## 安裝 / 啟動

```powershell
# 建立排程任務(登入時自動啟動,對付偶發斷電)
powershell -NoProfile -Command "iex ([IO.File]::ReadAllText('LiveWeightReader\Install-WeightReaderTask.ps1'))"

# 立即啟動一次(不必等下次登入)
Start-ScheduledTask -TaskName ScalesLiveWeightReader
```

## 現況

- ✅ 已驗證:能自動定位重量格、穩定讀出即時跳動數字(2026-06-30 實測多趟過磅)。
- ⏭️ 下一步:在此基礎上加入「推送即時重量到 aigo」+ 網頁即時看板。

## 備註

- 本機有偶發斷電問題,故一定要用「登入自動啟動」排程,斷電重開後才會自己回來。
- 排程以互動式在使用者 session 執行(讀視窗需與 ScalesManager 同桌面 session)。
