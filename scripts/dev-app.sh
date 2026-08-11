#!/usr/bin/env bash

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
module_cache="${TMPDIR:-/tmp}/MacMouseGestures-swift-module-cache"
swift_args=(-Xswiftc -module-cache-path -Xswiftc "$module_cache")

cd "$project_root"
swift build "${swift_args[@]}"
swift run "${swift_args[@]}" MacMouseGestures
