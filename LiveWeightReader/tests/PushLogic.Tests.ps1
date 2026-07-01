$ErrorActionPreference = 'Stop'
# $PSScriptRoot is empty when this file is run via Invoke-Expression (iex) instead of as a
# real script file (e.g. when execution policy blocks direct execution); fall back to CWD,
# which is expected to be the repo root per this script's usage instructions.
$__testsRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Join-Path (Get-Location) 'LiveWeightReader\tests' }
$__pushLogicPath = Join-Path $__testsRoot '..\PushLogic.ps1'
# Dot-sourcing a physical .ps1 file is subject to execution policy even from within an
# already-iex'd context; loading its text via Invoke-Expression sidesteps that restriction
# while still defining Get-PushDecision in this scope.
iex ([IO.File]::ReadAllText($__pushLogicPath))

$fail = 0
function Check($name, $got, $want) {
  if ($got -ne $want) { Write-Host "FAIL ${name}: got=$got want=$want"; $script:fail++ }
  else { Write-Host "ok   $name" }
}

# reader 檔案過時(now-fileAt > 15) → stale
Check 'reader stale' (Get-PushDecision -State 'weighing' -StateChanged $false -LastPushEpoch 0 -FileAtEpoch 0 -NowEpoch 20) 'stale'
# 有車且檔案新鮮 → push
Check 'weighing push' (Get-PushDecision -State 'weighing' -StateChanged $false -LastPushEpoch 100 -FileAtEpoch 109 -NowEpoch 110) 'push'
# 狀態剛變(weighing→idle,推最後 0) → push
Check 'state changed push' (Get-PushDecision -State 'idle' -StateChanged $true -LastPushEpoch 100 -FileAtEpoch 109 -NowEpoch 110) 'push'
# 閒置未滿 60 秒(59.9999 < 60,-ge 未達標)→ skip
Check 'idle skip' (Get-PushDecision -State 'idle' -StateChanged $false -LastPushEpoch 100 -FileAtEpoch 159.9999 -NowEpoch 159.9999) 'skip'
# 閒置滿 60 秒(剛好達標,-ge 60 算 heartbeat)→ heartbeat
Check 'idle heartbeat' (Get-PushDecision -State 'idle' -StateChanged $false -LastPushEpoch 100 -FileAtEpoch 159 -NowEpoch 160.0001) 'heartbeat'
Check 'idle heartbeat2' (Get-PushDecision -State 'idle' -StateChanged $false -LastPushEpoch 100 -FileAtEpoch 165 -NowEpoch 165) 'heartbeat'

if ($fail -gt 0) { Write-Host "$fail FAILED"; exit 1 } else { Write-Host 'ALL PASS'; exit 0 }
