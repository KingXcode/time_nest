#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
cd -- "${SCRIPT_DIR}/.."
if [[ "$(uname -s)" != Darwin ]]; then
  printf '%s\n' 'The macOS app must be built on a Mac with Xcode.' >&2
  exit 1
fi
if [[ -n "${FLUTTER_BIN:-}" ]]; then
  flutter_command=("${FLUTTER_BIN}")
else
  flutter_command=(fvm flutter)
fi
# Native package versions use pubspec, independent of Pages deployment counts.
release_version="$(WEB_RELEASE_SEQUENCE=0 node tool/release_version.mjs)"
"${flutter_command[@]}" build macos --release \
  --build-name="${release_version%%+*}" --build-number="${release_version##*+}" \
  --dart-define="APP_VERSION=${release_version}"
app_path="build/macos/Build/Products/Release/Shike.app"
codesign --verify --deep --strict "${app_path}"
printf 'App: %s/%s\n' "$PWD" "${app_path}"
printf '%s\n' 'Local ad-hoc signed build. Developer ID signing and Apple notarization are required before public distribution.'
