#!/usr/bin/env bash
# Builds OrgPad as a native Linux app.
#   ./build.sh            build only
#   ./build.sh --install  build, then install to ~/.local with a menu entry
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK not found. Install it first:"
  echo "  git clone https://github.com/flutter/flutter.git -b stable ~/flutter"
  echo "  export PATH=\"\$HOME/flutter/bin:\$PATH\""
  exit 1
fi

missing=()
for tool in clang cmake ninja pkg-config; do
  command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
pkg-config --exists gtk+-3.0 2>/dev/null || missing+=("gtk3")
if [ ${#missing[@]} -gt 0 ]; then
  echo "Missing build dependencies: ${missing[*]}"
  if command -v pacman >/dev/null 2>&1; then
    echo "Install with: sudo pacman -S --needed base-devel clang cmake ninja gtk3"
  else
    echo "On Debian/Ubuntu: sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev"
  fi
  exit 1
fi

flutter config --enable-linux-desktop >/dev/null

# Generate the native Linux runner the first time (existing files are kept).
if [ ! -d linux ]; then
  flutter create --platforms=linux --project-name orgpad --org dev.orgpad .
fi

flutter pub get
flutter build linux --release

bundle=$(find build/linux -type d -path '*/release/bundle' | head -n 1)
echo
echo "Built: $bundle/orgpad"

if [ "${1:-}" = "--install" ]; then
  ./install.sh "$bundle"
fi
