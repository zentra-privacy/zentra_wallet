#!/usr/bin/env bash
# Zentra Wallet — single entry point (menu + all commands).
#
#   ./wallet.sh              interactive menu
#   ./wallet.sh build
#   ./wallet.sh run
#   ./wallet.sh help
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export WALLET_ROOT="$ROOT"

LIB="$ROOT/scripts/lib"
# shellcheck source=lib/native_build.sh
source "$LIB/native_build.sh"
# shellcheck source=lib/native_build_common.sh
source "$LIB/native_build_common.sh"
# shellcheck source=lib/native_build_android.sh
source "$LIB/native_build_android.sh"
# shellcheck source=lib/native_build_mingw.sh
source "$LIB/native_build_mingw.sh"
# shellcheck source=lib/native_build_macos.sh
source "$LIB/native_build_macos.sh"
# shellcheck source=lib/native_build_ios.sh
source "$LIB/native_build_ios.sh"
# shellcheck source=lib/flutter_run.sh
source "$LIB/flutter_run.sh"
# shellcheck source=lib/clean_data.sh
source "$LIB/clean_data.sh"
# shellcheck source=lib/build_apps.sh
source "$LIB/build_apps.sh"

SO_PATH="$ROOT/packages/zentra_wallet_core/linux/libzentra_wallet_ffi.so"

_USE_COLOR=0
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-}" != dumb ]]; then
  _USE_COLOR=1
