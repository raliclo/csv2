@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 > nul
:: module_api_win.bat -- initialise MSVC, then return to module_api.zsh
::
:: This file contains bootstrap only. The source selection, module build,
:: client build and assertions remain in module_api.zsh so there is one
:: verification on every platform.
::
:: Comments are English-only because non-ASCII batch comments have corrupted
:: parsing of later lines in this environment.

cd /d "%~dp0.."

where swiftc.exe > nul 2>&1
if errorlevel 1 (
    echo [FAIL] swiftc.exe not on PATH. Install the Swift toolchain for Windows.
    exit /b 1
)

where zsh.exe > nul 2>&1
if errorlevel 1 (
    echo [FAIL] zsh.exe not on PATH.
    exit /b 1
)

set "_vswhere=C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
where cl.exe > nul 2>&1
if errorlevel 1 (
    if not exist "%_vswhere%" (
        echo [FAIL] Neither cl.exe nor vswhere.exe found. Install Visual Studio
        echo        with the "Desktop development with C++" workload.
        exit /b 1
    )
    set "_vsroot="
    for /f "usebackq delims=" %%I in (`"%_vswhere%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "_vsroot=%%I"
    if not defined _vsroot (
        echo [FAIL] MSVC C++ tools not found by vswhere.
        exit /b 1
    )
    if not exist "!_vsroot!\VC\Auxiliary\Build\vcvars64.bat" (
        echo [FAIL] vcvars64.bat not found under "!_vsroot!"
        exit /b 1
    )
    call "!_vsroot!\VC\Auxiliary\Build\vcvars64.bat" > nul
    if errorlevel 1 (
        echo [FAIL] vcvars64.bat failed.
        exit /b 1
    )
)

set "CSV2_MSVC_READY=1"
set "MSYS2_ARG_CONV_EXCL="
zsh.exe "%~dp0module_api.zsh"
exit /b %errorlevel%
