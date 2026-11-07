#!/usr/bin/env bash
# mb-migrate steps that edit rc.xml, run against a copy of the shipped file.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

conf=$tmp/conf
mkdir -p "$conf/mabox-noctalia-ce" "$tmp/state"
migrate() {
    HOME=$tmp XDG_STATE_HOME=$tmp/state XDG_CONFIG_HOME=$conf bash "$root/bin/mb-migrate"
    rm -f "$tmp/state/mabox-noctalia-ce/config-version"
}
count() { grep -c "$1" "$conf/mabox-noctalia-ce/rc.xml" || true; }
valid() { python3 -c "import sys, xml.dom.minidom as m; m.parse(sys.argv[1])" "$conf/mabox-noctalia-ce/rc.xml"; }

# migrate_7: the Cava panel key is added once, and an existing binding of the key is left alone.
grep -v 'key="W-A-v"' "$root/configs/mabox-noctalia-ce/rc.xml" > "$conf/mabox-noctalia-ce/rc.xml"
migrate; migrate
[[ $(count 'key="W-A-v"') == 1 ]] || { echo "FAIL migrate_7: expected one W-A-v bind"; exit 1; }
valid || { echo "FAIL migrate_7: rc.xml is no longer valid"; exit 1; }

sed -i 's|command.action="noctalia msg panel-open mabox/cava:main"|command.action="mine"|' "$conf/mabox-noctalia-ce/rc.xml"
migrate
[[ $(count 'command.action="mine"') == 1 && $(count 'key="W-A-v"') == 1 ]] || { echo "FAIL migrate_7: overwrote the user's own W-A-v"; exit 1; }

echo ok
