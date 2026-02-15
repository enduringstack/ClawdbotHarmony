#!/bin/bash
# ============================================
# ClawdbotHarmony Test Suite Runner
# Runs all unit, functional, and scenario tests
# ============================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TOTAL_FILES=0
PASSED_FILES=0
FAILED_FILES=0
FAILED_LIST=()

run_js_test() {
  local file="$1"
  local rel="${file#$PROJECT_ROOT/}"
  TOTAL_FILES=$((TOTAL_FILES + 1))
  if node "$file" 2>&1; then
    PASSED_FILES=$((PASSED_FILES + 1))
  else
    FAILED_FILES=$((FAILED_FILES + 1))
    FAILED_LIST+=("$rel")
  fi
}

run_sh_test() {
  local file="$1"
  local rel="${file#$PROJECT_ROOT/}"
  TOTAL_FILES=$((TOTAL_FILES + 1))
  if bash "$file" 2>&1; then
    PASSED_FILES=$((PASSED_FILES + 1))
  else
    FAILED_FILES=$((FAILED_FILES + 1))
    FAILED_LIST+=("$rel")
  fi
}

echo ""
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}  ClawdbotHarmony Full Test Suite${NC}"
echo -e "${CYAN}================================================${NC}"

# --- Unit Tests ---
echo ""
echo -e "${YELLOW}━━━ Unit Tests ━━━${NC}"
for f in "$SCRIPT_DIR"/unit/test_*.js; do
  [ -f "$f" ] && run_js_test "$f"
done

# --- Functional Tests ---
echo ""
echo -e "${YELLOW}━━━ Functional Tests ━━━${NC}"
for f in "$SCRIPT_DIR"/functional/test_*.js; do
  [ -f "$f" ] && run_js_test "$f"
done
for f in "$SCRIPT_DIR"/functional/test_*.sh; do
  [ -f "$f" ] && run_sh_test "$f"
done

# --- Scenario Tests ---
echo ""
echo -e "${YELLOW}━━━ Scenario Tests ━━━${NC}"
for f in "$SCRIPT_DIR"/scenario/test_*.js; do
  [ -f "$f" ] && run_js_test "$f"
done

# --- Summary ---
echo ""
echo -e "${CYAN}================================================${NC}"
if [ $FAILED_FILES -eq 0 ]; then
  echo -e "${GREEN}  All $TOTAL_FILES test files passed!${NC}"
else
  echo -e "${GREEN}  $PASSED_FILES/$TOTAL_FILES test files passed${NC}"
  echo -e "${RED}  $FAILED_FILES test file(s) failed:${NC}"
  for f in "${FAILED_LIST[@]}"; do
    echo -e "    ${RED}- $f${NC}"
  done
fi
echo -e "${CYAN}================================================${NC}"
echo ""

exit $FAILED_FILES
