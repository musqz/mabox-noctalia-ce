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

# migrate_11: the Equalizer key is added once, and an existing binding of the key is left alone.
grep -v 'key="W-A-q"' "$root/configs/mabox-noctalia-ce/rc.xml" > "$conf/mabox-noctalia-ce/rc.xml"
migrate; migrate
[[ $(count 'key="W-A-q"') == 1 ]] || { echo "FAIL migrate_11: expected one W-A-q bind"; exit 1; }
valid || { echo "FAIL migrate_11: rc.xml is no longer valid"; exit 1; }

# migrate_13: the Places key is added once, and an existing binding of the key is left alone.
grep -v 'key="W-p"' "$root/configs/mabox-noctalia-ce/rc.xml" > "$conf/mabox-noctalia-ce/rc.xml"
migrate; migrate
[[ $(count 'key="W-p"') == 1 ]] || { echo "FAIL migrate_13: expected one W-p bind"; exit 1; }
valid || { echo "FAIL migrate_13: rc.xml is no longer valid"; exit 1; }

# migrate_14: pinned windows move to C-W-<letter> from the old defaults, and a user-bound key is left alone.
grep -v -e 'key="C-W-[cnsp]"' "$root/configs/mabox-noctalia-ce/rc.xml" > "$conf/mabox-noctalia-ce/rc.xml"
sed -i 's#</keyboard>#<keybind key="W-A-c"><action name="Execute"><command>mb-pinned configs</command></action></keybind>\n<keybind key="C-W-c"><action name="Execute" command="mb-pinned colors"/></keybind>\n<keybind key="W-A-n"><action name="Execute" command="mb-pinned notes"/></keybind>\n<keybind key="W-S-s"><action name="Execute" command="mb-pinned status"/></keybind>\n<keybind key="C-W-n"><action name="Execute" command="mine"/></keybind>\n</keyboard>#' "$conf/mabox-noctalia-ce/rc.xml"
migrate; migrate
[[ $(count 'key="C-W-c">.*mb-pinned configs') == 1 && $(count 'mb-pinned colors') == 0 ]] || { echo "FAIL migrate_14: configs/colors"; exit 1; }
[[ $(count 'key="C-W-s"><action name="Execute" command="mb-pinned status"') == 1 && $(count 'key="C-W-p"') == 1 ]] || { echo "FAIL migrate_14: status/places"; exit 1; }
[[ $(count 'key="C-W-n"') == 1 && $(count 'command="mine"') == 1 && $(count 'key="W-A-n"') == 1 ]] || { echo "FAIL migrate_14: touched the user's C-W-n"; exit 1; }
valid || { echo "FAIL migrate_14: rc.xml is no longer valid"; exit 1; }

# migrate_14: with W-A-c rebound by the user, the pinned Colors key stays.
grep -v -e 'key="C-W-[cnsp]"' -e 'key="W-A-c"' "$root/configs/mabox-noctalia-ce/rc.xml" > "$conf/mabox-noctalia-ce/rc.xml"
sed -i 's#</keyboard>#<keybind key="W-A-c"><action name="Execute" command="mine"/></keybind>\n<keybind key="C-W-c"><action name="Execute" command="mb-pinned colors"/></keybind>\n</keyboard>#' "$conf/mabox-noctalia-ce/rc.xml"
migrate
[[ $(count 'mb-pinned colors') == 1 && $(count 'command="mine"') == 1 ]] || { echo "FAIL migrate_14: removed the Colors key without moving configs"; exit 1; }

# migrate_12 and 28: the Calamares launcher runs through sudo -E with an empty DISPLAY, and an existing user copy is left alone.
if [[ -f /usr/share/applications/calamares.desktop ]]; then
    desk=$tmp/.local/share/applications/calamares.desktop
    migrate
    grep -qx 'Exec=sudo -E env DISPLAY= /usr/bin/calamares' "$desk" || { echo "FAIL migrate_28: Exec not rewritten"; exit 1; }
    echo mine > "$desk"; migrate
    [[ $(<"$desk") == mine ]] || { echo "FAIL migrate_12: overwrote the user's launcher"; exit 1; }
fi

# migrate_15: the Todo key is added once, and an existing binding of W-y is left alone.
grep -v -e 'key="W-y"' "$root/configs/mabox-noctalia-ce/rc.xml" > "$conf/mabox-noctalia-ce/rc.xml"
migrate; migrate
[[ $(count 'key="W-y"') == 1 ]] || { echo "FAIL migrate_15: expected one W-y bind"; exit 1; }
valid || { echo "FAIL migrate_15: rc.xml is no longer valid"; exit 1; }

