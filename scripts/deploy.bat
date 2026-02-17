@echo off
cd /d C:\Users\Liuho\ClawdBotHarmony
set HDC="C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
echo Installing HAP...
%HDC% -t 192.168.1.69:39915 install -r entry\build\default\outputs\default\entry-default-signed.hap
echo.
echo Starting app...
%HDC% -t 192.168.1.69:39915 shell aa start -a EntryAbility -b com.hongjieliu.clawdbot
