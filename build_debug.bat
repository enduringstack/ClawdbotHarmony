@echo off
cd /d C:\Users\Liuho\ClawdbotHarmony
set DEVECO_SDK_HOME=C:\Program Files\Huawei\DevEco Studio\sdk
set PATH=%PATH%;C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains
echo CWD:
cd
echo.
echo Building HAP with debug...
call "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat" assembleHap --no-daemon --debug 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo Build failed!
    exit /b 1
)
echo Installing to device...
hdc install entry\build\default\outputs\default\entry-default-signed.hap
echo Done!