fi
if [[ "$_USE_COLOR" -eq 1 ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_CYAN=$'\033[36m'; C_RED=$'\033[31m'
else
  C_RESET= C_BOLD= C_DIM= C_GREEN= C_YELLOW= C_CYAN= C_RED=
fi

_hr() { printf '%b\n' "${C_DIM}========================================${C_RESET}"; }
_ok() { printf '  %b✓%b %s\n' "$C_GREEN" "$C_RESET" "$*"; }
_warn() { printf '  %b!%b %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
_err() { printf '  %bx%b %s\n' "$C_RED" "$C_RESET" "$*"; }

_resolve_zentra() {
  if [[ -n "${ZENTRA_ROOT:-}" && -d "${ZENTRA_ROOT}/src/wallet/api" ]]; then
    echo "$(cd "$ZENTRA_ROOT" && pwd)"; return
  fi
  if [[ -d "$ROOT/../zentra/src/wallet/api" ]]; then
    echo "$(cd "$ROOT/../zentra" && pwd)"; return
  fi
  if [[ -d "$ROOT/third_party/zentra/src/wallet/api" ]]; then
    echo "$(cd "$ROOT/third_party/zentra" && pwd)"; return
  fi
  echo ""
}

cmd_status() {
  _hr
  printf '%b%b  Zentra Wallet — status%b\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
  _hr
  local z; z="$(_resolve_zentra)"
  [[ -n "$z" ]] && _ok "Zentra: $z" || _warn "Zentra: not found"
  [[ -f "$SO_PATH" ]] && _ok "Linux FFI: $(ls -lh "$SO_PATH" | awk '{print $5, $9}')" || _warn "Linux FFI: missing (./wallet.sh build)"
  local jni="$ROOT/packages/zentra_wallet_core/android/src/main/jniLibs"
  local android_ok=0
  for abi in arm64-v8a armeabi-v7a x86_64; do
    if [[ -f "$jni/$abi/libzentra_wallet_ffi.so" ]]; then
      _ok "Android $abi: $(ls -lh "$jni/$abi/libzentra_wallet_ffi.so" | awk '{print $5}')"
      android_ok=1
    fi
  done
  [[ "$android_ok" -eq 0 ]] && _warn "Android FFI: missing (./wallet.sh build-android)"
  local macdylib="$ROOT/packages/zentra_wallet_core/macos/lib/libzentra_wallet_ffi.dylib"
  [[ -f "$macdylib" ]] && _ok "macOS FFI: $(ls -lh "$macdylib" | awk '{print $5, $9}')" || _warn "macOS FFI: missing (./wallet.sh build-macos)"
  local iosxcf="$ROOT/packages/zentra_wallet_core/ios/lib/zentra_wallet_ffi.xcframework"
  [[ -d "$iosxcf" ]] && _ok "iOS XCFramework: present" || _warn "iOS FFI: missing (./wallet.sh build-ios on Mac)"
  command -v flutter >/dev/null 2>&1 && _ok "Flutter: $(flutter --version 2>/dev/null | head -1)" || _warn "Flutter: not in PATH"
  _hr
}

cmd_build() {
  local z="${1:-$(_resolve_zentra)}"
  [[ -z "$z" ]] && { _err "Zentra source not found. Set ZENTRA_ROOT or clone into third_party/zentra"; return 1; }
  native_build_host "$z"
}

cmd_build_windows() {
  local z=""
  if [[ -n "${1:-}" && -d "${1}/src/wallet/api" ]]; then z="$1"; else z="$(_resolve_zentra)"; fi
  [[ -z "$z" ]] && { _err "Zentra source not found"; return 1; }
  native_build_mingw "$z"
}

cmd_build_macos() {
  local z=""
  if [[ -n "${1:-}" && -d "${1}/src/wallet/api" ]]; then z="$1"; else z="$(_resolve_zentra)"; fi
  [[ -z "$z" ]] && { _err "Zentra source not found"; return 1; }
  native_build_macos "$z"
}

cmd_build_all_native() {
  local z=""
  if [[ -n "${1:-}" && -d "${1}/src/wallet/api" ]]; then z="$1"; else z="$(_resolve_zentra)"; fi
  [[ -z "$z" ]] && { _err "Zentra source not found"; return 1; }
  cmd_build "$z" || return 1
  native_build_mingw "$z" || return 1
  native_build_android "$z" || return 1
  if [[ "$(uname -s)" == "Darwin" ]]; then
    native_build_macos "$z" || return 1
    native_build_ios "$z" || return 1
  else
    _warn "Skip macOS/iOS native (run build-macos / build-ios on a Mac)"
  fi
}

cmd_build_ios() {
  local z=""
  if [[ -n "${1:-}" && -d "${1}/src/wallet/api" ]]; then z="$1"; else z="$(_resolve_zentra)"; fi
  [[ -z "$z" ]] && { _err "Zentra source not found"; return 1; }
  native_build_ios "$z"
}

cmd_build_apps() {
  local z=""
  if [[ -n "${1:-}" && -d "${1}/src/wallet/api" ]]; then z="$1"; else z="$(_resolve_zentra)"; fi
  [[ -z "$z" ]] && { _err "Zentra source not found"; return 1; }
  build_apps_auto "$z"
}

cmd_build_app_macos() {
  local z=""
  if [[ -n "${1:-}" && -d "${1}/src/wallet/api" ]]; then z="$1"; else z="$(_resolve_zentra)"; fi
  [[ -z "$z" ]] && { _err "Zentra source not found"; return 1; }
  build_apps_macos_native "$z" && build_apps_macos_flutter
}

cmd_build_app_ios() {
  local z=""
  if [[ -n "${1:-}" && -d "${1}/src/wallet/api" ]]; then z="$1"; else z="$(_resolve_zentra)"; fi
  [[ -z "$z" ]] && { _err "Zentra source not found"; return 1; }
  build_apps_ios_native "$z" && build_apps_ios_flutter
}

cmd_build_apple_production() {
  local z=""
  if [[ -n "${1:-}" && -d "${1}/src/wallet/api" ]]; then z="$1"; else z="$(_resolve_zentra)"; fi
  [[ -z "$z" ]] && { _err "Zentra source not found"; return 1; }
  build_apple_production "$z"
}

cmd_build_android() {
  local z=""
  if [[ -n "${1:-}" && -d "${1}/src/wallet/api" ]]; then
    z="$1"
    shift
  else
    z="$(_resolve_zentra)"
  fi
  [[ -z "$z" ]] && { _err "Zentra source not found. Set ZENTRA_ROOT or clone into third_party/zentra"; return 1; }
  native_build_android "$z" "$@"
}

cmd_run_app() {
  [[ ! -f "$SO_PATH" ]] && { _warn "Building native lib first…"; cmd_build || return 1; }
  flutter_wallet_run -d linux "$@"
}

cmd_devices() { flutter_wallet_run -l; }

cmd_clean_data() { clean_wallet_data "$@"; }

cmd_full_flow() {
  local z="${1:-$(_resolve_zentra)}"
  [[ -z "$z" ]] && { _err "Zentra source not found"; return 1; }
  cmd_build "$z" || return 1
  echo
  cmd_run_app "$@"
}

# Prints path on stdout only (messages go to stderr for safe $(...) capture).
_ask_zentra_path() {
  local c; c="$(_resolve_zentra)"
  if [[ -n "$c" ]]; then
    echo "$c"
    return 0
  fi
  printf 'Path to zentra source: ' >&2
  read -r p
  if [[ -d "$p/src/wallet/api" ]]; then
    echo "$(cd "$p" && pwd)"
    return 0
  fi
  printf '  %b!%b Invalid path (need src/wallet/api)\n' "$C_YELLOW" "$C_RESET" >&2
  return 1
}

_show_menu() {
  echo ""
  _hr
  printf '%b%b  Zentra Wallet%b\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
  if [[ -f "$SO_PATH" ]]; then
    printf '  %bNative lib: ready%b\n' "$C_GREEN" "$C_RESET"
  else
    printf '  %bNative lib: not built%b\n' "$C_YELLOW" "$C_RESET"
  fi
  _hr
  cat <<'MENU'
  1   Build native library
  2   Run app (Linux)
  3   Build + Run
  4   Flutter devices
  5   Status
  6   Clean wallet test data
  0   Exit
MENU
  _hr
}

_run_menu_action() {
  local title="$1"
  shift
  echo ""
  _hr
  printf '%b%b  %s%b\n' "$C_BOLD" "$C_CYAN" "$title" "$C_RESET"
  _hr
  echo ""
  set +e
  "$@"
  local rc=$?
  set -e
  echo ""
  _hr
  if [[ $rc -eq 0 ]]; then
    _ok "Done: $title"
  else
    _err "Failed (exit $rc): $title"
  fi
  _hr
  echo ""
  read -r -p "Press Enter to return to menu… " _
}

_menu_loop() {
  while true; do
    _show_menu
    read -r -p "Choice [0-6]: " c
    case "$c" in
      1|3)
        if p="$(_ask_zentra_path)"; then
          if [[ "$c" == "1" ]]; then
            _run_menu_action "Build native library" cmd_build "$p"
          else
            _run_menu_action "Build + Run" cmd_full_flow "$p"
          fi
        fi
        ;;
      2) _run_menu_action "Run app (Linux)" cmd_run_app ;;
      4) _run_menu_action "Flutter devices" cmd_devices ;;
      5) _run_menu_action "Status" cmd_status ;;
      6) _run_menu_action "Clean wallet data" cmd_clean_data ;;
      0|q|Q) echo "Bye."; exit 0 ;;
      *) _err "Invalid choice: $c"; sleep 1 ;;
    esac
  done
}

