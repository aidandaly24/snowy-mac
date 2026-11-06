#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
cd "$project_root"

# Build first so a failed compilation leaves the current app running.
./scripts/build-app.sh

# Quit only instances launched from this checkout before loading the new binary.
app_binary="$project_root/build/Snowy.app/Contents/MacOS/Snowy"
while IFS= read -r app_pid; do
  [[ -n "$app_pid" ]] || continue
  running_binary="$(ps -ww -p "$app_pid" -o comm= 2>/dev/null || true)"
  [[ "${running_binary:A}" == "$app_binary" ]] || continue
  kill -TERM "$app_pid" 2>/dev/null || continue
  for attempt in {1..50}; do
    kill -0 "$app_pid" 2>/dev/null || break
    sleep 0.1
  done
  if kill -0 "$app_pid" 2>/dev/null; then
    print -u2 "Snowy is still quitting. Close it, then run this command again."
    exit 1
  fi
done < <(pgrep -x Snowy || true)

if [[ -n "${SNOWY_SPACE_DIAGNOSTICS_PATH:-}" ]]; then
  open --env "SNOWY_SPACE_DIAGNOSTICS_PATH=$SNOWY_SPACE_DIAGNOSTICS_PATH" "$project_root/build/Snowy.app"
else
  open "$project_root/build/Snowy.app"
fi
