"""Offline PTY peer: never imports or launches an AI CLI."""
import json
import os
import sys
import tty

tty.setraw(sys.stdin.fileno())
print("READY:" + json.dumps({"argv": sys.argv[1:], "cwd": os.getcwd(),
                             "marker": os.environ.get("AGENT_TEST_MARKER")}, ensure_ascii=False), flush=True)
pending = bytearray()
while True:
    piece = os.read(sys.stdin.fileno(), 1)
    if not piece:
        break
    if piece in (b"\r", b"\n"):
        os.write(sys.stdout.fileno(), b"SEEN:" + bytes(pending) + b"\n")
        pending.clear()
    else:
        pending.extend(piece)
