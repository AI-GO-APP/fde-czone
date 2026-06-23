@echo off
rem Start the weigh-ticket print agent (bypass Restricted policy + UTF-8 console).
rem If the agent is already running -> just open the browser.
rem Otherwise start the agent (it opens the browser when the listener is ready).
rem Keep this window open = service running; close it to stop.
rem NOTE: keep this file ASCII-only. Chinese here breaks cmd parsing on cp950 (set fails).
chcp 65001 >nul
set "AGENT_DIR=%~dp0"

rem 1) detect if already running (port 9180)
powershell -NoProfile -Command "try { Invoke-RestMethod http://localhost:9180/health -TimeoutSec 1 | Out-Null; exit 0 } catch { exit 1 }"
if %errorlevel%==0 (
  echo Agent already running, opening browser...
  start "" http://localhost:9180/
  goto :eof
)

rem 2) start agent; flag tells agent to open the browser when the listener is ready
set "AGENT_OPEN_BROWSER=1"
echo Starting print agent... (do NOT close this window; closing stops the service)
powershell -NoProfile -Command "& ([ScriptBlock]::Create((Get-Content -Raw -Encoding UTF8 '%~dp0Start-Agent.ps1')))"
pause
