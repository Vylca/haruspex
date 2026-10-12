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

apps="$HOME/.local/share/applications"
icons="$HOME/.local/share/icons/hicolor"
rm -rf "$dest"
mkdir -p "$dest" "$HOME/.local/bin" "$apps" "$icons/256x256/apps"
cp -r "$bundle"/. "$dest"/
ln -sf "$dest/orgpad" "$HOME/.local/bin/orgpad"

icon="$dest/data/flutter_assets/assets/icon/orgpad.png"
if [ -f "$icon" ]; then
  cp "$icon" "$icons/256x256/apps/orgpad.png"
  gtk-update-icon-cache -q -t "$icons" >/dev/null 2>&1 || true
fi

# Named after the app id so docks and window switchers find the icon.
rm -f "$apps/orgpad.desktop"
cat > "$apps/dev.orgpad.orgpad.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=OrgPad
Comment=Plain text editor built on Org mode
Exec=$dest/orgpad %F
Icon=orgpad
Terminal=false
Categories=Utility;TextEditor;
MimeType=text/org;text/x-org;text/plain;
StartupWMClass=orgpad
EOF

update-desktop-database "$apps" >/dev/null 2>&1 || true
echo "Installed. Start it from your app menu or run: orgpad [file.org]"
