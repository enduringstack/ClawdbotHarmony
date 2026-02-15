@echo off
cd /d C:\Users\Liuho\ClawdBotHarmony
set PATH=%PATH%;C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains;C:\Program Files\Huawei\DevEco Studio\tools\ohpm\bin
echo Installing dependencies...
call ohpm install
echo Done.
