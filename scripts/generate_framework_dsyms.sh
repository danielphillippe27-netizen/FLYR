#!/bin/sh
set -eu

if [ "${DEBUG_INFORMATION_FORMAT:-}" != "dwarf-with-dsym" ]; then
  exit 0
fi

frameworks_dir="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH:-}"
dsym_dir="${DWARF_DSYM_FOLDER_PATH:-}"

if [ ! -d "$frameworks_dir" ] || [ -z "$dsym_dir" ]; then
  exit 0
fi

find "$frameworks_dir" -maxdepth 1 -type d -name '*.framework' | while IFS= read -r framework; do
  framework_name="$(basename "$framework" .framework)"
  binary_path="$framework/$framework_name"
  output_dsym="$dsym_dir/$framework_name.framework.dSYM"

  if [ ! -f "$binary_path" ] || [ -d "$output_dsym" ]; then
    continue
  fi

  echo "Generating dSYM for $framework_name.framework"
  dsymutil -o "$output_dsym" "$binary_path"
done
