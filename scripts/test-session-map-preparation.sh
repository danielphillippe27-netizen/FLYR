#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_build="$(mktemp -d "${TMPDIR:-/tmp}/wolfgrid-session-tests.XXXXXX")"
trap 'rm -rf "$task_build"' EXIT
cd "$task_root"
swiftc WolfGrid/Features/Map/Services/SessionMapPreparationCache.swift \
  scripts/test-session-map-preparation.swift -o "$task_build/session-regressions"
"$task_build/session-regressions"
