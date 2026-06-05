@echo off
title Secure Chat - Manual Cloud Sync Engine
:: --- CONFIGURATION: GitHub Repository Asset Anchors ---
set "VERSION_URL=https://raw.githubusercontent.com/cpri2k26/secure/main/version.txt"
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

:: Step 2: Extract local app version string variable
set "LOCAL_VERSION=0.0.0"
if exist "app.py" (
    for /f "delims=" %%i in ('python -c "import app; print(getattr(app, '__version__', '0.0.0'))" 2^>nul') do set "LOCAL_VERSION=%%i"
)

:: Step 3: Fetch latest production version stamp from GitHub
curl -s -o "%temp%\cloud_version.txt" "%VERSION_URL%"
if %errorlevel% neq 0 (
    echo [!] Cloud update repository unreachable. Maintaining current state...
    pause
    exit /b
)

set /p CLOUD_VERSION=<"%temp%\cloud_version.txt"
del "%temp%\cloud_version.txt"

echo [+] Local Cache Version:   %LOCAL_VERSION%
echo [+] GitHub Target Version:  %CLOUD_VERSION%
echo.

:: Step 4: Compare versions
if "%LOCAL_VERSION%"=="%CLOUD_VERSION%" (
    echo [+] System matches the latest release configuration! No update needed.
    pause
    exit /b
)

echo [!] New version update discovered! Fetching clean software assets...
curl -s -o "app.py" "%CODE_URL%"
echo [+] Asset synchronization successfully finished!
echo.

:: Step 5: Automatically trigger setup.bat to refresh dependencies and rewrite the hover description
if exist "setup.bat" (
    echo [*] Calling setup.bat to update your startup shortcuts and hover names...
    call setup.bat
) else (
    echo [!] Warning: setup.bat not found in this folder. Shortcut hover metadata was not refreshed.
)

pause
