<#
.SYNOPSIS
  安裝「地磅即時重量讀取」排程任務 — 登入時自動啟動 Read-LiveWeight.ps1。

.DESCRIPTION
  在 Windows 工作排程器建立一個任務,於「使用者登入」時自動啟動 reader。
  目的:對付本機偶發斷電——斷電/重開機後,使用者一登入 reader 就自動回來,
  不需人工重開。

  - 以互動式(目前使用者、Limited 權限)在使用者 session 執行
    (讀 ScalesManager 視窗必須與它同一個桌面 session)。
  - 用 IEX 讀取腳本內容執行,避免 .ps1 執行原則(ExecutionPolicy)限制。
  - 執行時間上限設為無限;若當掉則自動重試。
  - 看門狗:登入觸發器另掛「每 5 分鐘重複、無限期」。搭配任務的
    MultipleInstances=IgnoreNew 與腳本內建 mutex(同時只跑一份):
    reader 活著時,每 5 分鐘的重觸發是空操作;一旦 reader 因斷電復原
    時序、被外部結束等原因掛掉,最多 5 分鐘內排程自動把它拉回來。
    (只靠 AtLogOn + RestartCount 會在「死了卻未被判為失敗」時一直躺著。)

  重新執行本腳本會覆蓋既有任務(-Force)。
#>

$ErrorActionPreference = 'Stop'

$taskName = 'ScalesLiveWeightReader'
$script   = 'C:\Users\user\Desktop\fde-czone\LiveWeightReader\Read-LiveWeight.ps1'

$me = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name  # 例:DESKTOP-XXXX\user

$cmd = "Invoke-Expression ([IO.File]::ReadAllText('$script'))"
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
  -Argument "-NoProfile -WindowStyle Hidden -Command `"$cmd`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $me
# 看門狗:每 5 分鐘重複、無限期(借一個 -Once 觸發器的 Repetition 設定套上去)
$trigger.Repetition = (New-ScheduledTaskTrigger -Once -At '00:00' `
  -RepetitionInterval (New-TimeSpan -Minutes 5)).Repetition
$principal = New-ScheduledTaskPrincipal -UserId $me `
  -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
  -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) `
  -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
  -Principal $principal -Settings $settings -Force | Out-Null

Write-Output "Registered scheduled task: $taskName (trigger: AtLogOn)"