# migrate_18: the slideshow key is added once.
grep -v -e 'key="W-A-a"' "$root/configs/mabox-noctalia-ce/rc.xml" > "$conf/mabox-noctalia-ce/rc.xml"
migrate; migrate
[[ $(count 'key="W-A-a"') == 1 ]] || { echo "FAIL migrate_18: expected one W-A-a bind"; exit 1; }
valid || { echo "FAIL migrate_18: rc.xml is no longer valid"; exit 1; }

# migrate_19: the wallpaper right-click is added once; a user-edited block stays.
mkdir -p "$conf/noctalia"
printf '[widget.workspaces]\n\n[widget.wallpaper]\ncapsule = false\n' > "$conf/noctalia/config.toml"
migrate; migrate
[[ $(grep -c 'wallpaper-dirs:dirs' "$conf/noctalia/config.toml") == 1 ]] || { echo "FAIL migrate_19: expected one right-click action"; exit 1; }
printf '[widget.wallpaper]\ncapsule = false\n\n[widget.wallpaper.actions]\nright = "mine"\n' > "$conf/noctalia/config.toml"
migrate
[[ $(grep -c 'mine' "$conf/noctalia/config.toml") == 1 && $(grep -c 'wallpaper-dirs' "$conf/noctalia/config.toml") == 0 ]] || { echo "FAIL migrate_19: overwrote the user's action"; exit 1; }

# migrate_20: each logo template gets the refresh hook once.
printf '[theme.templates.user.mabox-logo]\ninput_path = "a"\noutput_path = "~/.local/share/mabox-noctalia-ce/mabox-logo.svg"\n\n[theme.templates.user.mabox-logo-ce]\ninput_path = "b"\noutput_path = "~/.local/share/mabox-noctalia-ce/mabox-logo-ce.svg"\n' > "$conf/noctalia/config.toml"
migrate; migrate
[[ $(grep -c 'post_hook = "mb-logo-refresh"' "$conf/noctalia/config.toml") == $(grep -c '^output_path = .*mabox-logo' "$conf/noctalia/config.toml") ]] || { echo "FAIL migrate_20: expected one hook per logo template"; exit 1; }

# migrate_21: the old q-term rule becomes the right terminal, the left rule and key are added once, an edited size stays.
printf '<openbox_config>\n<keyboard>\n</keyboard>\n<windowRules>\n    <windowRule title="q-term">\n      <action name="SetDecorations" decorations="none"/>\n      <action name="ResizeTo" width="2545" height="700"/>\n      <action name="MoveTo" x="10" y="45"/>\n    </windowRule>\n</windowRules>\n</openbox_config>\n' > "$conf/mabox-noctalia-ce/rc.xml"
migrate; migrate
[[ $(count 'title="q-term-right"') == 1 && $(count 'title="q-term-left"') == 1 && $(count 'key="C-grave"') == 1 && $(count 'width="1265"') == 2 ]] || { echo "FAIL migrate_21: expected both rules and the key once"; exit 1; }
valid || { echo "FAIL migrate_21: rc.xml is no longer valid"; exit 1; }
sed -i '0,/width="1265"/s/width="1265"/width="999"/' "$conf/mabox-noctalia-ce/rc.xml"
sed -i 's#title="q-term-right"#title="q-term"#' "$conf/mabox-noctalia-ce/rc.xml"
migrate
[[ $(count 'title="q-term-right"') == 1 && $(count 'width="999"') == 1 ]] || { echo "FAIL migrate_21: overwrote an edited rule"; exit 1; }

# migrate_25: the install key and the launcher right-click are added once; an edited action stays.
grep -v -e 'key="W-i"' "$root/configs/mabox-noctalia-ce/rc.xml" > "$conf/mabox-noctalia-ce/rc.xml"
printf '[widget.launcher]\nshow_tooltip = false\n' > "$conf/noctalia/config.toml"
migrate; migrate
[[ $(count 'key="W-i"') == 1 ]] || { echo "FAIL migrate_25: expected one W-i bind"; exit 1; }
[[ $(grep -c 'mabox/install:main' "$conf/noctalia/config.toml") == 1 ]] || { echo "FAIL migrate_25: expected one launcher action"; exit 1; }
printf '[widget.launcher]\n\n[widget.launcher.actions]\nright = "mine"\n' > "$conf/noctalia/config.toml"
migrate
[[ $(grep -c 'mine' "$conf/noctalia/config.toml") == 1 && $(grep -c 'install:main' "$conf/noctalia/config.toml") == 0 ]] || { echo "FAIL migrate_25: overwrote the user's action"; exit 1; }

