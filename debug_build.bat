@echo off
cd /d C:\Users\Liuho\ClawdBotHarmony
echo Current directory: %CD%
echo Checking entry directory...
dir entry
echo.
echo Starting build...
set DEVECO_SDK_HOME=C:\Program Files\Huawei\DevEco Studio\sdk
set PATH=%PATH%;C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains
call "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat" assembleHap --no-daemon --debug
