@echo off
rem Double-clickable wrapper for compile_windows_portable.ps1.
rem Builds a portable bundle (full build: flutter clean + rebuild) and writes the ZIP to app\dist\.
rem The .ps1 derives the repository root from its own location, so the current directory does not matter.
rem A double-click cannot pass arguments; use PowerShell directly for -NoClean or -Arch arm64.

setlocal

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0compile_windows_portable.ps1"
set "EXITCODE=%ERRORLEVEL%"

echo.
if "%EXITCODE%"=="0" (
    echo Portable bundle built. Output: app\dist\LocalSend-windows-x86_64.zip
    echo Unpack it into a new empty directory and start localsend_app.exe to verify.
) else (
    echo Build FAILED with exit code %EXITCODE%. Read the messages above.
)

rem Keep the window open when launched from Explorer, otherwise errors flash by.
pause
endlocal & exit /b %EXITCODE%