# migrate_27: the on() helper and the wrapped default lines are added once; the menu entry opens the panel.
cat > "$conf/mabox-noctalia-ce/autostart" <<'EOT'
systemctl --user import-environment WAYLAND_DISPLAY
command -v skippy-wl >/dev/null && systemctl --user --no-block start skippy-wl.service
command -v kanshi >/dev/null && kanshi &
command -v mb-updates-ce >/dev/null && systemctl --user --no-block start mb-updates-ce.timer mb-updates-ce.path
command -v mb-status-warn >/dev/null && systemctl --user --no-block start mb-status-warn.timer
command -v mb-hide-cursor >/dev/null && mb-hide-cursor &
(sleep 3 && [ "$(cat /sys/class/leds/*numlock/brightness 2>/dev/null | head -1)" = "0" ] && wtype -k Num_Lock) &
EOT
printf '<item label="Edit autostart" icon="edit">\n<action name="Execute" command="xdg-open ~/.config/mabox-noctalia-ce/autostart" />\n</item>\n' > "$conf/mabox-noctalia-ce/menu.xml"
migrate; migrate
a=$conf/mabox-noctalia-ce/autostart
[[ $(grep -c '^on() {' "$a") == 1 && $(grep -c '^on [a-z-]* &&' "$a") == 6 ]] || { echo "FAIL migrate_27: expected the helper and six wrapped lines"; exit 1; }
bash -n "$a" || { echo "FAIL migrate_27: autostart no longer parses"; exit 1; }
[[ $(grep -c 'panel-toggle mabox/autostart:main' "$conf/mabox-noctalia-ce/menu.xml") == 1 ]] || { echo "FAIL migrate_27: menu entry"; exit 1; }

# migrate_28: the old DISPLAY=:0 launcher of migrate_12 is rewritten once, other launchers stay.
desk=$tmp/.local/share/applications/calamares.desktop
mkdir -p "${desk%/*}" "$tmp/state/mabox-noctalia-ce"
printf '[Desktop Entry]\nExec=env DISPLAY=:0 /usr/bin/calamares_polkit %%f\nName=Calamares\n' > "$desk"
echo 27 > "$tmp/state/mabox-noctalia-ce/config-version"
migrate; migrate
[[ $(grep -c '^Exec=sudo -E env DISPLAY= /usr/bin/calamares$' "$desk") == 1 && $(grep -c 'Name=Calamares' "$desk") == 1 ]] || { echo "FAIL migrate_28: old launcher not rewritten"; exit 1; }
printf 'Exec=mine\n' > "$desk"; echo 27 > "$tmp/state/mabox-noctalia-ce/config-version"; migrate
[[ $(<"$desk") == Exec=mine ]] || { echo "FAIL migrate_28: overwrote the user's launcher"; exit 1; }

# migrate_34: the session workspace binds are added once, four workspaces at least, a user-bound key stays.
grep -v 'key="W-A-C-F' "$root/configs/mabox-noctalia-ce/rc.xml" | sed 's#<desktops number="4" />#<desktops number="2" />#; s#</keyboard>#    <keybind key="W-A-C-F2"><action name="Execute" command="mine"/></keybind>\n  </keyboard>#' > "$conf/mabox-noctalia-ce/rc.xml"
echo 33 > "$tmp/state/mabox-noctalia-ce/config-version"
migrate; migrate
[[ $(count 'GoToDesktop') == 5 && $(count 'key="W-A-C-F2"') == 1 && $(count 'command="mine"') == 1 ]] || { echo "FAIL migrate_34: binds"; exit 1; }
[[ $(count '<desktops number="4" />') == 1 ]] || { echo "FAIL migrate_34: desktops"; exit 1; }
valid || { echo "FAIL migrate_34: rc.xml is no longer valid"; exit 1; }

# migrate_35: the Sessions panel key is added once, and an existing binding of the key is left alone.
grep -v 'key="A-F1"' "$root/configs/mabox-noctalia-ce/rc.xml" > "$conf/mabox-noctalia-ce/rc.xml"
echo 34 > "$tmp/state/mabox-noctalia-ce/config-version"
migrate; migrate
[[ $(count 'key="A-F1"') == 1 ]] || { echo "FAIL migrate_35: expected one A-F1 bind"; exit 1; }
valid || { echo "FAIL migrate_35: rc.xml is no longer valid"; exit 1; }

