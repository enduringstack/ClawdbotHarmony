#!/bin/bash
# Functional test: Version consistency across 4 locations
set -e

RED='\033[31m'
GREEN='\033[32m'
CYAN='\033[36m'
NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

pass_count=0
fail_count=0
failures=""

pass() {
  echo -e "    ${GREEN}\xE2\x9C\x93${NC} $1"
  pass_count=$((pass_count + 1))
}

fail() {
  echo -e "    ${RED}\xE2\x9C\x97 $1${NC}"
  echo -e "      ${RED}$2${NC}"
  fail_count=$((fail_count + 1))
  failures="${failures}\n  ${RED}$1: $2${NC}"
}

echo -e "\n${CYAN}  Version Consistency${NC}"

# --- Extract versions from 4 locations ---

# 1. AppScope/app.json5 -> versionName
APP_JSON="${PROJECT_ROOT}/AppScope/app.json5"
if [ ! -f "$APP_JSON" ]; then
  fail "app.json5 exists" "File not found: $APP_JSON"
  V_APP=""
else
  V_APP=$(grep -oP '"versionName"\s*:\s*"\K[^"]+' "$APP_JSON" 2>/dev/null || echo "")
fi

# 1b. versionCode
V_CODE=$(grep -oP '"versionCode"\s*:\s*\K[0-9]+' "$APP_JSON" 2>/dev/null || echo "")

# 2. NodeRuntime.ets -> APP_VERSION
NODERUNTIME="${PROJECT_ROOT}/entry/src/main/ets/service/gateway/NodeRuntime.ets"
if [ ! -f "$NODERUNTIME" ]; then
  fail "NodeRuntime.ets exists" "File not found: $NODERUNTIME"
  V_NODE=""
else
  V_NODE=$(grep -oP "const APP_VERSION\s*=\s*'\K[^']+" "$NODERUNTIME" 2>/dev/null || echo "")
fi

# 3. Index.ets -> Text('vX.Y.Z')
INDEX="${PROJECT_ROOT}/entry/src/main/ets/pages/Index.ets"
if [ ! -f "$INDEX" ]; then
  fail "Index.ets exists" "File not found: $INDEX"
  V_INDEX=""
else
  V_INDEX=$(grep -oP "Text\('v\K[0-9]+\.[0-9]+\.[0-9]+" "$INDEX" 2>/dev/null || echo "")
fi

# 4. SettingsPage.ets -> version display
SETTINGS="${PROJECT_ROOT}/entry/src/main/ets/pages/SettingsPage.ets"
if [ ! -f "$SETTINGS" ]; then
  fail "SettingsPage.ets exists" "File not found: $SETTINGS"
  V_SETTINGS=""
else
  V_SETTINGS=$(grep -oP "version.*'\K[0-9]+\.[0-9]+\.[0-9]+" "$SETTINGS" 2>/dev/null || echo "")
fi

# --- Validate no version is empty ---

if [ -n "$V_APP" ]; then
  pass "app.json5 versionName not empty: $V_APP"
else
  fail "app.json5 versionName not empty" "extracted empty value"
fi

if [ -n "$V_NODE" ]; then
  pass "NodeRuntime APP_VERSION not empty: $V_NODE"
else
  fail "NodeRuntime APP_VERSION not empty" "extracted empty value"
fi

if [ -n "$V_INDEX" ]; then
  pass "Index.ets version not empty: $V_INDEX"
else
  fail "Index.ets version not empty" "extracted empty value"
fi

if [ -n "$V_SETTINGS" ]; then
  pass "SettingsPage.ets version not empty: $V_SETTINGS"
else
  fail "SettingsPage.ets version not empty" "extracted empty value"
fi

# --- Validate semver format (X.Y.Z) ---

SEMVER_RE='^[0-9]+\.[0-9]+\.[0-9]+$'

if [[ "$V_APP" =~ $SEMVER_RE ]]; then
  pass "app.json5 version is valid semver"
else
  fail "app.json5 version is valid semver" "got: '$V_APP'"
fi

if [[ "$V_NODE" =~ $SEMVER_RE ]]; then
  pass "NodeRuntime version is valid semver"
else
  fail "NodeRuntime version is valid semver" "got: '$V_NODE'"
fi

if [[ "$V_INDEX" =~ $SEMVER_RE ]]; then
  pass "Index.ets version is valid semver"
else
  fail "Index.ets version is valid semver" "got: '$V_INDEX'"
fi

if [[ "$V_SETTINGS" =~ $SEMVER_RE ]]; then
  pass "SettingsPage.ets version is valid semver"
else
  fail "SettingsPage.ets version is valid semver" "got: '$V_SETTINGS'"
fi

# --- Validate versionCode is a valid number ---

if [[ "$V_CODE" =~ ^[0-9]+$ ]] && [ "$V_CODE" -gt 0 ]; then
  pass "app.json5 versionCode is valid number: $V_CODE"
else
  fail "app.json5 versionCode is valid number" "got: '$V_CODE'"
fi

# --- Validate all 4 versions match ---

if [ "$V_APP" = "$V_NODE" ]; then
  pass "app.json5 == NodeRuntime ($V_APP)"
else
  fail "app.json5 == NodeRuntime" "app.json5=$V_APP, NodeRuntime=$V_NODE"
fi

if [ "$V_APP" = "$V_INDEX" ]; then
  pass "app.json5 == Index.ets ($V_APP)"
else
  fail "app.json5 == Index.ets" "app.json5=$V_APP, Index=$V_INDEX"
fi

if [ "$V_APP" = "$V_SETTINGS" ]; then
  pass "app.json5 == SettingsPage ($V_APP)"
else
  fail "app.json5 == SettingsPage" "app.json5=$V_APP, Settings=$V_SETTINGS"
fi

if [ "$V_NODE" = "$V_INDEX" ] && [ "$V_INDEX" = "$V_SETTINGS" ]; then
  pass "all 4 locations consistent: $V_APP"
else
  fail "all 4 locations consistent" "app=$V_APP node=$V_NODE index=$V_INDEX settings=$V_SETTINGS"
fi

# --- Summary ---

echo ""
if [ $fail_count -eq 0 ]; then
  echo -e "${GREEN}  $pass_count passing${NC}"
else
  echo -e "${GREEN}  $pass_count passing${NC}"
  echo -e "${RED}  $fail_count failing${NC}"
  echo -e "$failures"
fi
echo ""

exit $fail_count
