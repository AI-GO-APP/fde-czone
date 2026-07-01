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
$principal = New-ScheduledTaskPrincipal -UserId $me `
  -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
  -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) `
  -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
  -Principal $principal -Settings $settings -Force | Out-Null

Write-Output "Registered scheduled task: $taskName (trigger: AtLogOn)"
