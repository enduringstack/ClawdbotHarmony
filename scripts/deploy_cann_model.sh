#!/bin/bash
# deploy_cann_model.sh - Deploy CANN LLM model files to device
# Usage: ./deploy_cann_model.sh [device_ip]

set -e

# Model directories on local machine
LOCAL_TARGET_MODEL="D:/proj/cann_lm_engine/c20_7b_target"
LOCAL_DRAFT_MODEL="D:/proj/cann_lm_engine/c20_7b_draft"

# Target sandbox path on device
DEVICE_SANDBOX="/data/app/el2/100/base/com.hongjieliu.clawdbot/haps/entry/files"

# Device model directories
DEVICE_TARGET_MODEL="${DEVICE_SANDBOX}/chs_7b_target_model"
DEVICE_DRAFT_MODEL="${DEVICE_SANDBOX}/chs_7b_draft_model"

echo "=========================================="
echo "CANN LLM Model Deployment Script"
echo "=========================================="

# Check if local model directories exist
if [ ! -d "$LOCAL_TARGET_MODEL" ]; then
    echo "ERROR: Target model directory not found: $LOCAL_TARGET_MODEL"
    echo "Please download the model files first."
    exit 1
fi

if [ ! -d "$LOCAL_DRAFT_MODEL" ]; then
    echo "ERROR: Draft model directory not found: $LOCAL_DRAFT_MODEL"
    echo "Please download the model files first."
    exit 1
fi

echo "Local model directories found:"
echo "  Target: $LOCAL_TARGET_MODEL"
echo "  Draft:  $LOCAL_DRAFT_MODEL"

# Check if device is connected
echo ""
echo "Checking device connection..."
if ! hdc list targets 2>/dev/null | grep -q "."; then
    echo "ERROR: No device connected. Please connect your device and try again."
    exit 1
fi
echo "Device connected."

# Create directories on device
echo ""
echo "Creating directories on device..."
hdc shell "mkdir -p ${DEVICE_TARGET_MODEL}"
hdc shell "mkdir -p ${DEVICE_DRAFT_MODEL}"
echo "Directories created."

# Deploy target model files
echo ""
echo "=========================================="
echo "Deploying Target Model (7B)..."
echo "=========================================="

TARGET_FILES=(
    "SubGraph_0.weight"
    "chs_7b_target_model.json"
    "chs_7b_target_model.omc"
    "chs_7b_target_model.omc.loraconf"
    "chs_7b_target_model.omc.loradata"
    "chs_7b_target_model.omc.quantpara"
    "chs_7b_32_1536.embedding_dequant_scale"
    "chs_7b_32_1536.embedding_weights"
    "tokenizer.model"
)

for file in "${TARGET_FILES[@]}"; do
    local_path="${LOCAL_TARGET_MODEL}/${file}"
    if [ -f "$local_path" ]; then
        echo "Sending: $file"
        hdc file send "$local_path" "${DEVICE_TARGET_MODEL}/"
    else
        echo "WARNING: File not found: $file"
    fi
done

# Deploy draft model files
echo ""
echo "=========================================="
echo "Deploying Draft Model (220M)..."
echo "=========================================="

DRAFT_FILES=(
    "SubGraph_0.weight"
    "chs_7b_draft_model.json"
    "chs_7b_draft_model.omc"
    "Pangu_7B_220M_TokenFreq.json"
    "chs_spec_model_32_4224.embedding_dequant_scale"
    "chs_spec_model_32_4224.embedding_weights"
    "tokenizer.model"
)

for file in "${DRAFT_FILES[@]}"; do
    local_path="${LOCAL_DRAFT_MODEL}/${file}"
    if [ -f "$local_path" ]; then
        echo "Sending: $file"
        hdc file send "$local_path" "${DEVICE_DRAFT_MODEL}/"
    else
        echo "WARNING: File not found: $file"
    fi
done

# Verify deployment
echo ""
echo "=========================================="
echo "Verifying deployment..."
echo "=========================================="

echo "Target model files:"
hdc shell "ls -la ${DEVICE_TARGET_MODEL}/"

echo ""
echo "Draft model files:"
hdc shell "ls -la ${DEVICE_DRAFT_MODEL}/"

echo ""
echo "=========================================="
echo "Deployment complete!"
echo "=========================================="
echo ""
echo "Model files deployed to:"
echo "  Target: ${DEVICE_TARGET_MODEL}"
echo "  Draft:  ${DEVICE_DRAFT_MODEL}"
echo ""
echo "You can now use 'cann-local' provider in the app."
