@echo off
REM Build script for PDF Importer SketchUp Extension (Windows)
REM Creates a pdf_importer.rbz file ready for installation
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "BUILD_DIR=%SCRIPT_DIR%\build"
set "OUTPUT_FILE=%SCRIPT_DIR%\pdf_importer.rbz"

echo === PDF Importer Build Script ===
echo.

REM Clean previous build
if exist "%BUILD_DIR%" (
    rmdir /s /q "%BUILD_DIR%"
)
if exist "%OUTPUT_FILE%" (
    del /f /q "%OUTPUT_FILE%"
)

REM Create build directory
mkdir "%BUILD_DIR%"

REM Copy registrar file
echo Copying registrar file...
copy "%SCRIPT_DIR%\pdf_importer.rb" "%BUILD_DIR%\" >nul

REM Copy support folder
echo Copying extension files...
xcopy "%SCRIPT_DIR%\pdf_importer" "%BUILD_DIR%\pdf_importer\" /s /e /q /i >nul

REM Remove unwanted files
for /r "%BUILD_DIR%" %%d in (__pycache__) do (
    if exist "%%d" rmdir /s /q "%%d"
)
for /r "%BUILD_DIR%" %%f in (*.pyc) do (
    if exist "%%f" del /f /q "%%f"
)
for /r "%BUILD_DIR%" %%f in (Thumbs.db) do (
    if exist "%%f" del /f /q "%%f"
)

REM Create the .rbz (which is just a .zip)
echo Creating .rbz package...
where tar >nul 2>&1
if %errorlevel% equ 0 (
    REM Use tar (available on Windows 10 1803+)
    pushd "%BUILD_DIR%"
    tar -a -cf "%OUTPUT_FILE%" pdf_importer.rb pdf_importer
    popd
) else (
    REM Fallback to PowerShell Compress-Archive
    powershell -NoProfile -Command ^
        "Compress-Archive -Path '%BUILD_DIR%\pdf_importer.rb','%BUILD_DIR%\pdf_importer' -DestinationPath '%OUTPUT_FILE%' -Force"
)

REM Clean up build directory
rmdir /s /q "%BUILD_DIR%"

REM Show results
echo.
echo === Build Complete ===
echo Output: %OUTPUT_FILE%
for %%A in ("%OUTPUT_FILE%") do echo Size: %%~zA bytes
echo.
echo To install:
echo   1. Open SketchUp
echo   2. Extensions ^> Extension Manager
echo   3. Install Extension
echo   4. Select: %OUTPUT_FILE%

endlocal
