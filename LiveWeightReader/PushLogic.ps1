# 純決策函式:給定狀態與時間,決定要不要推 aigo。無副作用,便於測試。
function Get-PushDecision {
    param(
        [Parameter(Mandatory)][string]$State,
        [Parameter(Mandatory)][bool]$StateChanged,
        [Parameter(Mandatory)][double]$LastPushEpoch,
        [Parameter(Mandatory)][double]$FileAtEpoch,
        [Parameter(Mandatory)][double]$NowEpoch,
        [double]$HeartbeatSec = 60,
        [double]$StaleSec = 15
    )
    if (($NowEpoch - $FileAtEpoch) -gt $StaleSec) { return 'stale' }   # reader 疑似掛了 → 停推
    if ($State -eq 'weighing') { return 'push' }                       # 有車 → 每秒推
    if ($StateChanged) { return 'push' }                              # 剛歸零 → 推最後一筆 0
    if (($NowEpoch - $LastPushEpoch) -ge $HeartbeatSec) { return 'heartbeat' }  # 閒置心跳
    return 'skip'
}
