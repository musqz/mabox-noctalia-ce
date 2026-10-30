#!/usr/bin/env bash
# Install the packages mabox-noctalia-ce needs, then build and install mabox-noctalia-ce itself.
# Already installed packages are skipped.
# --uninstall removes only the packages this script installed.
# --reset-config backs up and overwrites the user config with the one in this repo.
# --recover-profile [timestamp] restores the newest (or given) --reset-config backup.
set -euo pipefail

dir=$(dirname "$(readlink -f "$0")")
data="${XDG_DATA_HOME:-$HOME/.local/share}/mabox-noctalia-ce"
state="$data/installed"
read_list() { grep -v '^\s*\(#\|$\)' "$1"; }

conf="$HOME/.config"
backup_config() {
    local ts d
    ts=$(date +%Y%m%d-%H%M%S)
    for d in mabox-noctalia-ce noctalia; do
        [[ -d $conf/$d ]] || continue
        cp -a "$conf/$d" "$conf/$d.bak-$ts" || { rm -rf "$conf/$d.bak-$ts"; echo "Backup of $conf/$d failed; nothing changed." >&2; exit 1; }
        echo "Backup: $conf/$d.bak-$ts"
    done
}

case ${1:-} in
    "") ;;
    --recover-profile)
        pick=${2:-$(ls -1d "$conf"/mabox-noctalia-ce.bak-* 2>/dev/null | sed 's/.*\.bak-//' | sort | tail -n1 || true)}
        if [[ ! $pick =~ ^[0-9]{8}-[0-9]{6}$ || ! -d $conf/mabox-noctalia-ce.bak-$pick ]]; then
            echo "No backup${2:+ $2}. Available:" >&2
            ls -1d "$conf"/mabox-noctalia-ce.bak-* 2>/dev/null | sed 's/.*\.bak-/  /' >&2 || true
            exit 1
        fi
        backup_config
        for d in mabox-noctalia-ce noctalia; do
            [[ -d $conf/$d.bak-$pick ]] || continue
            rm -rf "$conf/$d"
            cp -a "$conf/$d.bak-$pick" "$conf/$d"
        done
        labwc --reconfigure >/dev/null 2>&1 || true
        echo "Config restored from backup $pick. Log out and back in to apply it all."
        exit 0 ;;
    --uninstall)
        noctalia msg plugins disable musqz/music >/dev/null 2>&1 \
            && noctalia msg plugins source remove musqz-local >/dev/null 2>&1 \
            || echo "Noctalia not running: run 'noctalia msg plugins source remove musqz-local' in the session." >&2
        rm -rf "$data/plugins"
        [[ -s $state ]] || { echo "Nothing recorded in $state"; exit 0; }
        mapfile -t pkgs < <(while read -r p; do pacman -Qq "$p" 2>/dev/null; done < "$state")
        (( ${#pkgs[@]} )) && sudo pacman -Rns "${pkgs[@]}"
        rm -f "$state"
        exit 0 ;;
    --reset-config)
        backup_config
        rm -rf "$conf/mabox-noctalia-ce"
        mkdir -p "$conf/noctalia"
        cp -r "$dir/configs/mabox-noctalia-ce" "$conf/"
        rm -rf "$conf/mabox-noctalia-ce/plugins"
        chmod 755 "$conf"/mabox-noctalia-ce/menuscripts/* "$conf/mabox-noctalia-ce/autostart"
        cp -rf "$dir/configs/noctalia/." "$conf/noctalia/"
        labwc --reconfigure >/dev/null 2>&1 || true
        echo "Config reset from $dir/configs. Log out and back in to apply it all."
        exit 0 ;;
    *) echo "usage: ${0##*/} [--uninstall|--reset-config|--recover-profile [timestamp]]" >&2; exit 2 ;;
esac

mkdir -p "$(dirname "$state")"
record() { printf '%s\n' "$@" >> "$state"; }

ver=$(pacman -Q noctalia 2>/dev/null | cut -d' ' -f2 || true)
if [[ -z $ver ]] || (( $(vercmp "$ver" 5.4) < 0 )); then
    pacman -Sl maboxlinux >/dev/null 2>&1 || { echo "noctalia 5.4+ is required: enable repo [maboxlinux] in /etc/pacman.conf." >&2; exit 1; }
fi

mapfile -t repo < <(read_list "$dir/lists/pacman.txt")
mapfile -t aur < <(read_list "$dir/lists/aur.txt")

missing() {
    local p
    for p in "$@"; do pacman -Qq "$p" >/dev/null 2>&1 || echo "$p"; done
}

mapfile -t need_repo < <(missing "${repo[@]}")
mapfile -t need_aur < <(missing "${aur[@]}")

if (( ${#need_repo[@]} )); then
    echo "Installing: ${need_repo[*]}"
    sudo pacman -S --needed "${need_repo[@]}"
    record "${need_repo[@]}"
fi

if (( ${#need_aur[@]} )); then
    helper=$(command -v paru || command -v yay || true)
    [[ -n $helper ]] || { echo "No AUR helper (paru/yay). Install by hand: ${need_aur[*]}" >&2; exit 1; }
    echo "Installing from AUR: ${need_aur[*]}"
    "$helper" -S --needed "${need_aur[@]}"
    record "${need_aur[@]}"
fi

tmp=
trap '[[ -z $tmp ]] || rm -rf "$tmp"' EXIT
while read -r -u 3 cmd url; do
    command -v "$cmd" >/dev/null 2>&1 && continue
    echo "Building $cmd from $url"
    tmp=$(mktemp -d)
    git clone --depth 1 "$url" "$tmp/src"
    (cd "$tmp/src/packaging" && makepkg -si)
    record "$(cd "$tmp/src/packaging" && makepkg --printsrcinfo | sed -n 's/^pkgname = //p')"
    rm -rf "$tmp"; tmp=
done 3< <(read_list "$dir/lists/github.txt")

for c in labwc noctalia; do
    command -v "$c" >/dev/null 2>&1 || { echo "$c is not in PATH" >&2; exit 1; }
done
if ! pacman -Qq mabox-noctalia-ce >/dev/null 2>&1; then
    echo "Building mabox-noctalia-ce"
    (cd "$dir/packaging" && makepkg -si)
    record mabox-noctalia-ce
fi
rm -rf "$data/plugins"
cp -r "$dir/configs/mabox-noctalia-ce/plugins" "$data/plugins"
if noctalia msg plugins source add musqz-local path "$data/plugins" >/dev/null 2>&1 \
    && noctalia msg plugins enable musqz/music >/dev/null 2>&1; then
    echo "Enabled plugin musqz/music (/music in the launcher)."
else
    echo "Noctalia is not running. In the session run:"
    echo "  noctalia msg plugins source add musqz-local path $data/plugins"
    echo "  noctalia msg plugins enable musqz/music"
fi
echo "Done. Pick \"Noctalia CE\" at the login screen."
