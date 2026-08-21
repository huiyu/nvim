#!/bin/sh
# Run every tests/*_spec.lua against the real configuration.
#
# Specs load the config with `-u init.lua` so they exercise what actually ships,
# not a stripped-down harness. Each spec calls helper.done(), which `cquit 1`s on
# failure -- a plain `-c qa` would exit 0 even after an uncaught Lua error.

set -eu
cd "$(dirname "$0")/.."

# The spec is pcall'd rather than run by a bare `luafile`. A spec that *raises*
# never reaches helper.done(), so without this wrapper its cquit never fires and
# the run would exit 0 -- a crashed spec would read as a passing one.
BOOTSTRAP='local ok, err = pcall(vim.cmd, "luafile " .. vim.env.SPEC)
if not ok then
  print("ERROR - " .. tostring(err))
  vim.cmd("cquit 1")
end'

status=0
for spec in tests/*_spec.lua; do
  [ -e "$spec" ] || continue
  printf '\n== %s\n' "$spec"
  # `qa!` is only a fallback for a spec that forgot helper.done(); the bang
  # keeps a modified scratch buffer from stalling the run on E37.
  if ! SPEC="$spec" nvim --headless -u init.lua -i NONE -c "lua $BOOTSTRAP" -c 'qa!'; then
    status=1
  fi
done

if [ "$status" -eq 0 ]; then
  printf '\nall specs passed\n'
else
  printf '\nSPEC FAILURES\n'
fi
exit "$status"
