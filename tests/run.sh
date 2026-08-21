#!/bin/sh
# Run every tests/*_spec.lua against the real configuration.
#
# Specs load the config with `-u init.lua` so they exercise what actually ships,
# not a stripped-down harness. Each spec calls helper.done(), which `cquit 1`s on
# failure -- a plain `-c qa` would exit 0 even after an uncaught Lua error.

set -eu
cd "$(dirname "$0")/.."

status=0
for spec in tests/*_spec.lua; do
  [ -e "$spec" ] || continue
  printf '\n== %s\n' "$spec"
  if ! nvim --headless -u init.lua -i NONE -c "luafile $spec" -c qa; then
    status=1
  fi
done

if [ "$status" -eq 0 ]; then
  printf '\nall specs passed\n'
else
  printf '\nSPEC FAILURES\n'
fi
exit "$status"
