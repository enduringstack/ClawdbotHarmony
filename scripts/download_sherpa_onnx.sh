#!/bin/bash
# download_sherpa_onnx.sh
# Downloads sherpa-onnx HAR package and 3D-Speaker model for voiceprint recognition.
#
# Usage: ./scripts/download_sherpa_onnx.sh
#
# Prerequisites:
#   - ohpm (OpenHarmony Package Manager) installed and in PATH
#   - curl or wget available
#
# References:
#   - https://k2-fsa.github.io/sherpa/onnx/harmony-os/
#   - https://ohpm.openharmony.cn/#/cn/detail/sherpa_onnx

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# sherpa_onnx version
SHERPA_ONNX_VERSION="1.12.1"

# 3D-Speaker model for speaker identification
MODEL_NAME="3dspeaker_speech_eres2net_base_200k_sv_zh-cn_16k-common.onnx"
MODEL_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/${MODEL_NAME}"
MODEL_DIR="${PROJECT_ROOT}/entry/src/main/resources/rawfile/voiceprint"

echo "========================================"
echo " sherpa-onnx Setup for ClawdBotHarmony"
echo "========================================"
echo ""

# Step 1: Install sherpa_onnx HAR via ohpm
echo "[1/3] Installing sherpa_onnx@${SHERPA_ONNX_VERSION} via ohpm..."
if command -v ohpm &> /dev/null; then
    cd "$PROJECT_ROOT"
    ohpm install sherpa_onnx@${SHERPA_ONNX_VERSION}
    echo "  -> sherpa_onnx installed successfully."
else
    echo "  WARNING: ohpm not found in PATH."
    echo "  Please install ohpm or add it to PATH, then run:"
    echo "    cd ${PROJECT_ROOT} && ohpm install sherpa_onnx@${SHERPA_ONNX_VERSION}"
    echo ""
    echo "  Alternatively, add to entry/oh-package.json5:"
    echo '    "dependencies": { "sherpa_onnx": "'${SHERPA_ONNX_VERSION}'" }'
    echo ""
fi

# Step 2: Download 3D-Speaker model
echo ""
echo "[2/3] Downloading 3D-Speaker model (~38MB)..."
mkdir -p "$MODEL_DIR"

if [ -f "${MODEL_DIR}/${MODEL_NAME}" ]; then
    echo "  -> Model already exists at ${MODEL_DIR}/${MODEL_NAME}"
    echo "  -> Skipping download. Delete the file to re-download."
else
    echo "  -> Downloading from: ${MODEL_URL}"
    if command -v curl &> /dev/null; then
        curl -L --progress-bar -o "${MODEL_DIR}/${MODEL_NAME}" "$MODEL_URL"
    elif command -v wget &> /dev/null; then
        wget --show-progress -O "${MODEL_DIR}/${MODEL_NAME}" "$MODEL_URL"
    else
        echo "  ERROR: Neither curl nor wget found. Please download manually:"
        echo "  URL: ${MODEL_URL}"
        echo "  Save to: ${MODEL_DIR}/${MODEL_NAME}"
        exit 1
    fi
    echo "  -> Model downloaded successfully."
fi

# Step 3: Verify
echo ""
echo "[3/3] Verifying setup..."

if [ -f "${MODEL_DIR}/${MODEL_NAME}" ]; then
    MODEL_SIZE=$(wc -c < "${MODEL_DIR}/${MODEL_NAME}" 2>/dev/null || echo "unknown")
    echo "  -> Model: ${MODEL_DIR}/${MODEL_NAME} (${MODEL_SIZE} bytes)"
else
    echo "  WARNING: Model file not found."
fi

echo ""
echo "========================================"
echo " Setup complete!"
echo "========================================"
echo ""
echo "Next steps:"
echo "  1. Open the project in DevEco Studio"
echo "  2. Sync the ohpm dependencies"
echo "  3. Build and run the project"
echo ""
echo "Model location: ${MODEL_DIR}/${MODEL_NAME}"
echo "The model will be bundled in the HAP as a rawfile resource."
