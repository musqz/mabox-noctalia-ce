#!/usr/bin/env bash
# mb-session against stubbed wlrctl and wtype.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'kill $sp 2>/dev/null || true; rm -rf "$tmp"' EXIT
sp=

mkdir -p "$tmp/bin" "$tmp/.local/share/applications" "$tmp/run"
cat > "$tmp/bin/wlrctl" <<'STUB'
#!/usr/bin/env bash
if [[ ${2:-} == close ]]; then
    grep -v "^${3#app_id:}:" "$MB_WINDOWS" > "$MB_WINDOWS.new" || true
    mv "$MB_WINDOWS.new" "$MB_WINDOWS"
else
    cat "$MB_WINDOWS"
fi
STUB
cat > "$tmp/bin/wtype" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$MB_WTYPE"
STUB
chmod +x "$tmp/bin/"*
export PATH=$tmp/bin:$PATH HOME=$tmp XDG_CONFIG_HOME=$tmp/.config XDG_RUNTIME_DIR=$tmp/run
export MB_WINDOWS=$tmp/windows MB_WTYPE=$tmp/wtype MB_SESSION_WAIT=0
ms=$root/bin/mb-session
fail() { echo "FAIL $1"; exit 1; }

printf '[Desktop Entry]\nName=Sleeper\nExec=sleep 5 %%U\n' > "$tmp/.local/share/applications/sleeper.desktop"
printf '[Desktop Entry]\nName=Touch\nStartupWMClass=Toucher\nExec=touch %s/started\n' "$tmp" > "$tmp/.local/share/applications/touch.desktop"
sleep 77 &
sp=$!
printf '[Desktop Entry]\nName=Sl\nExec=sleep 5\n' > "$tmp/.local/share/applications/sl.desktop"

printf 'sleeper: a\nToucher: b\nfirefox: c\nnoctalia: x\nq-term-right: y\nmystery: z\n' > "$MB_WINDOWS"
out=$("$ms" capture 2>/dev/null)
grep -qx $'firefox\tfirefox --new-window' <<<"$out" || fail "override: $out"
grep -qx "Toucher.touch $tmp/started" <<<"$out" || fail "StartupWMClass: $out"
grep -q '^mystery' <<<"$out" && fail "unmappable kept"
grep -q '^noctalia\|^q-term' <<<"$out" && fail "internal windows kept"
grep -qx $'sleeper\tsleep 77' <<<"$out" || fail "running cmdline: $out"

"$ms" save work >/dev/null 2>&1
[[ $("$ms" list) == $'work\t1\t3' ]] || fail "list: $("$ms" list)"
"$ms" save hobby --workspace 1 2>/dev/null && fail "shared workspace accepted"
"$ms" save hobby 2>/dev/null; [[ $("$ms" list | grep -c .) == 2 ]] || fail "second session"
"$ms" list | grep -qx $'hobby\t2\t3' || fail "next free workspace"

"$ms" rename hobby play; "$ms" list | grep -q '^play' || fail "rename"
"$ms" rename play work 2>/dev/null && fail "rename onto existing"
"$ms" rename "bad/name" x 2>/dev/null && fail "bad name accepted"
"$ms" remove play firefox; [[ $("$ms" list | grep play) == $'play\t2\t2' ]] || fail "remove app"
"$ms" delete play; "$ms" delete play 2>/dev/null && fail "delete twice"

# start: running apps are skipped, missing ones launch, the workspace bind is pressed
"$ms" save touch 2>/dev/null; printf 'Toucher: b\n' > "$MB_WINDOWS"
"$ms" delete touch
printf '# workspace 3\nToucher\ttouch %s/started\nfirefox\ttrue\n' "$tmp" > "$tmp/.config/mabox-noctalia-ce/sessions/t.session"
printf 'firefox: c\n' > "$MB_WINDOWS"
"$ms" start t; sleep 0.3
[[ -f $tmp/started ]] || fail "start did not launch the missing app"
grep -qx -- '-M logo -M alt -M ctrl -k F3 -m ctrl -m alt -m logo' "$MB_WTYPE" || fail "workspace bind: $(cat "$MB_WTYPE")"
rm "$tmp/started"; printf 'firefox: c\nToucher: b\n' > "$MB_WINDOWS"
"$ms" start t; sleep 0.3
[[ ! -f $tmp/started ]] || fail "start relaunched a running app"

