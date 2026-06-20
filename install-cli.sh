#!/usr/bin/env bash
#
# install-cli.sh — install the `vsswift` command onto your PATH.
#
# Usage:
#   ./install-cli.sh [BIN_DIR]
#
# Symlinks the repo's `vsswift` launcher into BIN_DIR (default: /usr/local/bin).
# After installation, run `vsswift .` in any folder to open it in the editor.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="${1:-/usr/local/bin}"
LAUNCHER="$ROOT/vsswift"

chmod +x "$LAUNCHER"

if ! mkdir -p "$BIN_DIR" 2>/dev/null; then
  echo "install-cli: cannot create $BIN_DIR — try: sudo ./install-cli.sh" >&2
  exit 1
fi

if ! ln -sf "$LAUNCHER" "$BIN_DIR/vsswift" 2>/dev/null; then
  echo "install-cli: cannot write to $BIN_DIR — try: sudo ./install-cli.sh" >&2
  echo "             or choose a writable dir, e.g.: ./install-cli.sh \"\$HOME/.local/bin\"" >&2
  exit 1
fi

echo "✅ Installed: $BIN_DIR/vsswift -> $LAUNCHER"
case ":$PATH:" in
  *":$BIN_DIR:"*) echo "   '$BIN_DIR' is on your PATH. Try:  vsswift ." ;;
  *) echo "   ⚠️  '$BIN_DIR' is not on your PATH. Add it to your shell profile:";
     echo "       export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac
