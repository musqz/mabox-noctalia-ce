#!/usr/bin/env bash
# Check that a built ISO, or its rootfs.sfs, carries this repo's current files. Read-only, no root.
# usage: tests/iso-check.sh <file.iso|rootfs.sfs>
#        tests/iso-check.sh --host     the installed system: run it before building the snapshot
# For an ISO the rootfs.sfs is first copied out to a temp folder (it can be many GB); the work folder of the
# last build has it ready: <workdir>/iso/mabox/x86_64/rootfs.sfs
set -euo pipefail

usage() { echo "usage: iso-check.sh <file.iso|rootfs.sfs> | --host" >&2; exit 2; }
(($# == 1)) || usage
src=$1
[[ $src != -* || $src == --host ]] || usage
root=$(cd "$(dirname "$0")/.." && pwd)

tmp=$(mktemp -d)
# unsquashfs keeps the read-only directory modes of the image.
trap 'chmod -R u+rwX "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT

where=iso
if [[ $src == --host ]]; then
    fs=
    where=host
else
    command -v unsquashfs >/dev/null || { echo "error: unsquashfs is not installed (squashfs-tools)" >&2; exit 2; }
    sfs=$src
    if [[ $src == *.iso ]]; then
        command -v xorriso >/dev/null || { echo "error: xorriso is not installed (libisoburn)" >&2; exit 2; }
        sfs=$tmp/rootfs.sfs
        xorriso -osirrox on -indev "$src" -extract /mabox/x86_64/rootfs.sfs "$sfs" >/dev/null 2>&1 \
            || { echo "error: rootfs.sfs not found in $src" >&2; exit 2; }
    fi

    # One extraction of what the repo installs: the commands, the session launcher, the key lists, the plugins,
    # the noctalia files and the skel. Not compared: systemd units, file-manager actions and file modes.
    paths=(usr/share/mabox-noctalia-ce etc/skel/.config/mabox-noctalia-ce usr/bin/mabox-noctalia-ce)
    for f in "$root"/bin/*; do
        [[ -f $f ]] && paths+=("usr/bin/$(basename "$f")")
    done
    unsquashfs -n -f -d "$tmp/fs" "$sfs" "${paths[@]}" >"$tmp/unsquashfs.log" 2>&1 || true
    if [[ ! -d $tmp/fs ]]; then
        echo "error: could not read $sfs" >&2
        tail -n 5 "$tmp/unsquashfs.log" >&2
        exit 2
    fi
    fs=$tmp/fs
fi

problems=0
report() { echo "$1"; problems=$((problems + 1)); }

for f in "$root"/bin/*; do
    [[ -f $f ]] || continue
    name=$(basename "$f")
    if [[ -L $fs/usr/bin/$name ]]; then
        report "SYMLINK  usr/bin/$name (a stopgap link, not the installed package file)"
    elif [[ ! -f $fs/usr/bin/$name ]]; then
        report "MISSING  usr/bin/$name"
    elif ! cmp -s "$f" "$fs/usr/bin/$name"; then
        report "DIFFERS  usr/bin/$name"
    fi
done

compare() { # label repo-dir iso-dir [diff -x args...]
    local label=$1 a=$2 b=$3
    shift 3
    if [[ ! -d $b ]]; then
        report "MISSING  $label"
        return
    fi
    while IFS= read -r line; do
        report "$label: $line"
    done < <(diff -rq "$@" "$a" "$b" | sed "s#$a#repo#; s#$b#$where#")
}

for pair in "lib/mabox-noctalia-ce:usr/bin/mabox-noctalia-ce" "lists/keys.csv:usr/share/mabox-noctalia-ce/keys.csv" "lists/keys-profiles.csv:usr/share/mabox-noctalia-ce/keys-profiles.csv"; do
    if [[ ! -f $fs/${pair#*:} ]]; then
        report "MISSING  ${pair#*:}"
    elif ! cmp -s "$root/${pair%%:*}" "$fs/${pair#*:}"; then
        report "DIFFERS  ${pair#*:}"
    fi
done

compare "plugins" "$root/configs/mabox-noctalia-ce/plugins" "$fs/usr/share/mabox-noctalia-ce/plugins"
compare "noctalia files" "$root/configs/noctalia" "$fs/usr/share/mabox-noctalia-ce/noctalia"
compare "skel" "$root/configs/mabox-noctalia-ce" "$fs/etc/skel/.config/mabox-noctalia-ce" -x plugins -x autostart.local

if ((problems)); then
    if [[ $where == host ]]; then
        echo "$problems difference(s): the installed package is older than this repo. Run ./install.sh (it builds and installs the working tree), then run this check again."
    else
        echo "$problems difference(s): the package on the build host was older than this repo. Run ./install.sh, check with --host, then build the snapshot again."
    fi
    exit 1
fi
echo "ok: commands, session launcher, key lists, plugins, noctalia files and skel match the repo"
