#!/usr/bin/env bash
# Installs a built OrgPad bundle for the current user:
#   ~/.local/share/orgpad/          the app
#   ~/.local/bin/orgpad             launcher
#   ~/.local/share/applications/    menu entry, opens .org files
set -euo pipefail
cd "$(dirname "$0")"

if [ -n "${1:-}" ]; then
  bundle="$1"
elif [ -x ./orgpad ] && [ -d ./lib ] && [ -d ./data ]; then
  # Running from an unpacked download: the app is right here.
  bundle="$(pwd)"
else
  bundle="$(find build/linux -type d -path '*/release/bundle' 2>/dev/null | head -n 1)"
fi
if [ -z "$bundle" ] || [ ! -x "$bundle/orgpad" ]; then
  echo "No build found. Run ./build.sh first."
  exit 1
fi

dest="$HOME/.local/share/orgpad"
if [ "$(cd "$bundle" && pwd)" = "$dest" ]; then
  echo "Already installed in $dest"
  exit 0
fi

rm -rf "$dest"
mkdir -p "$dest" "$HOME/.local/bin" "$HOME/.local/share/applications"
cp -r "$bundle"/. "$dest"/
ln -sf "$dest/orgpad" "$HOME/.local/bin/orgpad"

cat > "$HOME/.local/share/applications/orgpad.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=OrgPad
Comment=Plain text editor built on Org mode
Exec=$dest/orgpad %F
Icon=accessories-text-editor
Terminal=false
Categories=Utility;TextEditor;
MimeType=text/org;text/x-org;text/plain;
EOF

update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
echo "Installed. Start it from your app menu or run: orgpad [file.org]"
