#!/usr/bin/env bash
set -euo pipefail

# Resolve from the script, not the caller's cwd. Invoke with bash tool/build_web.sh.
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd -P)"
if [[ ! -f "${PROJECT_ROOT}/pubspec.yaml" || ! -f "${PROJECT_ROOT}/web/sw.template.js" ]]; then
  printf '%s\n' 'Cannot locate the Flutter project beside this script.' >&2
  exit 1
fi
cd -- "${PROJECT_ROOT}"

# Keep generation and compilation in the same directory/mode. Safe build flags
# such as --base-href=/clock/, --dart-define=..., and --no-pub pass through.
for argument in "$@"; do
  case "${argument}" in
    --output|--output=*|--output-dir|--output-dir=*|-o|-o?*|--debug|--profile|--wasm|--web-resources-cdn|--web-resources-cdn=*|--pwa-strategy|--pwa-strategy=*)
      printf 'This release/offline wrapper does not allow: %s\n' "${argument}" >&2
      exit 2
      ;;
  esac
done

# Verified read-only against the pinned Flutter 3.47.5 SDK sources:
# packages/flutter_tools/lib/src/commands/build_web.dart still defines
# pwa-strategy (deprecated, supports none); runner/flutter_command.dart defines
# the negatable web-resources-cdn flag. Remove pwa-strategy if upgrading to a
# future SDK that removes it; do not invoke Flutter merely to probe flags.
fvm flutter build web --release --no-web-resources-cdn --pwa-strategy=none "$@"
node tool/generate_sw.mjs build/web
