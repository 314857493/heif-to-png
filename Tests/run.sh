#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_work="$(mktemp -d "${TMPDIR:-/tmp}/heif-png-tests.XXXXXX")"
trap 'rm -rf "$test_work"' EXIT
xcrun swiftc -swift-version 5 \
  -module-cache-path "${SWIFT_MODULE_CACHE_PATH:-$test_work/cache}" \
  "$project_dir/Source/Converter.swift" "$project_dir/Tests/main.swift" \
  -o "$test_work/converter-tests"
"$test_work/converter-tests" "$test_work/fixtures"
