#!/usr/bin/env bash
# Build a release artifact:  scripts/release.sh <android|linux|deb|windows|macos|web>
# Desktop sign-in needs the Desktop OAuth client. Keep it OUT of the repo: put these two keys in a JSON file anywhere
# outside the project and point at it, e.g.   DEFINES=~/secrets/desktop_oauth.json scripts/release.sh linux
#   {"GOOGLE_DESKTOP_CLIENT_ID": "...", "GOOGLE_DESKTOP_CLIENT_SECRET": "..."}
set -euo pipefail
cd "$(dirname "$0")/.."

target="${1:-}"
defines=()
if [[ -n "${DEFINES:-}" ]]; then defines=(--dart-define-from-file="$DEFINES"); fi

need_os() { echo "error: '$target' can only be built on $1 (Flutter can't cross-compile desktop apps)." >&2; exit 2; }

case "$target" in
  android)
    # Signed with android/key.properties when it exists (see android/key.properties.example).
    flutter build apk --release
    echo "-> build/app/outputs/flutter-apk/app-release.apk  (sideload: adb install -r <file>)"
    ;;
  web)
    # The web build must never contain the desktop OAuth secret, so DEFINES is deliberately not passed.
    flutter build web --release
    echo "-> build/web  (deployed to Netlify: see README)"
    ;;
  linux)
    [[ "$(uname -s)" == "Linux" ]] || need_os Linux
    flutter build linux --release "${defines[@]}"
    out=build/linux/x64/release
    tar -C "$out" -czf build/todo-linux-x64.tar.gz bundle
    echo "-> build/todo-linux-x64.tar.gz"
    ;;
  deb)
    [[ "$(uname -s)" == "Linux" ]] || need_os Linux
    flutter build linux --release "${defines[@]}"
    scripts/make_deb.sh
    ;;
  windows)
    [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* || "$(uname -s)" == CYGWIN* ]] || need_os Windows
    flutter build windows --release "${defines[@]}"
    echo "-> build/windows/x64/runner/Release  (zip this folder)"
    ;;
  macos)
    [[ "$(uname -s)" == "Darwin" ]] || need_os macOS
    flutter build macos --release
    echo "-> build/macos/Build/Products/Release/todo.app"
    ;;
  *)
    echo "usage: $0 <android|linux|deb|windows|macos|web>" >&2
    exit 1
    ;;
esac
