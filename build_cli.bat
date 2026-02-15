@echo off
cd /d C:\Users\Liuho\ClawdBotHarmony
set PATH=%PATH%;C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin
set PATH=%PATH%;C:\Program Files\Huawei\DevEco Studio\tools\node
call hvigorw assembleHap --mode module -p product=default -p buildMode=debug
