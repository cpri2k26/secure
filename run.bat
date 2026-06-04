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
