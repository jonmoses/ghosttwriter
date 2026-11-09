#!/bin/sh
# Pipes hook fixtures through gtw into a fake socket server and checks what arrives.
set -eu
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/.." && pwd); repo=$(cd "$root/.." && pwd)
swift build --package-path "$repo/macos/gtw" -c release --product gtw >/dev/null
gtw="$(swift build --package-path "$repo/macos/gtw" -c release --show-bin-path)/gtw"
tmp=$(mktemp -d); sock="$tmp/gtw.sock"; log="$tmp/requests.jsonl"
python3 -I - "$sock" "$log" <<'PY' &
import json, os, socket, sys
path, log = sys.argv[1], sys.argv[2]
s = socket.socket(socket.AF_UNIX); s.bind(path); s.listen(); open(path + ".ready", "w").close()
for _ in range(2):
    c, _ = s.accept(); line = b""
    while not line.endswith(b"\n"): line += c.recv(65536)
    open(log, "a").write(line.decode()); c.sendall(b'{"ok":true,"data":{}}\n'); c.close()
PY
while [ ! -f "$sock.ready" ]; do sleep 0.1; done
export GHOSTTWRITER_SURFACE=6F1C0D2E-0000-4000-8000-000000000001 GHOSTTWRITER_SOCKET="$sock"
"$gtw" hook < "$here/fixtures/session-start.json"
"$gtw" hook < "$here/fixtures/stop.json"
wait
python3 -I - "$log" "$root/hooks/hooks.json" <<'PY'
import json, sys
reqs = [json.loads(l) for l in open(sys.argv[1])]
assert [r["args"]["event"] for r in reqs] == ["SessionStart", "Stop"], reqs
assert reqs[0]["args"]["session_id"] == "abc-123" and reqs[0]["op"] == "hook"
hooks = json.load(open(sys.argv[2]))["hooks"]
want = {"SessionStart", "UserPromptSubmit", "PostToolUse", "Notification", "Stop", "SessionEnd"}
assert set(hooks) == want, set(hooks)
for ev in want:
    h = hooks[ev][0]["hooks"][0]
    assert h == {"type": "command", "command": "gtw hook", "timeout": 2}, (ev, h)
print("hooks ok")
PY
# claude() wrapper: injects /color only for a bare interactive start.
fake="$tmp/bin"; mkdir -p "$fake"; printf '#!/bin/sh\necho "$@"\n' > "$fake/claude"; chmod +x "$fake/claude"
out=$(PATH="$fake:$PATH" TABCOLOR=pink TERM_PROGRAM=ghostty zsh -f -i -c "source '$root/shell/ghosttwriter.zsh'; claude; claude -p hi; claude --resume x")
[ "$out" = "$(printf '/color pink\n-p hi\n--resume x')" ] || { echo "wrapper: $out"; exit 1; }
echo "wrapper ok"
