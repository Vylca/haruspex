#!/usr/bin/env bash
# Installs a built Haruspex bundle for the current user:
#   ~/.local/share/haruspex/        the app
#   ~/.local/bin/haruspex           launcher
#   ~/.local/share/applications/    menu entry, opens .org files
set -euo pipefail
cd "$(dirname "$0")"
id=io.github.vylca.haruspex

if [ -n "${1:-}" ]; then
  bundle="$1"
elif [ -x ./haruspex ] && [ -d ./lib ] && [ -d ./data ]; then
  # Running from an unpacked download: the app is right here.
  bundle="$(pwd)"
else
  bundle="$(find build/linux -type d -path '*/release/bundle' 2>/dev/null | head -n 1)"
fi
if [ -z "$bundle" ] || [ ! -x "$bundle/haruspex" ]; then
  echo "No build found. Run ./build.sh first."
  exit 1
fi

dest="$HOME/.local/share/haruspex"
if [ "$(cd "$bundle" && pwd)" = "$dest" ]; then
  echo "Already installed in $dest"
  exit 0
fi

apps="$HOME/.local/share/applications"
icons="$HOME/.local/share/icons/hicolor"

# Remove the install from before the rename (OrgPad).
rm -rf "$HOME/.local/share/orgpad"
if [ -L "$HOME/.local/bin/orgpad" ]; then rm -f "$HOME/.local/bin/orgpad"; fi
rm -f "$apps/orgpad.desktop" "$apps/dev.orgpad.orgpad.desktop" "$icons/256x256/apps/orgpad.png"

rm -rf "$dest"
mkdir -p "$dest" "$HOME/.local/bin" "$apps" "$icons/256x256/apps"
cp -r "$bundle"/. "$dest"/
ln -sf "$dest/haruspex" "$HOME/.local/bin/haruspex"

# The icon is named after the app id. Earlier versions used "haruspex",
# which desktops may have cached with the old picture.
icon="$dest/data/flutter_assets/assets/icon"
rm -f "$icons/256x256/apps/haruspex.png" "$icons/scalable/apps/haruspex.svg"
if [ -f "$icon/haruspex.png" ]; then
  cp "$icon/haruspex.png" "$icons/256x256/apps/$id.png"
fi
if [ -f "$icon/haruspex.svg" ]; then
  mkdir -p "$icons/scalable/apps"
  cp "$icon/haruspex.svg" "$icons/scalable/apps/$id.svg"
fi
touch "$icons"
gtk-update-icon-cache -f -q -t "$icons" >/dev/null 2>&1 || true
# KDE keeps its own icon cache.
rm -f "$HOME/.cache/icon-cache.kcache"

# Named after the app id so docks and window switchers find the icon.
cat > "$apps/$id.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Haruspex
Comment=Plain text editor built on Org mode
Exec=$dest/haruspex %F
Icon=$id
Terminal=false
Categories=Utility;TextEditor;
MimeType=text/org;text/x-org;text/plain;
StartupWMClass=$id
EOF

update-desktop-database "$apps" >/dev/null 2>&1 || true
for tool in kbuildsycoca6 kbuildsycoca5; do
  if command -v "$tool" >/dev/null 2>&1; then "$tool" >/dev/null 2>&1 || true; break; fi
done
xdg-desktop-menu forceupdate >/dev/null 2>&1 || true
echo "Installed. Start it from your app menu or run: haruspex [file.org]"
