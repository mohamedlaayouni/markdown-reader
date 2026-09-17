#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
READER_SDK="${READER_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
if [ ! -d "$READER_SDK" ]; then READER_SDK="$(xcrun --sdk macosx --show-sdk-path)"; fi
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT/.build/ModuleCache}"
ARGS=(--sdk "$READER_SDK")
# Some Command Line Tools releases omit this macro plugin from Swift Build's
# discovery list even though the bundled Testing framework is available.
TESTING_PLUGIN="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [ -f "$TESTING_PLUGIN" ]; then ARGS+=(-Xswiftc -load-plugin-library -Xswiftc "$TESTING_PLUGIN"); fi
swift test --build-system native "${ARGS[@]}" "$@"
