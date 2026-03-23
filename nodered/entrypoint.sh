#!/bin/sh
set -eu

target_flow="/data/${FLOWS:-flows.json}"
starter_flow="/usr/src/node-red/course/flows.json"
starter_settings="/usr/src/node-red/course/settings.js"
managed_flow_checksum="/data/.course-demo-flow.cksum"

flow_checksum() {
  cksum "$1" | awk '{print $1 ":" $2}'
}

if [ -f "$starter_settings" ] && [ ! -f /data/settings.js ]; then
  cp "$starter_settings" /data/settings.js
fi

if [ -f "$starter_flow" ]; then
  should_sync_flow=false

  if [ ! -f "$target_flow" ] || [ ! -s "$target_flow" ] || grep -Eq '^[[:space:]]*\[[[:space:]]*\][[:space:]]*$' "$target_flow"; then
    should_sync_flow=true
  elif [ -f "$managed_flow_checksum" ]; then
    current_checksum="$(flow_checksum "$target_flow")"
    managed_checksum="$(cat "$managed_flow_checksum" 2>/dev/null || true)"

    if [ "$current_checksum" = "$managed_checksum" ]; then
      should_sync_flow=true
    fi
  fi

  if [ "$should_sync_flow" = true ]; then
    cp "$starter_flow" "$target_flow"
    flow_checksum "$target_flow" > "$managed_flow_checksum"
  elif [ -f "$target_flow" ] && [ ! -f "$managed_flow_checksum" ]; then
    current_checksum="$(flow_checksum "$target_flow")"
    starter_checksum="$(flow_checksum "$starter_flow")"

    if [ "$current_checksum" = "$starter_checksum" ]; then
      printf '%s\n' "$current_checksum" > "$managed_flow_checksum"
    fi
  fi
fi

exec npm start -- --userDir /data
