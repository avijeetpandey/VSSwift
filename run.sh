#!/usr/bin/env bash
#
# run.sh — Build and launch VSSwift with a single command.
#
# Usage:
#   ./run.sh                 Build (release) and launch the editor
#   ./run.sh --debug         Build in debug mode and launch
#   ./run.sh --build-only    Build without launching
#   ./run.sh --test          Build and run all package test suites
#   ./run.sh --clean         Remove build artifacts, then build and launch
#   ./run.sh -h | --help     Show this help
#
set -euo pipefail

cd "$(dirname "$0")"

# The local environment injects git config that breaks SwiftPM remote dependency
# resolution (swift-syntax). Neutralize it for every swift invocation.
export GIT_CONFIG_COUNT=0

CONFIG="release"
ACTION="run"

for arg in "$@"; do
  case "$arg" in
    --debug)      CONFIG="debug" ;;
    --release)    CONFIG="release" ;;
    --build-only) ACTION="build" ;;
    --test)       ACTION="test" ;;
    --clean)      ACTION="clean" ;;
    -h|--help)
      sed -n '3,12p' "$0" | sed 's/^#\{1,\} \{0,1\}//; s/^#//'
      exit 0 ;;
    *)
      echo "Unknown option: $arg" >&2
      echo "Run './run.sh --help' for usage." >&2
      exit 1 ;;
  esac
done

bold() { printf "\033[1m%s\033[0m\n" "$1"; }

if [ "$ACTION" = "clean" ]; then
  bold "🧹  Cleaning build artifacts…"
  rm -rf .build
  ACTION="run"
fi

if [ "$ACTION" = "test" ]; then
  bold "🧪  Running all VSSwift test suites…"
  FAILED=0
  for pkg in Core Engine LSP Syntax Workspace Git; do
    bold "── VSSwift${pkg} ──"
    if ( cd "Packages/VSSwift${pkg}" && swift run "VSSwift${pkg}Tests" ); then
      :
    else
      FAILED=1
    fi
  done
  [ "$FAILED" -eq 0 ] && bold "✅  All suites passed." || { bold "❌  Some suites failed."; exit 1; }
  exit 0
fi

bold "🔨  Building VSSwift (${CONFIG})…"
swift build -c "$CONFIG"

if [ "$ACTION" = "build" ]; then
  bold "✅  Build complete."
  exit 0
fi

BIN="$(swift build -c "$CONFIG" --show-bin-path 2>/dev/null | tail -1)/VSSwift"
if [ ! -x "$BIN" ]; then
  BIN=".build/${CONFIG}/VSSwift"
fi

bold "🚀  Launching VSSwift…"
exec "$BIN"
