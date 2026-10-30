#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_build="$(mktemp -d "${TMPDIR:-/tmp}/wolfgrid-2d-tests.XXXXXX")"
trap 'rm -rf "$task_build"' EXIT
cd "$task_root"
swiftc -D WOLFGRID_STANDALONE_MAP_TESTS -module-cache-path "$task_build/module-cache" \
  WolfGrid/Features/Map/Services/StandardCampaignClusterLayout.swift \
  WolfGrid/Features/Map/Services/StandardCampaignPinDraft.swift \
  WolfGridTests/StandardCampaignClusterLayoutTests.swift \
  WolfGridTests/StandardCampaignPinDraftTests.swift \
  scripts/test-standard-campaign-map.swift -o "$task_build/map-regressions"
"$task_build/map-regressions"
