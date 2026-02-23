@echo off
REM ClawdbotHarmony build script for pre-commit hook
set "DEVECO_SDK_HOME=C:\Program Files\Huawei\DevEco Studio"
set "HVIGORW=%DEVECO_SDK_HOME%\tools\hvigor\bin\hvigorw.bat"

if "%1"=="build-only" (
    call "%HVIGORW%" assembleHap 2>&1
) else (
    call "%HVIGORW%" assembleHap 2>&1
)
