@echo off
title Secure Chat Launcher
:: --- CONFIGURATION: Point to your cloud source instead of a local IP ---
set "VERSION_URL=https://raw.githubusercontent.com/YourUsername/secure-chat-app/main/version.txt"
set "CODE_URL=https://raw.githubusercontent.com/YourUsername/secure-chat-app/main/app.py"

echo ==========================================
echo        CHECKING FOR APP UPDATES            
echo ==========================================

:: Step 1: Check internet connectivity to the update server
curl -s --max-time 3 -I "%VERSION_URL%" >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] Cloud server unreachable or offline. Running local client fallback...
    goto LAUNCH
)

:: Step 2: Download remote version stamp to temporary directory
curl -s -o "%temp%\remote_version.txt" "%VERSION_URL%"

:: Step 3: Check if local version exists at all
if not exist "version.txt" (
    echo [*] Clean installation detected...
    goto UPDATE
)

:: Step 4: Core Deduplication / Identity Resolution Check via File Compare
fc "version.txt" "%temp%\remote_version.txt" >nul 2>&1
if %errorlevel% eq 0 (
    echo [+] Application is fully up to date!
    del "%temp%\remote_version.txt"
    goto STARTUP_CHECK
)

:UPDATE
echo [!] New version detected on the cloud! Downloading release updates...
curl -s -o "app.py" "%CODE_URL%"
move /y "%temp%\remote_version.txt" "version.txt" >nul
echo [+] Update applied successfully!

:STARTUP_CHECK
set "STARTUP_FOLDER=%appdata%\Microsoft\Windows\Start Menu\Programs\Startup"
if not exist "%STARTUP_FOLDER%\SecureChat.lnk" (
    echo [*] Creating persistent startup linkage...
    powershell -Command "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut('%STARTUP_FOLDER%\SecureChat.lnk'); $s.TargetPath = '%~dp0run_chat.bat'; $s.WorkingDirectory = '%~dp0'; $s.Save()"
    echo [+] Shortcut successfully registered.
)






@echo off
title Secure Chat Setup and Launcher
echo ==========================================
echo       SECURE CHAT AUTOMATIC LAUNCHER      
echo ==========================================
echo.

:: Step 1: Check if Python is installed
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] Python is NOT installed on this computer.
    echo [*] Downloading Python 3.11 installation package...
    
    :: Uses curl (built into modern Windows) to fetch the official installer
    curl -L -o python_installer.exe https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe
    
    echo [*] Installing Python silently... Please wait about 30 seconds...
    start /wait python_installer.exe /quiet PrependPath=1 Include_pip=1
    
    echo [*] Cleaning up temporary installation files...
    del python_installer.exe
    
    :: Manually update the current command window paths so it finds the new Python instantly
    set "PATH=%PATH%;%LocalAppData%\Programs\Python\Python311;%LocalAppData%\Programs\Python\Python311\Scripts;%ProgramFiles%\Python311;%ProgramFiles%\Python311\Scripts"
    echo [+] Python installation complete!
    echo.
) else (
    echo [+] Python is already installed. Moving forward...
)

:: Step 2: Install dependencies safely using python module rules
echo [*] Checking and installing required application libraries...
python -m pip install --upgrade pip
python -m pip install PyQt6 cryptography
