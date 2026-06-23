@echo off
rem 啟動磅單列印現場 agent (繞過 Restricted 執行原則 + UTF-8)
rem 行為: 若 agent 已在跑 -> 直接開瀏覽器; 否則啟動 agent (agent 就緒時自己開瀏覽器)。
rem 此視窗開著 = 服務運作中; 關閉視窗即停止。
chcp 65001 >nul
set "AGENT_DIR=%~dp0"

rem 1) 偵測是否已在執行 (9180)
powershell -NoProfile -Command "try { Invoke-RestMethod http://localhost:9180/health -TimeoutSec 1 | Out-Null; exit 0 } catch { exit 1 }"
if %errorlevel%==0 (
  echo agent 已在執行,開啟瀏覽器...
  start "" http://localhost:9180/
  goto :eof
)

rem 2) 啟動 agent; 設旗標讓 agent listener 就緒時自行開瀏覽器 (時機最準)
set "AGENT_OPEN_BROWSER=1"
echo 啟動磅單列印 agent... (請勿關閉此視窗;關閉即停止服務)
powershell -NoProfile -Command "& ([ScriptBlock]::Create((Get-Content -Raw -Encoding UTF8 '%~dp0Start-Agent.ps1')))"
pause