# migrate_36: the Sessions panel entry is off by default; a login switched on before stays on, once.
sk=$conf/mabox-noctalia-ce/autostart.skip
rm -f "$sk"; echo 35 > "$tmp/state/mabox-noctalia-ce/config-version"
migrate; migrate
[[ $(grep -cx session "$sk") == 1 ]] || { echo "FAIL migrate_36: session not off by default"; exit 1; }
printf 'kanshi\nsession\n' > "$sk"; mkdir -p "$tmp/state/mabox-noctalia-ce"; : > "$tmp/state/mabox-noctalia-ce/session-login"
echo 35 > "$tmp/state/mabox-noctalia-ce/config-version"
migrate
[[ $(<"$sk") == kanshi && ! -e "$tmp/state/mabox-noctalia-ce/session-login" ]] || { echo "FAIL migrate_36: login kept on"; exit 1; }

# migrate_37: the root menu gets the Bars entry once, after Autostart.
echo 36 > "$tmp/state/mabox-noctalia-ce/config-version"
migrate; migrate
[[ $(grep -c 'panel-toggle mabox/bars:main' "$conf/mabox-noctalia-ce/menu.xml") == 1 ]] || { echo "FAIL migrate_37: menu entry"; exit 1; }

# migrate_38: the Wallpaper entry leaves the root menu once; the other wallpaper entries stay.
m=$conf/mabox-noctalia-ce/menu.xml
printf '<item label="Wallpaper" icon="x">\n<action name="Execute" command="noctalia msg panel-toggle wallpaper" />\n</item>\n<item label="Wallpaper folders" icon="x">\n<action name="Execute" command="folders" />\n</item>\n' > "$m"
echo 37 > "$tmp/state/mabox-noctalia-ce/config-version"
migrate; migrate
[[ $(grep -c 'panel-toggle wallpaper"' "$m") == 0 && $(grep -c 'label="Wallpaper folders"' "$m") == 1 && $(grep -c '</item>' "$m") == 1 ]] || { echo "FAIL migrate_38: menu entry"; exit 1; }

# migrate_39: Bars moves in front of Config files, once.
printf '<item label="Config files" icon="x">\n<action name="Execute" command="cfg" />\n</item>\n<item label="Config files pinned" icon="x">\n<action name="Execute" command="mb-pinned configs" />\n</item>\n<item label="Autostart" icon="x">\n<action name="Execute" command="noctalia msg panel-toggle mabox/autostart:main" />\n</item>\n<item label="Bars" icon="x">\n<action name="Execute" command="noctalia msg panel-toggle mabox/bars:main" />\n</item>\n' > "$m"
echo 38 > "$tmp/state/mabox-noctalia-ce/config-version"
migrate; migrate
[[ $(grep -c 'mabox/bars:main' "$m") == 1 && $(grep -c '</item>' "$m") == 4 ]] || { echo "FAIL migrate_39: Bars count"; exit 1; }
[[ $(grep 'label="' "$m" | sed -n 1p) == *'"Bars"'* && $(grep 'label="' "$m" | sed -n 2p) == *'"Config files"'* ]] || { echo "FAIL migrate_39: Bars is not before Config files"; exit 1; }

# migrate_40: the Sessions key points at mabox/sessions, once.
echo 39 > "$tmp/state/mabox-noctalia-ce/config-version"
sed -i 's#mabox/sessions:main#mabox/places:sessions#' "$conf/mabox-noctalia-ce/rc.xml"
migrate; migrate
[[ $(grep -c 'mabox/sessions:main' "$conf/mabox-noctalia-ce/rc.xml") == 1 && $(grep -c 'places:sessions' "$conf/mabox-noctalia-ce/rc.xml") == 0 ]] || { echo "FAIL migrate_40: A-F1 command"; exit 1; }
valid || { echo "FAIL migrate_40: rc.xml is no longer valid"; exit 1; }

