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
cat "$MB_WINDOWS"
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

echo ok
