<# 建立 pusher 登入自動啟動排程 ScalesLiveWeightPusher(比照 reader,見 Install-WeightReaderTask.ps1)。#>
$ErrorActionPreference = 'Stop'
$taskName = 'ScalesLiveWeightPusher'
$script   = 'C:\Users\user\Desktop\fde-czone\LiveWeightReader\Push-LiveWeight.ps1'
$me = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

$cmd = "Invoke-Expression ([IO.File]::ReadAllText('$script'))"
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
  -Argument "-NoProfile -WindowStyle Hidden -Command `"$cmd`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $me
# 看門狗:每 5 分鐘重複、無限期(比照 reader,見 Install-WeightReaderTask.ps1)
$trigger.Repetition = (New-ScheduledTaskTrigger -Once -At '00:00' `
  -RepetitionInterval (New-TimeSpan -Minutes 5)).Repetition
$principal = New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
  -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) `
  -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
  -Principal $principal -Settings $settings -Force | Out-Null
Write-Output "Registered scheduled task: $taskName (trigger: AtLogOn)"