case "${1:-}" in
  ""|menu) _menu_loop ;;
  status) cmd_status ;;
  build|build-host) shift; cmd_build "${1:-}" ;;
  build-android) shift; cmd_build_android "$@" ;;
  build-windows|build-mingw) shift; cmd_build_windows "${1:-}" ;;
  build-macos|build-darwin) shift; cmd_build_macos "${1:-}" ;;
  build-ios) shift; cmd_build_ios "${1:-}" ;;
  build-all-native) shift; cmd_build_all_native "${1:-}" ;;
  build-apps|build-all-apps) shift; cmd_build_apps "${1:-}" ;;
  build-app-macos) shift; cmd_build_app_macos "${1:-}" ;;
  build-app-ios) shift; cmd_build_app_ios "${1:-}" ;;
  build-apple-production|build-production-apple) shift; cmd_build_apple_production "${1:-}" ;;
  run|start) shift; cmd_run_app "$@" ;;
  devices) cmd_devices ;;
  clean-data) shift; cmd_clean_data "$@" ;;
  release) shift; exec "$ROOT/scripts/release.sh" "$@" ;;
  full|all) cmd_full_flow ;;
  help|-h|--help)
    cat <<EOF
Zentra Wallet — ./wallet.sh

  ./wallet.sh              Interactive menu
  ./wallet.sh build        Build libzentra_wallet_ffi.so (Linux)
  ./wallet.sh build-android   Android jniLibs
  ./wallet.sh build-windows   Windows libzentra_wallet_ffi.dll (MinGW)
  ./wallet.sh build-macos     macOS dylib (run on Mac)
  ./wallet.sh build-ios       iOS XCFramework (run on Mac + Xcode)
  ./wallet.sh build-all-native  Linux + Android + Windows (+ macOS/iOS on Mac)
  ./wallet.sh build-apps     Native + Flutter apps for this host (macOS+iOS on Mac; Linux+APK on Linux)
  ./wallet.sh build-app-macos   macOS dylib + .app only
  ./wallet.sh build-app-ios     iOS XCFramework + simulator/device app
  ./wallet.sh build-apple-production  Mac + iPhone/iPad release files → dist/apple/
  ./wallet.sh run          Run Linux app
  ./wallet.sh release      GitHub community release (APK + Linux)
  ./wallet.sh full         build + run
  ./wallet.sh status       Zentra / native lib / Flutter

Build on Ubuntu 22 VM: clone repo there, install deps, then ./wallet.sh build && ./wallet.sh run
EOF
    ;;
  *)
    _err "Unknown: $1"
    echo "  ./wallet.sh help"
    exit 1
    ;;
esac
