#!/usr/bin/env bash
# Package the Linux release bundle as a .deb:   scripts/make_deb.sh      (run scripts/release.sh linux first)
# Installs to /opt/todo-app, adds /usr/bin/todo-app and a launcher entry with the app icon.
# NOTE: if the bundle was built with the Desktop OAuth client (--dart-define-from-file), that client secret is inside
# the binary, so don't publish the resulting .deb. A bundle built without it installs fine but can't sign in.
set -euo pipefail
cd "$(dirname "$0")/.."

bundle=build/linux/x64/release/bundle
[[ -x "$bundle/todo" ]] || { echo "error: $bundle not found. Run: DEFINES=<oauth json> scripts/release.sh linux" >&2; exit 2; }

version=$(sed -nE 's/^version: *([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' pubspec.yaml)
pkg=todo-app
root=build/deb/$pkg
out=build/${pkg}_${version}_amd64.deb

rm -rf build/deb && mkdir -p "$root/DEBIAN" "$root/opt/$pkg" "$root/usr/bin" "$root/usr/share/applications"
cp -r "$bundle"/. "$root/opt/$pkg/"
ln -s /opt/$pkg/todo "$root/usr/bin/$pkg"

# Same id as the GTK application (linux/CMakeLists.txt) so the shell matches the window to this launcher and its icon.
cat > "$root/usr/share/applications/com.chaaru.todo.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=TODO
Comment=A simple task list that follows you from your phone to your desk
Exec=/opt/$pkg/todo
Icon=com.chaaru.todo
Terminal=false
Categories=Utility;Office;
StartupWMClass=com.chaaru.todo
DESKTOP

for size in 48 64 128 256 512; do
  dir="$root/usr/share/icons/hicolor/${size}x${size}/apps"
  mkdir -p "$dir"
  python3 - "$size" "$dir/com.chaaru.todo.png" <<'PY'
import sys
from PIL import Image
Image.open("assets/logo/logo.png").convert("RGBA").resize((int(sys.argv[1]),) * 2, Image.LANCZOS).save(sys.argv[2])
PY
done

size_kb=$(du -sk "$root" | cut -f1)
cat > "$root/DEBIAN/control" <<CONTROL
Package: $pkg
Version: $version
Section: utils
Priority: optional
Architecture: amd64
Installed-Size: $size_kb
Depends: libgtk-3-0, libglib2.0-0, libsecret-1-0, libjsoncpp25
Maintainer: TODO app <noreply@example.com>
Description: A simple task list that follows you from your phone to your desk
 Cross-platform TODO app with Google sign-in and live sync.
CONTROL

cat > "$root/DEBIAN/postinst" <<'POST'
#!/bin/sh
set -e
command -v update-desktop-database >/dev/null && update-desktop-database -q /usr/share/applications || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -t /usr/share/icons/hicolor || true
POST
chmod 0755 "$root/DEBIAN/postinst"
find "$root" -type d -exec chmod 0755 {} +
find "$root" -type f ! -perm -u+x -exec chmod 0644 {} +   # no group-writable files

dpkg-deb --build --root-owner-group "$root" "$out" >/dev/null
echo "-> $out"
echo "   install:   sudo apt install ./$out"
echo "   uninstall: sudo apt remove $pkg"
