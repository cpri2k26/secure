@echo off
title Secure Chat - Setup Engine
echo ==========================================
echo       SECURE CHAT INITIAL BASE SETUP      
echo ==========================================
echo.

:: Step 1: Verify if Python is installed on system host
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

:: Step 2: Core library installation
echo [*] Upgrading pip and verifying external application libraries...
python -m pip install --upgrade pip >nul 2>&1
python -m pip install PyQt6 cryptography >nul 2>&1

:: Step 3: Extract the current version string directly from the local app.py code
set "FINAL_VERSION=0.0.0"
if exist "app.py" (
    for /f "delims=" %%i in ('python -c "import app; print(getattr(app, '__version__', '0.0.0'))" 2^>nul') do set "FINAL_VERSION=%%i"
)

:: Step 4: Overwrite/Create shortcut with current version embedded safely in Description metadata
set "STARTUP_FOLDER=%appdata%\Microsoft\Windows\Start Menu\Programs\Startup"
echo [*] Registering self-healing shortcut with hover metadata properties...

powershell -Command "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut('%STARTUP_FOLDER%\SecureChat.lnk'); $s.TargetPath = '%~dp0app.py'; $s.WorkingDirectory = '%~dp0'; $s.Description = 'SecureChat v%FINAL_VERSION%'; $s.Save()"

echo [+] System shortcut generated at: %STARTUP_FOLDER%\SecureChat.lnk
echo [+] Shortcut hover text updated to: SecureChat v%FINAL_VERSION%
echo.
echo ==========================================
echo        SETUP PROCESS FULLY COMPLETE        
echo ==========================================
