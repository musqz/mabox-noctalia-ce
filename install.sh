#!/usr/bin/env bash
# Install the packages mabox-noctalia-ce needs, then build and install mabox-noctalia-ce itself.
# Already installed packages are skipped; mabox-noctalia-ce is rebuilt when bin/ differs from /usr/bin.
# --uninstall removes only the packages this script installed.
# --reset-config backs up and overwrites the user config with the one in this repo.
# --save-config backs up the user config without changing it.
# --sync-configs copies edited live config files back into this repo.
# --recover-profile [timestamp] restores the newest --reset-config backup, or the one with the given timestamp
# (also --save-config copies).
set -euo pipefail

dir=$(dirname "$(readlink -f "$0")")
data="${XDG_DATA_HOME:-$HOME/.local/share}/mabox-noctalia-ce"
state="$data/installed"
read_list() { grep -v '^\s*\(#\|$\)' "$1"; }

conf="$HOME/.config"
backup_config() {
    local tag=${1:-bak} ts d
    ts=$(date +%Y%m%d-%H%M%S)
    for d in mabox-noctalia-ce noctalia; do
        [[ -d $conf/$d ]] || continue
        cp -a "$conf/$d" "$conf/$d.$tag-$ts" || { rm -rf "$conf/$d.$tag-$ts"; echo "Backup of $conf/$d failed; nothing changed." >&2; exit 1; }
        echo "Backup: $conf/$d.$tag-$ts"
    done
}

case ${1:-} in
    "") ;;
    --save-config)
        [[ -d $conf/mabox-noctalia-ce || -d $conf/noctalia ]] || { echo "Nothing to save." >&2; exit 1; }
        backup_config save
        exit 0 ;;
    --sync-configs)
        git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || { echo "$dir is not a git checkout." >&2; exit 1; }
        n=0
        while IFS= read -r -d '' f; do
            live="$conf/${f#configs/}"
            [[ -f $live ]] && ! cmp -s "$live" "$dir/$f" || continue
            cp "$live" "$dir/$f"
            echo "synced ${f#configs/}"
            n=$((n + 1))
        done < <(git -C "$dir" ls-files -z configs/mabox-noctalia-ce configs/noctalia | grep -zv "autostart.local$")
        (( n )) && echo "Review with: git -C $dir diff" || echo "No changes."
        exit 0 ;;
    --recover-profile)
        pick=${2:-$(ls -1d "$conf"/mabox-noctalia-ce.bak-* 2>/dev/null | sed 's/.*\.bak-//' | sort | tail -n1 || true)}
        tag=
        for t in bak save; do
            [[ $pick =~ ^[0-9]{8}-[0-9]{6}$ && -d $conf/mabox-noctalia-ce.$t-$pick ]] && { tag=$t; break; }
        done
        if [[ -z $tag ]]; then
            echo "No backup${2:+ $2}. Available:" >&2
            ls -1d "$conf"/mabox-noctalia-ce.{bak,save}-* 2>/dev/null | sed 's|.*/mabox-noctalia-ce\.|  |' >&2 || true
            exit 1
        fi
        backup_config
        for d in mabox-noctalia-ce noctalia; do
            [[ -d $conf/$d.$tag-$pick ]] || continue
            rm -rf "$conf/$d"
            cp -a "$conf/$d.$tag-$pick" "$conf/$d"
        done
        labwc --reconfigure >/dev/null 2>&1 || true
        echo "Config restored from $tag-$pick. Log out and back in to apply it all."
        exit 0 ;;
    --uninstall)
        { noctalia msg plugins disable musqz/music; noctalia msg plugins disable musqz/colors; } >/dev/null 2>&1 \
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
    *) echo "usage: ${0##*/} [--uninstall|--reset-config|--save-config|--sync-configs|--recover-profile [timestamp]]" >&2; exit 2 ;;
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
built=()
self=
trap '[[ -z $tmp ]] || rm -rf "$tmp"' EXIT
while read -r -u 3 cmd url; do
    command -v "$cmd" >/dev/null 2>&1 && continue
    echo "Building $cmd from $url"
    tmp=$(mktemp -d)
    git clone --depth 1 "$url" "$tmp/src"
    (cd "$tmp/src/packaging" && makepkg -si)
    record "$(cd "$tmp/src/packaging" && makepkg --printsrcinfo | sed -n 's/^pkgname = //p')"
    built+=("$cmd")
    rm -rf "$tmp"; tmp=
