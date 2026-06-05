@echo off
title Secure Chat - Regex Cloud Sync Engine
:: --- CONFIGURATION: Point to your cloud script asset target ---
set "CODE_URL=https://raw.githubusercontent.com/cpri2k26/secure/main/app.py"

echo ==========================================
echo         CLOUD VERSION SYNCHRONIZATION      
echo ==========================================
echo.

:: Step 1: Pre-flight network validation check
ping -n 1 8.8.8.8 >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] Network connection offline. Update check aborted.
    pause
    exit /b
)

:: Step 2: Extract local app version string variable safely
set "LOCAL_VERSION=0.0.0"
if exist "app.py" (
    for /f "delims=" %%i in ('python -c "import app; print(getattr(app, '__version__', '0.0.0'))" 2^>nul') do set "LOCAL_VERSION=%%i"
)

echo [*] Contacting production node to parse remote file streams...

:: Step 3: Use PowerShell Regex to read app.py directly from GitHub and extract the version string
for /f "delims=" %%i in ('powershell -Command "$web = Invoke-WebRequest -Uri '%CODE_URL%' -UseBasicParsing; if($web.Content -match '__version__\s*=\s*[\x22\x27]([^\x22\x27]+)[\x22\x27]'){ $Matches[1] } else { '0.0.0' }" 2^>nul') do set "CLOUD_VERSION=%%i"

:: Fallback if network stream reading failed completely
if "%CLOUD_VERSION%"=="" set "CLOUD_VERSION=0.0.0"

echo [+] Local Cache Version:   %LOCAL_VERSION%
echo [+] GitHub Remote Version: %CLOUD_VERSION%
echo.

:: Step 4: Identity verification and comparison check
if "%LOCAL_VERSION%"=="%CLOUD_VERSION%" (
    echo [+] System matches the latest release configuration! No update needed.
    pause
    exit /b
)

echo [!] Version divergence found! Pulling complete update stream...
curl -s -o "app.py" "%CODE_URL%"
echo [+] Asset synchronization successfully finished!
echo.

:: Step 5: Trigger setup wrapper to re-write Windows shortcuts and hover entries
if exist "setup.bat" (
    echo [*] Calling setup.bat to update your startup shortcuts and hover names...
    call setup.bat
) else (
    echo [!] Warning: setup.bat not found in this folder. Shortcut metadata was not refreshed.
)

pause
