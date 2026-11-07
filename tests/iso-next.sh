#!/usr/bin/env bash
# mb-iso-next with fake sudo and quickbox: menu choices, newest ISO of a directory, no quickbox.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin" "$tmp/isos"
printf '#!/usr/bin/env bash\necho "quickbox-qt ${FAKE_QB:-1.4.0-1}"\n' > "$tmp/bin/pacman"
chmod +x "$tmp/bin/pacman"
for c in sudo quickbox notify-send; do
    printf '#!/usr/bin/env bash\necho "%s $*" >> "$FAKE_LOG"\n' "$c" > "$tmp/bin/$c"
    chmod +x "$tmp/bin/$c"
done
touch -d '2 days ago' "$tmp/isos/old.iso"
touch "$tmp/isos/new.iso"

# noquick: a PATH of fakes and coreutils only, so a real quickbox is not found
mkdir "$tmp/bin-noquick"
for c in sudo notify-send; do cp "$tmp/bin/$c" "$tmp/bin-noquick/"; done
for c in env bash find sort head cut vercmp; do ln -s "$(command -v "$c")" "$tmp/bin-noquick/$c"; done

run() { # choice target [noquick]
    : > "$tmp/log"
    local p="$tmp/bin:$PATH"
    [[ ${3:-} == noquick ]] && p="$tmp/bin-noquick"
    echo "$1" | FAKE_LOG=$tmp/log PATH="$p" "$root/bin/mb-iso-next" "$2" >"$tmp/out" 2>&1 || true
}
check() { grep -q -- "$2" "$tmp/log" || { echo "FAIL $1: log [$(cat "$tmp/log")] expected [$2]"; exit 1; }; }
none() { [[ ! -s $tmp/log ]] || { echo "FAIL $1: log [$(cat "$tmp/log")] expected empty"; exit 1; }; }

run 1 "$tmp/isos/old.iso"; check "1 writes to usb" "sudo mabox-persistence-usb write $tmp/isos/old.iso"
run 2 "$tmp/isos/old.iso"; check "2 starts the vm" "quickbox --iso $tmp/isos/old.iso"
run 3 "$tmp/isos/old.iso"; none "3 does nothing"
run "" "$tmp/isos/old.iso"; none "enter does nothing"
run 2 "$tmp/isos"; check "directory picks the newest" "quickbox --iso $tmp/isos/new.iso"
run 3 "$tmp/isos/old.iso" noquick
grep -q "2) Start in a VM" "$tmp/out" && { echo "FAIL: option 2 shown without quickbox"; exit 1; }
FAKE_QB=1.3.5-1 run 3 "$tmp/isos/old.iso"
grep -q "2) Start in a VM" "$tmp/out" && { echo "FAIL: option 2 shown for quickbox 1.3.5"; exit 1; }
run 2 "$tmp/isos" noquick; check "2 without quickbox notifies" "quickbox is not installed"
echo ok
