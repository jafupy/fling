#!/bin/sh
set -eu

fling_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$fling_root"
swift build -c release
fling_products=$(swift build -c release --show-bin-path)
fling_bundle="$fling_root/.build/Fling.app"
mkdir -p "$fling_bundle/Contents/MacOS" "$fling_bundle/Contents/Resources"
cp "$fling_products/FlingWM" "$fling_bundle/Contents/MacOS/FlingWM"
cp Packaging/Info.plist "$fling_bundle/Contents/Info.plist"
printf 'APPL????' > "$fling_bundle/Contents/PkgInfo"
xcrun swiftc Packaging/Icon.swift -o .build/fling-icon-builder
.build/fling-icon-builder "$fling_root/.build/Fling.iconset"
iconutil -c icns .build/Fling.iconset -o "$fling_bundle/Contents/Resources/Fling.icns"
codesign --force --sign - --identifier com.jafupy.fling "$fling_bundle"
codesign --verify --strict "$fling_bundle"
fling_archive="$fling_root/.build/Fling-macOS-$(uname -m).zip"
ditto -c -k --sequesterRsrc --keepParent "$fling_bundle" "$fling_archive"
printf '%s\n%s\n' "$fling_bundle" "$fling_archive"
