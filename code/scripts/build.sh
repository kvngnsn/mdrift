#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
app_dir="${MDRIFT_APP_PATH:-$project_dir/build/mdrift.app}"
app_dir="${app_dir:A}"
if [[ "$app_dir" != *.app || "$app_dir" == /Applications/* || "$app_dir" == "$HOME/Applications/"* ]]; then
  print -u2 'Choose an .app build output outside Applications.'
  exit 1
fi
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/mdrift-build.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
sdk_path="$(xcrun --show-sdk-path)"
architecture="${MDRIFT_ARCH:-$(uname -m)}"
case "$architecture" in
  arm64|x86_64) ;;
  *) print -u2 "Unsupported architecture: $architecture"; exit 1 ;;
esac

if [[ ! -f "$project_dir/build/web/app.js" ]]; then
  print -u2 'Run npm run build:web first.'
  exit 1
fi

# Some Command Line Tools installs contain duplicate SwiftBridging module maps.
# Hide the obsolete map for this compiler invocation without changing the SDK.
compiler_flags=()
toolchain_include="$(xcode-select -p)/usr/include/swift"
if [[ -f "$toolchain_include/module.modulemap" && -f "$toolchain_include/bridging.modulemap" ]]; then
  python3 - "$build_dir" "$toolchain_include" <<'PY'
import json, pathlib, sys
build = pathlib.Path(sys.argv[1])
(build / 'empty.modulemap').write_text('')
(build / 'overlay.json').write_text(json.dumps({'version': 0, 'roots': [
    {'type': 'file', 'name': sys.argv[2] + '/module.modulemap',
     'external-contents': str(build / 'empty.modulemap')}
]}))
PY
  compiler_flags=(-vfsoverlay "$build_dir/overlay.json")
fi
sources=("$project_dir"/src/*.swift)
if [[ "${MDRIFT_NATIVE_TESTS:-0}" == "1" ]]; then
  compiler_flags+=(-D NATIVE_TESTS)
  sources+=("$project_dir/tests/NativeTests.swift")
fi
swiftc -O -sdk "$sdk_path" -module-cache-path "$build_dir/module-cache" \
  "${compiler_flags[@]}" -target "$architecture-apple-macosx13.0" \
  -framework Cocoa -framework WebKit "${sources[@]}" -o "$build_dir/mdrift"

# Assemble a fresh bundle so renamed executables never remain in the output.
staged_app="$build_dir/mdrift.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
cp "$build_dir/mdrift" "$staged_app/Contents/MacOS/mdrift"
cp "$project_dir/src/Info.plist" "$staged_app/Contents/Info.plist"
if [[ "${MDRIFT_NATIVE_TESTS:-0}" == "1" ]]; then
  /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.mdrift.qa' "$staged_app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleName mdrift QA' "$staged_app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName mdrift QA' "$staged_app/Contents/Info.plist"
fi
ditto "$project_dir/build/web" "$staged_app/Contents/Resources/web"
cp "$project_dir/../LICENSE" "$staged_app/Contents/Resources/LICENSE"
cp "$project_dir/THIRD_PARTY_NOTICES.md" "$staged_app/Contents/Resources/THIRD_PARTY_NOTICES.md"
swift -sdk "$sdk_path" -module-cache-path "$build_dir/module-cache" \
  "${compiler_flags[@]}" "$project_dir/scripts/make-icon.swift" "$build_dir/AppIcon.iconset"
iconutil -c icns "$build_dir/AppIcon.iconset" -o "$staged_app/Contents/Resources/AppIcon.icns"
mkdir -p "$project_dir/build"
cp "$build_dir/AppIcon.iconset/icon_512x512@2x.png" "$project_dir/build/icon.png"
codesign --force --deep --sign - "$staged_app"
# Replace only the development bundle, never an installed application.
if [[ -e "$app_dir" ]]; then rm -rf "$app_dir"; fi
mkdir -p "${app_dir:h}"
ditto "$staged_app" "$app_dir"
codesign --verify --deep --strict "$app_dir"
print "Built: $app_dir"
