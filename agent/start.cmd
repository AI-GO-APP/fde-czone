@echo off
rem 啟動磅單列印現場 agent (繞過 Restricted 執行原則 + UTF-8)
chcp 65001 >nul
set "AGENT_DIR=%~dp0"
powershell -NoProfile -Command "& ([ScriptBlock]::Create((Get-Content -Raw -Encoding UTF8 '%~dp0Start-Agent.ps1')))"
pause
