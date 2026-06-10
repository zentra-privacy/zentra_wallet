#!/usr/bin/env bash
# GitHub community release — APK + Linux tarball (no Play Store).
#
#   ./scripts/release.sh              # build + tag + GitHub release
#   ./scripts/release.sh --build-only   # dist/ only, no git/gh
#   ./scripts/release.sh --publish-only # tag + release from existing dist/
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export WALLET_ROOT="$ROOT"

# shellcheck source=lib/native_build.sh
source "$ROOT/scripts/lib/native_build.sh"
# shellcheck source=lib/native_build_android.sh
source "$ROOT/scripts/lib/native_build_android.sh"
# shellcheck source=lib/build_apps.sh
source "$ROOT/scripts/lib/build_apps.sh"

VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)"
TAG="v${VERSION}"
DIST="$ROOT/dist"
APK_NAME="zentra-wallet-${VERSION}.apk"
LINUX_NAME="zentra-wallet-linux-${VERSION}-x64.tar.gz"

DO_BUILD=1
DO_PUBLISH=1

for arg in "$@"; do
  case "$arg" in
    --build-only) DO_PUBLISH=0 ;;
    --publish-only) DO_BUILD=0 ;;
    -h|--help)
      sed -n '2,8p' "$0"
      exit 0
      ;;
    *) echo "Unknown: $arg (use --build-only or --publish-only)" >&2; exit 1 ;;
  esac
done

_resolve_zentra() {
  if [[ -n "${ZENTRA_ROOT:-}" && -d "${ZENTRA_ROOT}/src/wallet/api" ]]; then
    echo "$(cd "$ZENTRA_ROOT" && pwd)"; return
  fi
  if [[ -d "$ROOT/../zentra/src/wallet/api" ]]; then
    echo "$(cd "$ROOT/../zentra" && pwd)"; return
  fi
  echo ""
}

build_release_artifacts() {
  local z
  z="$(_resolve_zentra)"
  [[ -n "$z" ]] || { echo "Error: Zentra source not found"; exit 1; }

  echo "==> Version: $VERSION ($TAG)"
  echo "==> Native Linux FFI"
  native_build_host "$z"

  echo "==> Native Android jniLibs (ARM only — community sideload)"
  ANDROID_ABIS="arm64-v8a armeabi-v7a" native_build_android "$z"

  echo "==> Flutter pub get"
  (cd "$ROOT" && flutter pub get)

  echo "==> Flutter Linux release"
  (cd "$ROOT" && flutter build linux --release)

  echo "==> Flutter Android APK"
  (cd "$ROOT" && flutter build apk --release)

  mkdir -p "$DIST"
  cp "$ROOT/build/app/outputs/flutter-apk/app-release.apk" "$DIST/$APK_NAME"

  local bundle="$ROOT/build/linux/x64/release/bundle"
  tar -czf "$DIST/$LINUX_NAME" -C "$bundle" .

  echo ""
  echo "==> Release files:"
  ls -lh "$DIST/$APK_NAME" "$DIST/$LINUX_NAME"
  echo ""
  echo "==> iOS (Mac only — sideload / re-sign for community):"
  echo "    ./wallet.sh build-ios && flutter build ios --release --no-codesign"
  echo "    Zip Runner.app → dist/apple/ and attach to GitHub release manually"
}

publish_github_release() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "Error: gh CLI not installed (https://cli.github.com/)"
    exit 1
  fi

  [[ -f "$DIST/$APK_NAME" ]] || { echo "Error: missing $DIST/$APK_NAME — run build first"; exit 1; }
  [[ -f "$DIST/$LINUX_NAME" ]] || { echo "Error: missing $DIST/$LINUX_NAME — run build first"; exit 1; }

  if [[ -n "$(git status --porcelain)" ]]; then
    echo "Error: uncommitted changes — commit version bump first"
    git status --short
    exit 1
  fi

  if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "Error: tag $TAG already exists"
    exit 1
  fi

  git tag -a "$TAG" -m "Zentra Wallet $VERSION"
  git push origin "$TAG"

  gh release create "$TAG" \
    "$DIST/$APK_NAME" \
    "$DIST/$LINUX_NAME" \
    --title "Zentra Wallet $VERSION" \
    --notes "$(cat <<EOF
## What's new
- **Native history pagination** — only 25 transactions load at first; scroll loads more from wallet
- **Restore / sync height fix** — scan checkpoint saves correctly; no more stuck at block 0
- **Faster startup & polling** — balance first, smarter background sync

## Downloads (community — GitHub only)
- **Android:** \`$APK_NAME\` — sideload APK (ARM, Android 7.0+)
- **Linux x64:** \`$LINUX_NAME\` — extract and run \`./zentra_wallet\`

## iOS
Build on macOS: \`./wallet.sh build-ios\` then \`flutter build ios --release --no-codesign\` — attach \`.app\` zip to this release if needed.
EOF
)"

  echo ""
  echo "==> Published: $(gh release view "$TAG" --json url -q .url)"
}

[[ "$DO_BUILD" -eq 1 ]] && build_release_artifacts
[[ "$DO_PUBLISH" -eq 1 ]] && publish_github_release

echo "==> Done."
