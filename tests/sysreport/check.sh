#!/usr/bin/env bash
# Runs the sanitizer on the fixture; fails if a fake secret survives or a keeper is lost.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
bin="$here/../../bin/mb-sysreport"
out="$(HOME=/home/alice.smith python3 - "$bin" "$here/sample-input.txt" <<'PY'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("sysreport", sys.argv[1])
spec = importlib.util.spec_from_loader("sysreport", loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)
m.known_names = lambda: {"user": ["alice.smith", "Alice Smith"], "host": ["fakebox-7"], "wifi": ["HomeNet-5G"]}
print(m.scrub(open(sys.argv[2]).read())[0])
PY
)"
fail=0
hidden="$(echo "my philips and mynas" | "$bin" scrub --hide "Philips, mynas")"
case "$hidden" in *hilips*|*ynas*) echo "LEAK: hide words"; fail=1 ;; esac
mail="$(echo "jane@corp-example.org" | "$bin" scrub --hide jane)"
case "$mail" in *corp-example*) echo "LEAK: email with hide word"; fail=1 ;; esac
vol="$(echo "UUID=5A3B-9C1D" | "$bin" scrub)"
case "$vol" in *5A3B*) echo "LEAK: volume serial"; fail=1 ;; esac
raw="$(echo "user@example.org 10.1.2.3" | "$bin" scrub --raw)"
[ "$raw" = "user@example.org 10.1.2.3" ] || { echo "LOST: raw mode"; fail=1; }
for s in alice Smith fakebox alice@ hunter2 192.168 10.0.0.5 fe80 2001:db8 \
         AA:BB:CC 00-1a-2b 123e4567 a41abfd4 SN12345678 ZX99 0x0000E286 HomeNet Zm9vYmFy; do
  if grep -qi -- "$s" <<<"$out"; then echo "LEAK: $s"; fail=1; fi
done
if grep -q $'\033' <<<"$out"; then echo "LEAK: ansi"; fail=1; fi
for k in 127.0.0.1 0.0.0.0 ::1 1.21.1.24 1.2.3.4 12:34:56 2.40.1.1-1 polkit-agent-helper@0-12294-1082287.service; do
  grep -qF -- "$k" <<<"$out" || { echo "LOST: $k"; fail=1; }
done
[ "$fail" = 0 ] && echo "sysreport sanitizer: ok"
exit "$fail"
