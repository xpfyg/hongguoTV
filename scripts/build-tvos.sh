#!/usr/bin/env bash
# Build the Apple TV (tvOS) app with xcodebuild.
#
# Usage:
#   scripts/build-tvos.sh [simulator|device]
#
#   simulator (default)  - Release build for tvOS Simulator, no signing required.
#   device               - Release build for tvOS device. Unsigned by default;
#                          set DEVELOPMENT_TEAM=<TeamID> to sign automatically.
#
# Preconditions:
#   - node >= 22 in PATH (used by the React Native bundle phase)
#   - npm ci has been run (node_modules present)
#   - cd ios && pod install has been run (ios/HongguoTV.xcworkspace present)
#
# Output:
#   outputs/hongguotv-<version>-tvos.app (+ SHA256SUMS)
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

# --- locate CocoaPods (often not on non-interactive PATH) ---
POD_BIN="${POD_BIN:-}"
if [[ -z "$POD_BIN" ]]; then
  if command -v pod >/dev/null 2>&1; then
    POD_BIN=pod
  elif [[ -x /opt/homebrew/bin/pod ]]; then
    POD_BIN=/opt/homebrew/bin/pod
  elif [[ -x /usr/local/bin/pod ]]; then
    POD_BIN=/usr/local/bin/pod
  else
    echo "CocoaPods not found. Install it first: brew install cocoapods" >&2
    exit 1
  fi
fi

# --- preconditions ---
command -v node >/dev/null 2>&1 || { echo "node not found in PATH (RN bundle phase needs it)" >&2; exit 1; }
[[ -d node_modules ]] || { echo "node_modules missing - run: npm ci" >&2; exit 1; }
[[ -f ios/Podfile.lock ]] || { echo "Pods not installed - run: (cd ios && $POD_BIN install)" >&2; exit 1; }
workspace="ios/HongguoTV.xcworkspace"
[[ -d "$workspace" ]] || { echo "Pods workspace missing - run: (cd ios && $POD_BIN install)" >&2; exit 1; }

mode="${1:-simulator}"
case "$mode" in
  simulator|device) ;;
  *) echo "usage: $0 [simulator|device]" >&2; exit 1 ;;
esac

version="$(node -p "require('./package.json').version")"
out_dir="outputs"
mkdir -p "$out_dir"
derived="build/tv"

# --- Hermes tarball sanity check (Release builds) ---
# RN ships two prebuilt Hermes tarballs: the RELEASE tarball is built WITHOUT the
# JS debugger (no `HermesRuntimeImpl::debugJavaScript`), the DEBUG tarball WITH it.
# RN's C++ pods compile `HermesInstance.cpp` with `HERMES_ENABLE_DEBUGGER` only in
# the Debug configuration, so a Release build linked against the DEBUG Hermes
# framework dispatches `registerForProfiling()` onto `debugJavaScript()`'s vtable
# slot and crashes at launch (SIGSEGV at 0x17). The Podfile now installs a
# "[Hermes] Swap framework per configuration" build phase that swaps the framework
# to match each configuration at build time, so this check is informational only.
if [[ "$mode" == simulator || "$mode" == device ]]; then
  hermes_bin="$(find ios/Pods/hermes-engine/destroot -name hermes -path '*tvos*sim*' -print -quit 2>/dev/null || true)"
  if [[ -n "$hermes_bin" ]] && command -v nm >/dev/null 2>&1; then
    debug_count="$(nm "$hermes_bin" 2>/dev/null | grep -c 'CDPHandler' || true)"
    if [[ -n "$debug_count" && "$debug_count" -gt 0 ]]; then
      echo "note: installed Hermes framework currently has the JS debugger (CDPHandler symbols)."
      echo "  This is correct for Debug builds. The '[Hermes] Swap framework per configuration'"
      echo "  build phase will swap in the RELEASE framework during this Release build."
    fi
  fi
fi

echo "==> building tvOS $mode (Release) $version"

if [[ "$mode" == simulator ]]; then
  xcodebuild \
    -workspace "$workspace" -scheme HongguoTV -configuration Release \
    -sdk appletvsimulator -destination 'generic/platform=tvOS Simulator' \
    -derivedDataPath "$derived" build
  app_dir="$derived/Build/Products/Release-appletvsimulator"
else
  signing_args=(-sdk appletvos -destination 'generic/platform=tvOS')
  if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
    echo "==> signing with team $DEVELOPMENT_TEAM"
    signing_args+=(CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM")
  else
    echo "==> no DEVELOPMENT_TEAM set; producing unsigned .app (sign later in Xcode)"
    signing_args+=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO)
  fi
  xcodebuild \
    -workspace "$workspace" -scheme HongguoTV -configuration Release \
    "${signing_args[@]}" \
    -derivedDataPath "$derived" build
  app_dir="$derived/Build/Products/Release-appletvos"
fi

app="$(find "$app_dir" -maxdepth 1 -name 'HongguoTV.app' -print -quit)"
[[ -n "$app" && -d "$app" ]] || { echo "build finished but HongguoTV.app not found under $app_dir" >&2; exit 1; }

artifact="outputs/hongguotv-${version}-tvos.app"
rm -rf "$artifact"
cp -R "$app" "$artifact"
echo "==> artifact: $artifact"

# .app is a directory; archive it so the checksum covers the whole bundle
archive="outputs/hongguotv-${version}-tvos.app.tar.gz"
rm -f "$archive"
tar -C outputs -czf "$archive" "hongguotv-${version}-tvos.app"
echo "==> archive: $archive"

if command -v shasum >/dev/null; then shasum -a 256 "$archive" > outputs/SHA256SUMS; else sha256sum "$archive" > outputs/SHA256SUMS; fi
cat outputs/SHA256SUMS