# save --new-only keeps only windows that were not in the baseline
printf 'firefox: c\n' > "$MB_WINDOWS"; "$ms" baseline
printf 'firefox: c\nToucher: b\n' > "$MB_WINDOWS"
"$ms" save fresh --new-only 2>/dev/null
[[ $("$ms" show fresh | tail -n +2 | wc -l) == 1 ]] || fail "new-only: $("$ms" show fresh)"

# a second window of an app that was already open counts as new
printf 'Toucher: b\n' > "$MB_WINDOWS"; "$ms" baseline
printf 'Toucher: b\nToucher: b2\n' > "$MB_WINDOWS"
"$ms" save more --new-only 2>/dev/null || fail "new-only: extra window of a known app"

# every window is saved: two windows of one app give two lines; a quake terminal window is left out
printf 'firefox: a\nfirefox: b\nfirefox: q-term-left\n' > "$MB_WINDOWS"
"$ms" delete fresh; "$ms" delete more; "$ms" save multi 2>/dev/null || fail "save multi"
[[ $("$ms" show multi | grep -c '^firefox') == 2 ]] || fail "one line per window: $("$ms" show multi)"
# start launches only the missing window
printf '# workspace 1\nToucher\ttouch %s/started\nToucher\ttouch %s/started2\n' "$tmp" "$tmp" > "$tmp/.config/mabox-noctalia-ce/sessions/two.session"
printf 'Toucher: b\n' > "$MB_WINDOWS"; rm -f "$tmp/started" "$tmp/started2"
"$ms" start two; sleep 0.3
[[ ! -f $tmp/started && -f $tmp/started2 ]] || fail "start: count-aware"

# the root menu is valid XML and lists the sessions
"$ms" menu | python3 -c "import sys, xml.dom.minidom as m; d = m.parseString(sys.stdin.read()); assert 'multi' in d.toxml()" || fail "menu"

# a session can own a range of workspaces; ranges may not overlap
for n in multi two t work; do "$ms" delete "$n" 2>/dev/null || true; done
printf 'firefox: a\n' > "$MB_WINDOWS"
"$ms" save wide --workspace 1-2 2>/dev/null || fail "range save"
"$ms" list | grep -qx $'wide\t1-2\t1' || fail "range list: $("$ms" list)"
"$ms" save other --workspace 2 2>/dev/null && fail "overlap accepted"
"$ms" save other 2>/dev/null; "$ms" list | grep -qx $'other\t3\t1' || fail "next free after a range"

# replace: the session you are in is saved, every window is closed, the target starts
printf 'firefox: a\nToucher: b\n' > "$MB_WINDOWS"; rm -f "$tmp/started"
printf '# workspace 3\nToucher\ttouch %s/started\n' "$tmp" > "$tmp/.config/mabox-noctalia-ce/sessions/other.session"
MB_SESSION_WORKSPACE=1 "$ms" start other --replace; sleep 0.3
[[ $("$ms" show wide | grep -c '^firefox') == 1 && $("$ms" show wide | grep -c '^Toucher') == 0 ]] || fail "replace did not save the old session: $("$ms" show wide)"
[[ -f $tmp/started ]] || fail "replace did not start the target"
[[ ! -s $MB_WINDOWS ]] || fail "replace left windows open"

# replace keeps the other sessions' apps out of the saved one
printf '# workspace 2\nfirefox\ttrue\n' > "$tmp/.config/mabox-noctalia-ce/sessions/other.session"
printf '# workspace 1-2\nToucher\ttouch x\n' > "$tmp/.config/mabox-noctalia-ce/sessions/wide.session"
"$ms" delete other
printf '# workspace 3\nfirefox\ttrue\n' > "$tmp/.config/mabox-noctalia-ce/sessions/other.session"
printf 'firefox: a\nToucher: b\n' > "$MB_WINDOWS"
MB_SESSION_WORKSPACE=1 "$ms" start other --replace; sleep 0.3
[[ $("$ms" show wide | grep -c '^firefox') == 0 ]] || fail "replace saved another session's app: $("$ms" show wide)"

# login switch
[[ $("$ms" login) == on ]] || fail "login default"
"$ms" login off; [[ $("$ms" login) == off ]] || fail "login off"
grep -qx session "$tmp/.config/mabox-noctalia-ce/autostart.skip" || fail "login off: skip file"
"$ms" login on; [[ $("$ms" login) == on ]] || fail "login on"

echo ok
