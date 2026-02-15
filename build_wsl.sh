#!/bin/bash
cd /mnt/c/Users/Liuho/ClawdBotHarmony

# Set environment
export DEVECO_SDK_HOME="/mnt/c/Program Files/Huawei/DevEco Studio/sdk/default/openharmony"
export NODE_HOME="/mnt/c/Program Files/Huawei/DevEco Studio/tools/node"
export PATH="$NODE_HOME:$PATH"
export PATH="/mnt/c/Program Files/Huawei/DevEco Studio/tools/hvigor/bin:$PATH"

echo "DEVECO_SDK_HOME: $DEVECO_SDK_HOME"
echo "NODE_HOME: $NODE_HOME"

# Run hvigor build
"/mnt/c/Program Files/Huawei/DevEco Studio/tools/node/node.exe" \
  "/mnt/c/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.js" \
  assembleHap --mode module -p product=default -p buildMode=debug
