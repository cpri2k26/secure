@echo off
title Secure Chat Launcher
:: --- CONFIGURATION: Point to your cloud source instead of a local IP ---
set "VERSION_URL=https://raw.githubusercontent.com/cpri2k26/secure/main/version.txt"
set "CODE_URL=https://raw.githubusercontent.com/cpri2k26/secure/main/app.py"


@echo off
title Secure Chat Dependencies Setup
echo ==========================================
echo      Secure Chat Dependencies Setup      
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
echo -----------------------------------------------------------------------



echo ==========================================
echo       INITIALIZING APP ENVIRONMENT        
echo ==========================================

:: Step 1: Pre-flight network validation check
ping -n 1 8.8.8.8 >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] Network connection offline. Skipping update validation...
    goto LAUNCH_FALLBACK
)

:: Step 2: Ensure core dependencies are present
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] Python framework missing. Running background download...
    curl -L -o "%temp%\py_setup.exe" "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe"
    start /wait "" "%temp%\py_setup.exe" /quiet PrependPath=1 Include_pip=1
    del "%temp%\py_setup.exe"
    set "PATH=%PATH%;%LocalAppData%\Programs\Python\Python311;%LocalAppData%\Programs\Python\Python311\Scripts;%ProgramFiles%\Python311;%ProgramFiles%\Python311\Scripts"
)
python -m pip install PyQt6 cryptography >nul 2>&1

:: Step 3: Extract the current version string directly from the app.py code
if not exist "app.py" (
    echo [!] Local application cache missing. Requesting complete deployment...
    goto DOWNLOAD_UPDATE
)

:: Run a single line python instruction to grab the string variable safely
for /f "delims=" %%i in ('python -c "import app; print(getattr(app, '__version__', '0.0.0'))" 2^>nul') do set "LOCAL_VERSION=%%i"

:: If python evaluation failed completely, default version to force a safe rebuild
if "%LOCAL_VERSION%"=="" set "LOCAL_VERSION=0.0.0"

:: Step 4: Download the text version signature from your GitHub repository
curl -s -o "%temp%\cloud_version.txt" "%VERSION_URL%"
if %errorlevel% neq 0 (
    echo [!] Cloud update registry unreachable. Moving to launch...
    goto PERSISTENCE_CHECK
)

set /p CLOUD_VERSION=<"%temp%\cloud_version.txt"
del "%temp%\cloud_version.txt"

echo [+] Local Version:  %LOCAL_VERSION%
echo [+] Cloud Version:  %CLOUD_VERSION%

:: Step 5: String match comparison logic
if "%LOCAL_VERSION%"=="%CLOUD_VERSION%" (
    echo [+] System matches the latest release build.
    goto PERSISTENCE_CHECK
)

:DOWNLOAD_UPDATE
echo [!] New version update discovered! Fetching clean software assets...
curl -s -o "app.py" "%CODE_URL%"
echo [+] Download complete. Script code upgraded successfully.

:PERSISTENCE_CHECK
:: Step 6: Verify and create Windows Startup link
set "STARTUP_FOLDER=%appdata%\Microsoft\Windows\Start Menu\Programs\Startup"
if not exist "%STARTUP_FOLDER%\SecureChat.lnk" (
    echo [*] Creating persistent desktop configuration links...
    powershell -Command "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut('%STARTUP_FOLDER%\SecureChat.lnk'); $s.TargetPath = '%~dp0run_chat.bat'; $s.WorkingDirectory = '%~dp0'; $s.Save()"
    echo [+] Shortcut added to Startup folder!
)

:LAUNCH_FALLBACK
echo.
echo ==========================================
echo          BOOTING CHAT APPLICATION          
echo ==========================================






