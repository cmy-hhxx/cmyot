#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

MODE="diff"
STRICT_FLAG=""
EXTRA_TESTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quick)
      MODE="quick"
      shift
      ;;
    --all)
      MODE="all"
      shift
      ;;
    --strict)
      STRICT_FLAG="--strict"
      shift
      ;;
    --tests)
      shift
      if [[ $# -eq 0 ]]; then
        echo "[verify] --tests requires a test suite name (e.g. Round40AppleCentersTests)" >&2
        exit 2
      fi
      EXTRA_TESTS+=("-only-testing:Tests/$1")
      shift
      ;;
    -h|--help)
      cat <<'EOF'
CotEditor Pre-Delivery Verification Gate
Usage:
  ./Scripts/verify.sh [--quick | --all] [--strict] [--tests <SuiteName> ...]

Modes:
  (default)   Run static formal verification (--diff + --self-test), WebUI typecheck if changed,
              and xcodebuild test (FormalVerificationTests + any --tests suites).
  --quick     Run only --self-test and static formal verification (--diff) (< 1s).
  --all       Audit entire repository statically with Scripts/formal-verify.py --all.
  --strict    Fail on warnings as well as errors in static formal verification.
  --tests X   Include Tests/X in the xcodebuild test run (repeatable).
EOF
      exit 0
      ;;
    *)
      echo "[verify] Unknown flag: $1" >&2
      exit 2
      ;;
  esac
done

echo "==> [1/3] Running Formal Verification Rule Self-Test & Static Gate"
python3 "$ROOT_DIR/Scripts/formal-verify.py" --self-test
if [[ "$MODE" == "all" ]]; then
  python3 "$ROOT_DIR/Scripts/formal-verify.py" --all $STRICT_FLAG
  exit 0
fi

python3 "$ROOT_DIR/Scripts/formal-verify.py" --diff $STRICT_FLAG

if [[ "$MODE" == "quick" ]]; then
  echo "==> Quick formal verification gate passed."
  exit 0
fi

echo "==> [2/3] Checking WebUI TypeScript types (if modified)"
if git status --porcelain -- WebUI/ 2>/dev/null | grep -q .; then
  if command -v npm >/dev/null 2>&1 || [[ -x "/Users/cmy/.nvm/versions/node/v24.14.1/bin/npm" ]]; then
    PATH="/Users/cmy/.nvm/versions/node/v24.14.1/bin:$PATH" npm --prefix "$ROOT_DIR/WebUI/beautiful-agent" run typecheck
  fi
else
  echo "    (WebUI unchanged; skipping typecheck)"
fi

echo "==> [3/3] Running Xcode Formal Verification & Regression Tests"
TEST_ARGS=(
  -project CotEditor.xcodeproj
  -scheme CotEditor
  -destination 'platform=macOS'
  -skipPackagePluginValidation
  -parallel-testing-enabled NO
  -only-testing:Tests/FormalVerificationTests
)
if [[ ${#EXTRA_TESTS[@]} -gt 0 ]]; then
  TEST_ARGS+=("${EXTRA_TESTS[@]}")
fi

xcodebuild test "${TEST_ARGS[@]}"
echo "==> Formal verification & test gate succeeded."