# migrate_42: Luciole's colour template becomes the builtin one and the old user block goes, whatever the shape of the list; once.
mkdir -p "$conf/noctalia"
echo 41 > "$tmp/state/mabox-noctalia-ce/config-version"
check42() { # name, expected count of "luciole", expected count of user.luciole
    [[ $(grep -c '"luciole"' "$conf/noctalia/config.toml") == "$2" && $(grep -c 'user.luciole' "$conf/noctalia/config.toml") == "$3" && $(grep -c 'user.cava' "$conf/noctalia/config.toml") == 1 ]] || { echo "FAIL migrate_42: $1"; exit 1; }
    python3 -c "import sys, tomllib; tomllib.load(open(sys.argv[1], 'rb'))" "$conf/noctalia/config.toml" || { echo "FAIL migrate_42: $1: config.toml is no longer valid"; exit 1; }
}
block='[theme.templates.user.luciole]\ninput_path = "/usr/share/luciole/templates/colors.toml"\noutput_path = "~/.config/luciole/colors.toml"\nenabled = true\n\n[theme.templates.user.cava]\ninput_path = "x"\n'
for list in '["btop", "qt"]' '[]' $'[\n  "btop",\n  "qt",\n]'; do
    printf '[theme.templates]\nbuiltin_ids = %s\n\n%b' "$list" "$block" > "$conf/noctalia/config.toml"
    migrate; migrate
    check42 "list $list" 1 0
done
printf '[theme.templates]\nenable_builtin_templates = true\n\n%b' "$block" > "$conf/noctalia/config.toml"
migrate
check42 "no builtin_ids key" 0 0

# migrate_43: the launcher floats, once; a placement the user set stays.
echo 42 > "$tmp/state/mabox-noctalia-ce/config-version"
chk43() { # name, expected "floating" count, expected "attached" count
    [[ $(grep -c 'launcher_placement = "floating"' "$conf/noctalia/config.toml") == "$2" && $(grep -c 'launcher_placement = "attached"' "$conf/noctalia/config.toml") == "$3" ]] || { echo "FAIL migrate_43: $1"; exit 1; }
    python3 -c "import sys, tomllib; tomllib.load(open(sys.argv[1], 'rb'))" "$conf/noctalia/config.toml" || { echo "FAIL migrate_43: $1: config.toml is no longer valid"; exit 1; }
}
printf '[shell.panel]\nfloating_layer = "top"\n' > "$conf/noctalia/config.toml"; migrate; migrate; chk43 "key added once" 1 0
printf '[shell.panel]\nlauncher_placement = "attached"\n' > "$conf/noctalia/config.toml"; migrate; chk43 "own choice kept" 0 1
printf '[theme]\nmode = "dark"\n' > "$conf/noctalia/config.toml"; migrate; migrate; chk43 "table added" 1 0
printf '[shell.panel] # panels\nfloating_layer = "top"\n' > "$conf/noctalia/config.toml"; migrate; chk43 "commented header" 1 0
printf '[shell.panel.sub]\nx = 1\n' > "$conf/noctalia/config.toml"; migrate; chk43 "sub-table only left alone" 0 0
printf 'broken = [\n' > "$conf/noctalia/config.toml"; migrate || { echo "FAIL migrate_43: stops on an invalid config.toml"; exit 1; }

# migrate_44: with gThumb installed the screenshot key and the root menu use it, once; without it nothing changes.
mkdir -p "$tmp/bin"
echo 43 > "$tmp/state/mabox-noctalia-ce/config-version"
sed "s#bash -c 'gthumb #bash -c 'viewnior #" "$root/configs/mabox-noctalia-ce/rc.xml" > "$conf/mabox-noctalia-ce/rc.xml"
python3 - "$root/configs/mabox-noctalia-ce/menu.xml" "$conf/mabox-noctalia-ce/menu.xml" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
open(sys.argv[2], "w").write(re.sub(r'  <item label="Thumbnails".*?</item>\n', '', s, flags=re.S))
PY
if ! command -v gthumb >/dev/null; then
    migrate
    [[ $(count "viewnior") == 1 && $(grep -c 'gthumb' "$conf/mabox-noctalia-ce/menu.xml") == 0 ]] || { echo "FAIL migrate_44: changed without gthumb"; exit 1; }
fi
printf '#!/bin/sh\n' > "$tmp/bin/gthumb"; chmod +x "$tmp/bin/gthumb"
PATH=$tmp/bin:$PATH migrate; PATH=$tmp/bin:$PATH migrate
[[ $(count "viewnior") == 0 && $(count "bash -c 'gthumb ") == 1 && $(grep -c 'command="gthumb"' "$conf/mabox-noctalia-ce/menu.xml") == 1 ]] || { echo "FAIL migrate_44: gthumb entries"; exit 1; }
valid || { echo "FAIL migrate_44: rc.xml is no longer valid"; exit 1; }
python3 -c "import sys, xml.dom.minidom as m; m.parse(sys.argv[1])" "$conf/mabox-noctalia-ce/menu.xml" || { echo "FAIL migrate_44: menu.xml is no longer valid"; exit 1; }

echo ok
