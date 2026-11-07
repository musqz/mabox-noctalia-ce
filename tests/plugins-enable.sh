#!/usr/bin/env bash
# mb-plugins-enable against a fake noctalia: fresh user, existing install, a plugin added later, a plugin left disabled.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin" "$tmp/state"

cat > "$tmp/bin/noctalia" <<'STUB'
#!/usr/bin/env bash
# state file: "id enabled|disabled" per line; enable calls are logged
f=$FAKE_STATE
case "$3" in
    list) while read -r id st; do echo "$id [mabox-dev] 0.1.0 $st requires mpv, socat"; done < "$f" ;;
    enable) echo "$4" >> "$FAKE_LOG"; sed -i "s|^$4 .*|$4 enabled|" "$f" ;;
esac
STUB
chmod +x "$tmp/bin/noctalia"

run() { FAKE_STATE=$tmp/plugins FAKE_LOG=$tmp/log XDG_STATE_HOME=$tmp/state PATH="$tmp/bin:$PATH" "$root/bin/mb-plugins-enable"; }
enabled() { sort "$tmp/log" 2>/dev/null | tr '\n' ' '; }
check() { [[ "$(enabled)" == "$2" ]] || { echo "FAIL $1: enabled [$(enabled)] expected [$2]"; exit 1; }; }

printf 'mabox/a disabled\nmabox/b disabled\n' > "$tmp/plugins"; : > "$tmp/log"
run; check "fresh user enables everything" "mabox/a mabox/b "

: > "$tmp/log"; run; check "second run does nothing" ""

rm -rf "$tmp/state"; printf 'mabox/a enabled\nmabox/b disabled\n' > "$tmp/plugins"; : > "$tmp/log"
run; check "existing install enables nothing on its first run" ""
printf 'mabox/a enabled\nmabox/b disabled\nmabox/c disabled\n' > "$tmp/plugins"
run; check "a plugin added later is enabled once, b stays disabled" "mabox/c "

# migrate_6 puts the call into an existing autostart, once.
conf=$tmp/conf
mkdir -p "$conf/mabox-noctalia-ce" "$tmp/state2"
printf 'noctalia &\n(sleep 3 && noctalia msg plugins source add mabox path /usr/share/mabox-noctalia-ce/plugins) >/dev/null 2>&1 &\necho after\n' > "$conf/mabox-noctalia-ce/autostart"
for _ in 1 2; do
    HOME=$tmp XDG_STATE_HOME=$tmp/state2 XDG_CONFIG_HOME=$conf bash "$root/bin/mb-migrate"
    rm -f "$tmp/state2/mabox-noctalia-ce/config-version"
done
[[ $(grep -c mb-plugins-enable "$conf/mabox-noctalia-ce/autostart") == 1 ]] || { echo "FAIL migrate_6: expected one mb-plugins-enable line"; exit 1; }
bash -n "$conf/mabox-noctalia-ce/autostart" || { echo "FAIL migrate_6: autostart is no longer valid"; exit 1; }

echo ok
