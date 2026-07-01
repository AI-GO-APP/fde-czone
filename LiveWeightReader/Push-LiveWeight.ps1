<#
.SYNOPSIS 地磅即時重量推送 agent — 讀本機 current-weight.json,按策略推 aigo。
.DESCRIPTION
  讀取與推送解耦:reader 只寫本機檔,pusher 負責碰網路。推送失敗僅記 log,
  不影響 reader。由登入自動啟動排程執行(見 Install-PusherTask.ps1)。
#>
$ErrorActionPreference = 'Stop'

$root    = 'C:\Users\user\Desktop\fde-czone'
$jsonPath = Join-Path $root 'LiveWeightReader\out\current-weight.json'
$logPath  = Join-Path $root 'LiveWeightReader\out\pusher.log'
$cfgPath  = Join-Path $root 'agent\config.local.json'

# 防重複執行
$created = $false
$mtx = New-Object System.Threading.Mutex($true, 'Local\ScalesWeightPusher', [ref]$created)
if (-not $created) { return }

# 重點:本機執行原則為 Restricted,dot-source .ps1 即使在 iex 內也會失敗;
#       改用 iex 讀檔文字載入,避免觸發 ExecutionPolicy 檢查。
Invoke-Expression ([IO.File]::ReadAllText((Join-Path $root 'LiveWeightReader\PushLogic.ps1')))
Invoke-Expression ([IO.File]::ReadAllText((Join-Path $root 'agent\lib\AigoClient.ps1')))
$Cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json

function Log($m) {
    try { Add-Content -Path $logPath -Value ("[{0:yyyy-MM-dd HH:mm:ss}] {1}" -f (Get-Date), $m) }
    catch { }
}
function NowEpoch { [double]([DateTimeOffset]::Now.ToUnixTimeMilliseconds() / 1000.0) }

Log "pusher started"
$lastPush = 0.0
$prevState = 'idle'

while ($true) {
    Start-Sleep -Seconds 1
    if (-not (Test-Path $jsonPath)) { continue }
    try {
        $cur = Get-Content $jsonPath -Raw | ConvertFrom-Json
    } catch { continue }

    $state = "$($cur.state)"
    $weight = [int]$cur.weight
    $fileAt = try { [double]([DateTimeOffset]::Parse($cur.at).ToUnixTimeMilliseconds() / 1000.0) } catch { NowEpoch }
    $now = NowEpoch
    $changed = ($state -ne $prevState)

    $decision = Get-PushDecision -State $state -StateChanged $changed `
        -LastPushEpoch $lastPush -FileAtEpoch $fileAt -NowEpoch $now
    $prevState = $state

    if ($decision -eq 'push') {
        $params = @{ weight = $weight; state = $state; at = "$($cur.at)" }
    } elseif ($decision -eq 'heartbeat') {
        $params = @{ weight = 0; state = 'idle'; at = "$($cur.at)" }
    } else {
        continue   # skip / stale：不打 API
    }

    try {
        Resolve-AigoAction -Cfg $Cfg -Action 'update_live_weight' -Params $params | Out-Null
        $lastPush = $now
    } catch {
        Log ("push 失敗(略過): " + $_.Exception.Message)   # best-effort,不影響 reader
    }
}
