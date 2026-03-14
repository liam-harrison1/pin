#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "Launching DeskPins menu bar app..."
echo "If it starts correctly, you should see a \"Pins\" item in the macOS menu bar."
echo "Press Ctrl+C in this terminal to stop it."

exec swift run DeskPinsMenuBarApp
