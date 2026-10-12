#!/usr/bin/env bash
# Adjusts the Linux runner made by `flutter create`: window title, window
# icon and the color shown before the first frame. Safe to run again.
set -euo pipefail
f="${1:-linux/runner/my_application.cc}"
sed -i 's/\(_set_title([a-z_]*, \)"haruspex")/\1"Haruspex")/' "$f"
if ! grep -q 'gtk_window_set_icon_name' "$f"; then
  sed -i 's/^\([[:space:]]*\)gtk_window_set_default_size(window, \(.*\));/&\n\1gtk_window_set_icon_name(window, "haruspex");/' "$f"
fi
sed -i 's/gdk_rgba_parse(&background_color, "#000000");/gdk_rgba_parse(\&background_color, "#0F0E0C");/' "$f"
