#!/usr/bin/env bash
set -uo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FRONTEND="$ROOT/../frontend"
LOG="$ROOT/verification-results.txt"
: > "$LOG"

run() {
  echo "=== $1 ===" | tee -a "$LOG"
  shift
  if "$@" >> "$LOG" 2>&1; then
    echo "PASS: $1" | tee -a "$LOG"
    return 0
  else
    echo "FAIL: $1 (exit $?)" | tee -a "$LOG"
    return 1
  fi
}

cd "$ROOT"
run "forge build" forge build
run "forge build --sizes" forge build --sizes
run "forge test" forge test
run "slither" slither . --config-file slither.config.json

cd "$FRONTEND"
run "node export-abis" node "$ROOT/scripts/export-abis.mjs"
run "tsc --noEmit" npx tsc --noEmit
run "eslint" npm run lint
run "next build" npm run build

echo "=== DONE ===" | tee -a "$LOG"
