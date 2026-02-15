@echo off
cd /d C:\Users\Liuho\ClawdBotHarmony
set DEVECO_SDK_HOME=C:\Program Files\Huawei\DevEco Studio\sdk
set PATH=%PATH%;C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains
echo Building HAP...
call "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat" assembleHap --no-daemon
if %ERRORLEVEL% NEQ 0 (
    echo Build failed!
    exit /b 1
)
echo Installing to device...
hdc install entry\build\default\outputs\default\entry-default-signed.hap
echo Done!
