#!/bin/bash
set -euo pipefail
source_dir="$(cd "$(dirname "$0")" && pwd)"
app_dir="$source_dir/../HEIF to PNG.app"
build_cache="$(mktemp -d "${TMPDIR:-/tmp}/heif-png-build.XXXXXX")"
trap 'rm -rf "$build_cache"' EXIT
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$source_dir/Info.plist" "$app_dir/Contents/Info.plist"
xcrun swiftc -O -swift-version 5 -target arm64-apple-macos13.0 -module-cache-path "$build_cache" \
  "$source_dir/Converter.swift" "$source_dir/UI.swift" "$source_dir/main.swift" \
  -o "$app_dir/Contents/MacOS/HEIFtoPNG"
codesign --force --sign - "$app_dir"
echo "Built: $app_dir"
