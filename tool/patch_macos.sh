#!/usr/bin/env bash
# Adjusts the macOS runner made by `flutter create`: app name, bundle id,
# icon, and no app sandbox (Haruspex opens and saves files anywhere, like
# any editor outside the App Store). Safe to run again.
set -euo pipefail
d="${1:-macos}"
cfg="$d/Runner/Configs/AppInfo.xcconfig"
perl -pi -e 's/^PRODUCT_NAME = .*/PRODUCT_NAME = Haruspex/' "$cfg"
perl -pi -e 's/^PRODUCT_BUNDLE_IDENTIFIER = .*/PRODUCT_BUNDLE_IDENTIFIER = io.github.vylca.haruspex/' "$cfg"
perl -pi -e 's/^PRODUCT_COPYRIGHT = .*/PRODUCT_COPYRIGHT = Haruspex/' "$cfg"
for e in DebugProfile Release; do
  perl -0pi -e 's#(<key>com\.apple\.security\.app-sandbox</key>\s*)<true/>#$1<false/>#' "$d/Runner/$e.entitlements"
done
cp assets/icon/macos/app_icon_*.png "$d/Runner/Assets.xcassets/AppIcon.appiconset/"
# The window, plus files opened from the Finder handed to Dart.
cp tool/macos/MainFlutterWindow.swift "$d/Runner/MainFlutterWindow.swift"
# Files Haruspex can open from Finder ("Open With").
plist="$d/Runner/Info.plist"
if ! grep -q 'CFBundleDocumentTypes' "$plist"; then
  perl -0pi -e 's#</dict>\s*</plist>#\t<key>CFBundleDocumentTypes</key>
\t<array>
\t\t<dict>
\t\t\t<key>CFBundleTypeName</key>
\t\t\t<string>Org document</string>
\t\t\t<key>CFBundleTypeRole</key>
\t\t\t<string>Editor</string>
\t\t\t<key>LSHandlerRank</key>
\t\t\t<string>Alternate</string>
\t\t\t<key>CFBundleTypeExtensions</key>
\t\t\t<array>
\t\t\t\t<string>org</string>
\t\t\t\t<string>txt</string>
\t\t\t</array>
\t\t</dict>
\t</array>
</dict>
</plist>#' "$plist"
fi
