@echo off
setlocal
set "SITE=%~dp0docs\index.html"
if not exist "%SITE%" (
	echo Site file not found: %SITE%
	pause
	exit /b 1
)
start "" "%SITE%"
endlocal
