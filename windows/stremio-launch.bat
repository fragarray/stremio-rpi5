@echo off
:: Stremio Launcher for Windows
:: Starts the DualSubtitles addon server, then launches Stremio.
:: Place this file in the same folder as stremio.exe

setlocal
cd /d "%~dp0"

set STREMIO_DIR=%~dp0
set RUNTIME=%STREMIO_DIR%stremio-runtime.exe
set SERVER_JS=%STREMIO_DIR%server.js
set ADDON_DIR=%STREMIO_DIR%DualSubtitles
set ADDON_INDEX=%ADDON_DIR%\index.js
set STREMIO_EXE=%STREMIO_DIR%stremio.exe

echo =========================================
echo  Stremio Launcher (with DualSubtitles)
echo =========================================

:: Check that stremio.exe exists
if not exist "%STREMIO_EXE%" (
    echo ERROR: stremio.exe not found in %STREMIO_DIR%
    pause
    exit /b 1
)

:: Check for Node.js runtime (bundled or system)
set NODE_BIN=
if exist "%RUNTIME%" (
    set NODE_BIN=%RUNTIME%
) else (
    where node >nul 2>&1 && set NODE_BIN=node
)

if "%NODE_BIN%"=="" (
    echo WARNING: Node.js runtime not found.
    echo          server.js and DualSubtitles addon will not start.
    echo          Install Node.js from https://nodejs.org or use the bundled runtime.
    goto :start_shell
)

:: Start DualSubtitles addon in background (port 7000)
if exist "%ADDON_INDEX%" (
    echo Starting DualSubtitles addon on port 7000...
    start "DualSubtitles Addon" /min cmd /c "%NODE_BIN% %ADDON_INDEX% > "%TEMP%\stremio-addon.log" 2>&1"
    :: Give it a moment to initialize
    timeout /t 2 /nobreak >nul
    echo DualSubtitles addon started.
    echo To install in Stremio: Settings ^> Addons ^> http://127.0.0.1:7000/manifest.json
) else (
    echo NOTE: DualSubtitles addon not found, skipping.
)

:start_shell
echo Starting Stremio...
start "" "%STREMIO_EXE%" %*

endlocal
