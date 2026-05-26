#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUPABASE_WRAPPER="${ROOT_DIR}/scripts/supabase.sh"

FILES=(
  "${ROOT_DIR}/supabase/migrations/20260526110000_add_link_source_to_building_address_links.sql"
  "${ROOT_DIR}/supabase/migrations/20260526111000_create_auto_link_campaign_addresses.sql"
  "${ROOT_DIR}/supabase/migrations/20260526112000_materialize_campaign_buildings_from_geojson.sql"
)

MODE="${1:-dry-run}"
case "${MODE}" in
  dry-run)
    for file in "${FILES[@]}"; do
      echo "Would apply: ${file}"
    done
    ;;
  apply)
    for file in "${FILES[@]}"; do
      echo "Applying: ${file}"
      "${SUPABASE_WRAPPER}" db query --linked --workdir "${ROOT_DIR}" --file "${file}"
    done
    ;;
  *)
    echo "Usage: $0 [dry-run|apply]" >&2
    exit 2
    ;;
esac
