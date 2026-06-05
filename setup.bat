@echo off
title Secure Chat Setup Engine
:: --- CONFIGURATION: GitHub Repository Asset Anchors ---
set "VERSION_URL=https://raw.githubusercontent.com/cpri2k26/secure/main/version.txt"
set "CODE_URL=https://raw.githubusercontent.com/cpri2k26/secure/main/app.py"

echo ==========================================
echo       SECURE CHAT INITIAL BASE SETUP      
echo ==========================================
echo.

:: Step 1: Pre-flight network validation check
ping -n 1 8.8.8.8 >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] Network connection offline. Setup cannot proceed without cloud access.
    pause
    exit /b
)

:: Step 2: Verify if Python is installed on system host
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] Python is NOT installed on this computer.
    echo [*] Downloading Python 3.11 installation package...
    
    curl -L -o "%temp%\python_installer.exe" https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe
    
    echo [*] Installing Python silently... Please wait about 30 seconds...
    start /wait "" "%temp%\python_installer.exe" /quiet PrependPath=1 Include_pip=1
    del "%temp%\python_installer.exe"
    
    set "PATH=%PATH%;%LocalAppData%\Programs\Python\Python311;%LocalAppData%\Programs\Python\Python311\Scripts;%ProgramFiles%\Python311;%ProgramFiles%\Python311\Scripts"
    echo [+] Python installation complete!
) else (
    echo [+] Python framework verified.
)

:: Step 3: Core library installation
echo [*] Upgrading pip and verifying external application libraries...
python -m pip install --upgrade pip >nul 2>&1
python -m pip install PyQt6 cryptography >nul 2>&1

echo.
echo ==========================================
echo         CLOUD VERSION SYNCHRONIZATION      
echo ==========================================

:: Step 4: Extract the local app version if the code exists
set "LOCAL_VERSION=0.0.0"
if exist "app.py" (
    for /f "delims=" %%i in ('python -c "import app; print(getattr(app, '__version__', '0.0.0'))" 2^>nul') do set "LOCAL_VERSION=%%i"
)

:: Step 5: Fetch latest production version stamp from GitHub channel
curl -s -o "%temp%\cloud_version.txt" "%VERSION_URL%"
if %errorlevel% neq 0 (
    echo [!] Cloud update repository unreachable. Maintaining current local state...
    goto PERSISTENCE_GEN
)

set /p CLOUD_VERSION=<"%temp%\cloud_version.txt"
del "%temp%\cloud_version.txt"

echo [+] Local Cache Version:  %LOCAL_VERSION%
echo [+] GitHub Target Version: %CLOUD_VERSION%

:: Step 6: Code compilation sync logic
if "%LOCAL_VERSION%"=="%CLOUD_VERSION%" (
    echo [+] System files match the latest release configuration.
    goto PERSISTENCE_GEN
)

:DOWNLOAD_UPDATE
echo [!] Version mismatch or clean deployment needed. Fetching latest app code...
curl -s -o "app.py" "%CODE_URL%"
echo [+] Asset synchronization successfully finished!

:PERSISTENCE_GEN
:: Re-extract the true current version from the finalized file
for /f "delims=" %%i in ('python -c "import app; print(getattr(app, '__version__', '0.0.0'))" 2^>nul') do set "FINAL_VERSION=%%i"
if "%FINAL_VERSION%"=="" set "FINAL_VERSION=%LOCAL_VERSION%"

:: Step 7: Overwrite/Create shortcut with current version embedded safely in Description and Hover Metadata
set "STARTUP_FOLDER=%appdata%\Microsoft\Windows\Start Menu\Programs\Startup"
echo [*] Registering self-healing shortcut with hover metadata properties...

:: This PowerShell snippet assigns the clean 'SecureChat.lnk' file name on disk, 
:: but injects the dynamic string text into the Description metadata property.
powershell -Command "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut('%STARTUP_FOLDER%\SecureChat.lnk'); $s.TargetPath = '%~dp0run_chat.bat'; $s.WorkingDirectory = '%~dp0'; $s.Description = 'SecureChat v%FINAL_VERSION%'; $s.Save()"

echo [+] System shortcut generated at: %STARTUP_FOLDER%\SecureChat.lnk
echo [+] Shortcut hover text updated to: SecureChat v%FINAL_VERSION%
echo.
echo ==========================================
echo        SETUP PROCESS FULLY COMPLETE        
echo ==========================================
pause
