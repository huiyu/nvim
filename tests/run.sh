#!/bin/sh
# Run tests/*_spec.lua against the real configuration, one at a time.
#
#   tests/run.sh                         every spec
#   tests/run.sh hunk_actions codediff   some specs (name, name_spec or path)
#
# Specs load the config with `-u init.lua` so they exercise what actually ships,
# not a stripped-down harness. Each spec calls helper.done(), which `cquit 1`s on
# failure -- a plain `-c qa` would exit 0 even after an uncaught Lua error.
#
# One at a time on purpose: several specs share what one Nvim at a time
# expects -- the llama-server util.llama shares between Nvims, git index and
# gitsigns watcher timing -- and fail when run side by side.

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

# Specs never download. CodeDiff fetches its native diff library on first
# setup and its file watcher on first view when they are missing; with these
# set, a missing library is a failing spec (tests/codediff_spec.lua says so)
# and a missing watcher falls back to polling. CI installs the library itself.
export VSCODE_DIFF_NO_AUTO_INSTALL=1
export CODEDIFF_WATCHER_NO_AUTO_INSTALL=1

# The specs to run: every one, or the ones named.
specs=""
if [ $# -eq 0 ]; then
  for spec in tests/*_spec.lua; do
    [ -e "$spec" ] && specs="$specs $spec"
  done
else
  for name in "$@"; do
    case $name in
      */*) spec=$name ;;
      *_spec.lua) spec=tests/$name ;;
      *_spec) spec=tests/$name.lua ;;
      *) spec=tests/${name}_spec.lua ;;
    esac
    if [ ! -e "$spec" ]; then
      echo "no spec $spec" >&2
      exit 2
    fi
    specs="$specs $spec"
  done
fi

status=0
for spec in $specs; do
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
