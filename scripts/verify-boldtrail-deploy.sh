#!/usr/bin/env bash
# Verify BoldTrail routes after deploying www.flyrpro.app.
# Usage:
#   ./scripts/verify-boldtrail-deploy.sh
#
# Expected:
#   - POST /api/integrations/boldtrail/test -> 401 JSON when no auth is supplied
#   - POST /api/integrations/boldtrail/push-lead -> 401 JSON when no auth is supplied
#   - No x-matched-path: /404 on either route

set -e

BASE_URL="${BASE_URL:-https://www.flyrpro.app}"
ROUTES=(
  "/api/integrations/boldtrail/test"
  "/api/integrations/boldtrail/push-lead"
)

check_route() {
  local route="$1"
  local url="${BASE_URL}${route}"

  echo "→ POST $url"
  local resp
  resp=$(curl -s -i -X POST "$url" -H "Content-Type: application/json" --data '{}') || true

  echo "$resp"
  echo ""

  local status
  local match_path
  status=$(echo "$resp" | head -1)
  match_path=$(echo "$resp" | grep -i "x-matched-path" || true)

  if [ -n "$match_path" ] && echo "$match_path" | grep -q "/404"; then
    echo "❌ Route not found for $route"
    return 1
  fi

  if echo "$status" | grep -q " 401 "; then
    echo "✅ $route is live (returned 401 without auth, which is expected)."
    return 0
  fi

  echo "❌ Unexpected response for $route. Expected 401 JSON without auth."
  return 1
}

for route in "${ROUTES[@]}"; do
  check_route "$route"
done