done 3< <(read_list "$dir/lists/github.txt")

for c in labwc noctalia; do
    command -v "$c" >/dev/null 2>&1 || { echo "$c is not in PATH" >&2; exit 1; }
done
stale=
for f in "$dir"/bin/*; do cmp -s "$f" "/usr/bin/${f##*/}" || stale=1; done
if [[ -n $stale ]] || ! pacman -Qq mabox-noctalia-ce >/dev/null 2>&1; then
    echo "Building mabox-noctalia-ce"
    new=; pacman -Qq mabox-noctalia-ce >/dev/null 2>&1 || new=1
    (cd "$dir/packaging" && makepkg -fsi)
    [[ -z $new ]] || record mabox-noctalia-ce
    self=built
fi
rm -rf "$data/plugins"
cp -r "$dir/configs/mabox-noctalia-ce/plugins" "$data/plugins"
if noctalia msg plugins source add musqz-local path "$data/plugins" >/dev/null 2>&1 \
    && { noctalia msg plugins enable musqz/music; noctalia msg plugins enable musqz/colors; } >/dev/null 2>&1; then
    plugins_on=1
else
    plugins_on=0
fi

report() {
    local opt=() p
    echo; echo "Install summary"
    echo "[done] repo packages: ${#need_repo[@]} installed, $(( ${#repo[@]} - ${#need_repo[@]} )) already present"
    echo "[done] AUR packages: ${#need_aur[@]} installed, $(( ${#aur[@]} - ${#need_aur[@]} )) already present"
    echo "[done] GitHub builds: ${built[*]:-none, all present}"
    if [[ $self == built ]]; then echo "[done] mabox-noctalia-ce package built and installed"
    else echo "[skip] mabox-noctalia-ce package already installed"; fi
    echo "[done] plugins copied to $data/plugins"
    if (( plugins_on )); then echo "[done] plugins musqz/music and musqz/colors enabled"
    else echo "[skip] plugins not enabled: noctalia not running or the source call failed"; fi

    echo; echo "To do by hand"
    [[ -d $conf/mabox-noctalia-ce ]] || echo "[todo] config: cp -rn /etc/skel/.config/mabox-noctalia-ce ~/.config/"
    if (( ! plugins_on )); then
        echo "[todo] in the session run:"
        echo "         noctalia msg plugins source add musqz-local path $data/plugins"
        echo "         noctalia msg plugins enable musqz/music"
        echo "         noctalia msg plugins enable musqz/colors"
    fi
    if [[ -f /usr/share/wayland-sessions/noctalia-ce.desktop ]]; then echo "[todo] pick \"Noctalia CE\" at the login screen"
    else echo "[todo] noctalia-ce.desktop session file is missing: reinstall the package"; fi
    echo "[todo] autostart.local (optional): add personal startup programs in ~/.config/mabox-noctalia-ce/autostart.local"
    if command -v kanshi >/dev/null && [[ ! -f $conf/kanshi/config ]]; then echo "[todo] kanshi needs ~/.config/kanshi/config"; fi
    if command -v radicale >/dev/null; then echo "[todo] calendar (optional): run mb-calendar-setup, then Noctalia Settings > Calendar > Local (vdir)"
    else echo "[todo] calendar (optional): sudo pacman -S radicale, then mb-calendar-setup"; fi
    for p in kitty pavucontrol viewnior ffmpeg colormenu beautysolar-icon-theme pyradio pywalfox; do
        pacman -Qq "$p" >/dev/null 2>&1 || opt+=("$p")
    done
    if (( ${#opt[@]} )); then echo "[todo] optional packages not installed: ${opt[*]}"; fi
    echo "[todo] log out and back in"
}
report
