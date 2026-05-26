#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUPABASE_WRAPPER="${ROOT_DIR}/scripts/supabase.sh"
PROJECT_REF="${SUPABASE_PROJECT_REF:-}"

if [[ -z "${PROJECT_REF}" && -f "${ROOT_DIR}/supabase/.temp/project-ref" ]]; then
  PROJECT_REF="$(tr -d '[:space:]' < "${ROOT_DIR}/supabase/.temp/project-ref")"
fi

if [[ -z "${PROJECT_REF}" ]]; then
  echo "Missing Supabase project ref. Set SUPABASE_PROJECT_REF or link the project first." >&2
  exit 1
fi

if [[ ! -f "${ROOT_DIR}/supabase/config.toml" ]]; then
  echo "Supabase config.toml is missing; creating CLI project config."
  "${SUPABASE_WRAPPER}" init --workdir "${ROOT_DIR}"
fi

if [[ ! -f "${ROOT_DIR}/supabase/.temp/project-ref" ]]; then
  echo "Linking Supabase project ${PROJECT_REF}."
  "${SUPABASE_WRAPPER}" link --project-ref "${PROJECT_REF}" --workdir "${ROOT_DIR}"
fi

MODE="${1:-dry-run}"
case "${MODE}" in
  dry-run)
    "${SUPABASE_WRAPPER}" db push --linked --dry-run --workdir "${ROOT_DIR}"
    ;;
  push)
    "${SUPABASE_WRAPPER}" db push --linked --workdir "${ROOT_DIR}"
    ;;
  *)
    echo "Usage: $0 [dry-run|push]" >&2
    exit 2
    ;;
esac
