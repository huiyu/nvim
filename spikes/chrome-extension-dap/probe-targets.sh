#!/usr/bin/env bash
# SPIKE: does Chrome still load an unpacked extension from the command line,
# and are its service-worker / page targets exposed over CDP?
set -uo pipefail
SPIKE="$HOME/.config/nvim/spikes/chrome-extension-dap"
EXT="$SPIKE/output/chrome-mv3-dev"
PROF="$SPIKE/chrome-profile"
PORT=9333
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

rm -rf "$PROF"; mkdir -p "$PROF"
"$CHROME" --headless=new --remote-debugging-port=$PORT \
  --user-data-dir="$PROF" --no-first-run --no-default-browser-check \
  --load-extension="$EXT" --disable-extensions-except="$EXT" \
  about:blank > "$SPIKE/chrome.log" 2>&1 &
PID=$!
for _ in $(seq 1 40); do curl -sf "http://127.0.0.1:$PORT/json/version" >/dev/null && break; sleep 0.25; done

echo "=== targets ==="
curl -s "http://127.0.0.1:$PORT/json/list" | python3 -c '
import sys,json
try: ts=json.load(sys.stdin)
except Exception as e: print("  (no JSON:",e,")"); sys.exit()
for t in ts: print("  %-16s %s" % (t["type"], t["url"][:100]))
print("  ---- total:",len(ts))
'
echo "=== extension registered? ==="
curl -s "http://127.0.0.1:$PORT/json/list" | grep -c "chrome-extension://" | sed 's/^/  chrome-extension targets: /'
kill $PID 2>/dev/null; wait $PID 2>/dev/null
echo "(chrome stopped)"
