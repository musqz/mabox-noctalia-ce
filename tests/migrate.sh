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

# migrate_12: the Calamares launcher gets DISPLAY=:0, and an existing user copy is left alone.
if [[ -f /usr/share/applications/calamares.desktop ]]; then
    desk=$tmp/.local/share/applications/calamares.desktop
    migrate
    grep -q '^Exec=env DISPLAY=:0 /usr/bin/calamares_polkit' "$desk" || { echo "FAIL migrate_12: Exec not rewritten"; exit 1; }
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

echo ok
