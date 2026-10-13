#!/usr/bin/env bash
# Adjusts the Linux runner made by `flutter create`: window title, window
# icon and the color shown before the first frame. Safe to run again.
set -euo pipefail
f="${1:-linux/runner/my_application.cc}"
sed -i 's/\(_set_title([a-z_]*, \)"haruspex")/\1"Haruspex")/' "$f"
if ! grep -q 'haruspex_set_icon' "$f"; then
  # The icon installed by install.sh (named after the app id), and the one in
  # the bundle, which also works when the app is not installed.
  awk '
    /^static void my_application_activate\(/ && !done {
      print "// Window icon: the installed theme icon, then the picture in the bundle."
      print "static void haruspex_set_icon(GtkWindow* window) {"
      print "  gtk_window_set_icon_name(window, \"io.github.vylca.haruspex\");"
      print "  g_autofree gchar* exe = g_file_read_link(\"/proc/self/exe\", nullptr);"
      print "  if (exe == nullptr) return;"
      print "  g_autofree gchar* dir = g_path_get_dirname(exe);"
      print "  g_autofree gchar* icon ="
      print "      g_build_filename(dir, \"data\", \"flutter_assets\", \"assets\", \"icon\", \"haruspex.png\", nullptr);"
      print "  if (g_file_test(icon, G_FILE_TEST_EXISTS)) gtk_window_set_icon_from_file(window, icon, nullptr);"
      print "}"
      print ""
      done = 1
    }
    { print }
  ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  sed -i 's/^\([[:space:]]*\)gtk_window_set_default_size(window, \(.*\));/&\n\1haruspex_set_icon(window);/' "$f"
fi
sed -i 's/gdk_rgba_parse(&background_color, "#000000");/gdk_rgba_parse(\&background_color, "#0F0E0C");/' "$f"
