@echo off
setlocal enabledelayedexpansion

echo ==========================================
echo CANN LLM Model Deployment Script
echo ==========================================

set LOCAL_TARGET=D:\proj\cann_lm_engine\c20_7b_target
set LOCAL_DRAFT=D:\proj\cann_lm_engine\c20_7b_draft
set PACKAGE_NAME=com.hongjieliu.clawdbot
set SANDBOX_PATH=/data/app/el2/100/base/%PACKAGE_NAME%/haps/entry/files

echo Checking local model directories...
if not exist "%LOCAL_TARGET%" (
    echo ERROR: Target model directory not found: %LOCAL_TARGET%
    exit /b 1
)
if not exist "%LOCAL_DRAFT%" (
    echo ERROR: Draft model directory not found: %LOCAL_DRAFT%
    exit /b 1
)
echo Local model directories found.

echo.
echo Checking device connection...
hdc list targets >nul 2>&1
if errorlevel 1 (
    echo ERROR: No device connected. Please connect your device and try again.
    exit /b 1
)
echo Device connected.

echo.
echo Creating directories on device...
hdc shell "mkdir -p %SANDBOX_PATH%/chs_7b_target_model"
hdc shell "mkdir -p %SANDBOX_PATH%/chs_7b_draft_model"

echo.
echo ==========================================
echo Deploying Target Model (7B)...
echo ==========================================

echo Sending: SubGraph_0.weight (2.6GB, please wait...)
hdc file send "%LOCAL_TARGET%\SubGraph_0.weight" %SANDBOX_PATH%/chs_7b_target_model/

echo Sending: chs_7b_target_model.json
hdc file send "%LOCAL_TARGET%\chs_7b_target_model.json" %SANDBOX_PATH%/chs_7b_target_model/

echo Sending: chs_7b_target_model.omc
hdc file send "%LOCAL_TARGET%\chs_7b_target_model.omc" %SANDBOX_PATH%/chs_7b_target_model/

echo Sending: chs_7b_target_model.omc.loraconf
hdc file send "%LOCAL_TARGET%\chs_7b_target_model.omc.loraconf" %SANDBOX_PATH%/chs_7b_target_model/

echo Sending: chs_7b_target_model.omc.loradata
hdc file send "%LOCAL_TARGET%\chs_7b_target_model.omc.loradata" %SANDBOX_PATH%/chs_7b_target_model/

echo Sending: chs_7b_target_model.omc.quantpara
hdc file send "%LOCAL_TARGET%\chs_7b_target_model.omc.quantpara" %SANDBOX_PATH%/chs_7b_target_model/

echo Sending: chs_7b_32_1536.embedding_dequant_scale
hdc file send "%LOCAL_TARGET%\chs_7b_32_1536.embedding_dequant_scale" %SANDBOX_PATH%/chs_7b_target_model/

echo Sending: chs_7b_32_1536.embedding_weights (450MB)
hdc file send "%LOCAL_TARGET%\chs_7b_32_1536.embedding_weights" %SANDBOX_PATH%/chs_7b_target_model/

echo Sending: tokenizer.model
hdc file send "%LOCAL_TARGET%\tokenizer.model" %SANDBOX_PATH%/chs_7b_target_model/

echo.
echo ==========================================
echo Deploying Draft Model (220M)...
echo ==========================================

echo Sending: SubGraph_0.weight (50MB)
hdc file send "%LOCAL_DRAFT%\SubGraph_0.weight" %SANDBOX_PATH%/chs_7b_draft_model/

echo Sending: chs_7b_draft_model.json
hdc file send "%LOCAL_DRAFT%\chs_7b_draft_model.json" %SANDBOX_PATH%/chs_7b_draft_model/

echo Sending: chs_7b_draft_model.omc
hdc file send "%LOCAL_DRAFT%\chs_7b_draft_model.omc" %SANDBOX_PATH%/chs_7b_draft_model/

echo Sending: Pangu_7B_220M_TokenFreq.json
hdc file send "%LOCAL_DRAFT%\Pangu_7B_220M_TokenFreq.json" %SANDBOX_PATH%/chs_7b_draft_model/

echo Sending: chs_spec_model_32_4224.embedding_dequant_scale
hdc file send "%LOCAL_DRAFT%\chs_spec_model_32_4224.embedding_dequant_scale" %SANDBOX_PATH%/chs_7b_draft_model/

echo Sending: chs_spec_model_32_4224.embedding_weights (75MB)
hdc file send "%LOCAL_DRAFT%\chs_spec_model_32_4224.embedding_weights" %SANDBOX_PATH%/chs_7b_draft_model/

echo Sending: tokenizer.model
hdc file send "%LOCAL_DRAFT%\tokenizer.model" %SANDBOX_PATH%/chs_7b_draft_model/

echo.
echo ==========================================
echo Verifying deployment...
echo ==========================================

echo Target model files:
hdc shell "ls -la %SANDBOX_PATH%/chs_7b_target_model/"

echo.
echo Draft model files:
hdc shell "ls -la %SANDBOX_PATH%/chs_7b_draft_model/"

echo.
echo ==========================================
echo Deployment complete!
echo ==========================================
echo.
echo Model files deployed to:
echo   Target: %SANDBOX_PATH%/chs_7b_target_model
echo   Draft:  %SANDBOX_PATH%/chs_7b_draft_model
echo.
echo You can now use 'cann-local' provider in the app.

endlocal
