#!/usr/bin/env bash
set -euo pipefail

CLI_VERSION="${SUPABASE_CLI_VERSION:-2.101.0}"

if command -v supabase >/dev/null 2>&1; then
  exec supabase "$@"
fi

if command -v npx >/dev/null 2>&1; then
  exec npx -y "supabase@${CLI_VERSION}" "$@"
fi

if [[ -x /opt/homebrew/bin/npx ]]; then
  exec /opt/homebrew/bin/npx -y "supabase@${CLI_VERSION}" "$@"
fi

if [[ -x /usr/local/bin/npx ]]; then
  exec /usr/local/bin/npx -y "supabase@${CLI_VERSION}" "$@"
fi

echo "Supabase CLI is not installed and npx was not found." >&2
echo "Install Node/npm or Homebrew, then rerun this script." >&2
exit 127
