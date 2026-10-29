#!/usr/bin/env bash
# Install the packages mabox-noctalia-ce needs; already installed ones are skipped.
# --uninstall removes only the packages this script installed.
set -euo pipefail

dir=$(dirname "$(readlink -f "$0")")
state="${XDG_DATA_HOME:-$HOME/.local/share}/mabox-noctalia-ce/installed"
read_list() { grep -v '^\s*\(#\|$\)' "$1"; }

case ${1:-} in
    "") ;;
    --uninstall)
        [[ -s $state ]] || { echo "Nothing recorded in $state"; exit 0; }
        mapfile -t pkgs < <(while read -r p; do pacman -Qq "$p" 2>/dev/null; done < "$state")
        (( ${#pkgs[@]} )) && sudo pacman -Rns "${pkgs[@]}"
        rm -f "$state"
        exit 0 ;;
    *) echo "usage: ${0##*/} [--uninstall]" >&2; exit 2 ;;
esac

mkdir -p "$(dirname "$state")"
record() { printf '%s\n' "$@" >> "$state"; }

pacman -Sl maboxlinux >/dev/null 2>&1 || { echo "Repo [maboxlinux] is not enabled in /etc/pacman.conf (needed for noctalia 5.4+)." >&2; exit 1; }

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
echo "Building mabox-noctalia-ce"
(cd "$dir/packaging" && makepkg -si)
record mabox-noctalia-ce
echo "Done. Pick \"Noctalia CE\" at the login screen."
