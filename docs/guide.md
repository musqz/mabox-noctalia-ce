# Guide

What the Noctalia CE session adds on top of Mabox, and how to use it.

## Where things live

| Path | Content |
|---|---|
| `~/.config/mabox-noctalia-ce/` | labwc config: `rc.xml`, `menu.xml`, `autostart`, `environment`, plugins |
| `~/.config/noctalia/` | noctalia config, theme templates, palettes |
| `~/.local/state/noctalia/settings.toml` | settings saved by the noctalia GUI and `config-set`; overrides `config.toml` |
| `~/.config/mabox-noctalia-ce/jgmenurc` | generated; do not edit |

The repo copy under `configs/` is only the default. Edit the live files under `~/.config/`, or copy the repo version over by hand.

## System info

`W-A-i` opens the System panel: *Overview*, *Hardware*, *Logs* and *Report*.

*Report* collects the other tabs in one text without user name, host name, IP and MAC addresses, ids, serials and Wi-Fi names. Read it, then *Copy* or *Save* (to `~/Documents`).

*Upload* appears when *Settings* holds an `http(s)` address of a pastebin that takes a raw POST body and answers with the link. It asks before it sends.

## Keys

Binds live in `rc.xml`. Edit it, then reload with `C-S-r`.

`W-k` opens the hotkey list: search, Basics or All, play button runs a bind's command. `/keys` in the launcher searches the binds and runs the one you pick.

The list on the left filters the binds: *Panels*, *Mabox tools*, *Windows*, *Apps*, then the hotkeys of each installed application (Firefox, Geany, GIMP, Inkscape, ...). The panel opens on the application you called it from, when that application has a list.

Edit `lists/keys-profiles.csv` (`name,kind,source[,app ids]`) to add or reorder entries. An app entry shows only when its command is installed. App lists are `lists/appkeys/NAME.csv` (`section,keys,description`); Geany, Kitty, Yazi and Double Commander also read their own config.

`W-A-h` opens `/hist` and `W-A-e` opens `/es` in the launcher. Enter types the shell history line or the Espanso replacement text into the previous window (no Enter key). Snippets with variables (`{{...}}`) are listed only.

The first `/es` row, *Manage snippets*, opens a panel to add, edit and delete snippets. They are saved in `~/.config/espanso/match/mabox.yml` (backup: `mabox.yml.bak`); other Espanso files are not touched.

| Key | Action |
|---|---|
| `W-k` | hotkey list |
| `W-A-k` | show the fittsmon zone commands on each monitor (press again to hide) |
| `W-space` | launcher |
| `W-s` | control center |
| `W-,` | noctalia settings |
| `W-x` | session menu |
| `W-l` | lock screen |
| `W-=` | wallpaper panel |
| `C-A-a` | random wallpaper |
| `W-S-c` | caffeine (no idle) |
| `W-A-d` | show or hide desktop widgets |
| `W-t` | terminal |
| `F12` | quake terminal |
| `W-h` | btop |
| `W-S-r` | record region / stop |
| `C-S-a` | screenshot |
| `C-Insert` | open last screenshot |
| `W-A-c` | color picker |
| `W-n` | notes |
| `W-A-n` | pinned notes window |
| `W-A-s` | status |
| `W-S-s` | pinned status window |
| `A-Space` | root menu |
| `C-S-r` | reload labwc |

Windows:

| Key | Action |
|---|---|
| `W-Tab` | skippy-wl window switcher |
| `W-q` | close |
| `W-b` | hide or show the window title bar and border (press again to cycle) |
| `W-A-1` … `W-A-6` | snap to an edge or corner |
| `W-A-7` | maximize |
| `C-Space` | pick up to 4 windows and tile them |
| `W-A-C-7`, `W-A-C-9` | send window to HDMI-A-1, DP-1 |
| `W-1`, `W-2` | previous, next workspace |
| `W-S-1`, `W-S-2` | send window to previous, next workspace |
| `W-grave` | tabdock find |
| `W-A-r` | capture |

Panel keys (Keys, Snippets, Configs, Colors, Status, Capture, Reset, Notes; not in the pinned windows). Click the panel once first.

| Key | Action |
|---|---|
| `A-Up`, `A-Down`, `A-Left`, `A-Right` | move the cursor |
| `A-S-Up`, `A-S-Down` | move 5 rows (not in Notes) |
| `A-Enter` | activate |
| `A-s` | clear the cursor, back to the search field |
| `A-q` | close the panel |

## Bar

The bar is noctalia's. Extra buttons:

| Button | Left click | Right click |
|---|---|---|
| Updates | panel: update all, repo + AUR, repo only, flatpak, snap, npm, pipx, remove orphans (when any), check now | check now |
| Screen recording | start / stop | |

Click the updates button again to close the panel. Flatpak, Snap, npm and pipx entries show only when they have updates.

The RAM button is a noctalia `sysmon` widget: it shows memory use and has no click action.

### Updates

- Counts repo, AUR, flatpak, snap, npm and pipx updates. npm and pipx count only when you have user-level global packages.
- Tooltip shows the split: `5 updates (2 repo, 1 AUR, 2 flatpak)`.
- Check runs 30 s after login, then hourly, and after every change to `pacman.log` (offline, no refresh).
- `yay` is used when installed, else `pacman`.
- Snap is skipped in the check and hidden in the menu while `snapd` is stopped.
- Command line: `mb-updates-ce [check|offline|upgrade [all|aur|repo|flatpak|snap|npm|pipx]|orphans|menu]`.

### Change the bar

1. Check the live list: `noctalia msg config-get bar.default.end`.
2. Set it: `noctalia msg config-set bar.default.end "['group:g1','sysmon-ram','updates', ...]"`.
3. Keep `group:g1`: it holds the audio visualizer and media widgets.

Add a monitor widget: define `[widget.<name>]` with `type = "sysmon"` and `stat` (`cpu`, `cpu-temp`, `ram`, `swap`, `download`, `upload`, `gpu-usage`, `gpu-temp`, `disk-used-pct`), then add `<name>` to the bar list. `[system.monitor] enabled = true` must be set.

## Theme

One palette drives everything. Change it in noctalia settings or with the wallpaper panel; templates re-render and `labwc -r` reloads.

| Target | Output |
|---|---|
| labwc window borders and titlebars | `~/.local/share/themes/noctalia/openbox-3/themerc` |
| update menu | `jgmenurc` |
| Geany | `colorschemes/noctalia.conf` |
| PyRadio | `themes/mbcolors.pyradio-theme` |
| Firefox (Pywalfox) | `~/.cache/wal/colors.json` |

Add a target: put a template under `~/.config/noctalia/` and a `[theme.templates.user.<name>]` block with `input_path` and `output_path` in `config.toml`. Apply now: `noctalia msg templates-apply`.

## Root menu

`A-Space`. Entries: favorites, Mabox Config (settings, control center, wallpaper, edit and reload labwc), applications, running windows, screenshot, screen recording, converter.

Converter: pick a preset, then files; output lands next to the source and never overwrites. Video to MP4 / WebM / MKV / GIF, audio extraction, image formats. Command line: `mb-convert <preset> [file...]`.

## Interval screenshots and GIF

- `mb-shots-interval [-o OUTPUT|auto | -a] [seconds]` starts: `-o` one monitor (`auto` = `SCREENSHOT_OUTPUT` or the first), `-a` select an area once. Run it again to stop. Files go to `~/Pictures/shot_interval`.
- `mb-shots-interval -b` moves the images to `backup/DATE`; `-x` deletes them; `-n` counts them.
- `mb-gifmaker [-s PIXELS]` turns the images into a GIF in `~/Pictures/Mabox-Animations`. Settings: `~/.config/mabox/mb-gifmaker.conf`.
- Interval settings: `~/.config/mabox/mb-interval-shots.conf` (`interval=`, `screenshot_dir=`).
- `W-S-x` stops a running recording and interval screenshots.
- `mb-screenshot --delay N <screenshot-* args>` waits N seconds first; `--format png|jpg|webp|avif` sets the file type.
- `mb-screenshot screenshot-window` shows the skippy-wl picker: click or `Space` toggles windows, `Enter` confirms. Each picked window is saved as its own file, even when hidden or on another monitor. Without skippy-wl it takes the focused window.
- `screenrec-toggle -o auto` records a whole monitor instead of an area.
- While recording, a red stop button appears next to the `screenrec` bar button; click it to stop.
- Capture pinned window: `mb-pinned capture`; the side is set like for the other plugins.
- Pinned windows: the layout-sidebar button docks one (other windows make room); press it again to float. Saved per plugin in `~/.config/mabox-noctalia-ce/pinned-dock`.

## Wallpaper directory

Right-click a folder in pcmanfm → *Set wallpaper dir*. Command line: `mb-wallpaper-dir <dir>`.

Saved folders: `W-A-w`, the bar photo button, the *Wallpaper folders* entry in the root menu Mabox Config or `/wp` in the launcher (`/wp list`, `/wp add`). *Add folder* opens a chooser; select a circle to switch. The current folder is listed automatically.

## Monitors

- `kanshi` sets positions per profile: `~/.config/kanshi/config`.
- `W-A-C-7` / `W-A-C-9` move a window to a monitor.
- Screenshots of a whole screen use the focused monitor. Set `SCREENSHOT_OUTPUT` (for example `HDMI-A-1`) in `~/.config/mabox-noctalia-ce/environment` to always take the same one; re-login to apply.
- Brightness keys control one output; set `BRIGHTNESS_OUTPUT` (default `HDMI-A-1`).
- `skippy-wl-send-to-*` send the picked window to a named monitor.

## Music

See [music.md](music.md).

## Tips

- Edited `config.toml` and nothing changed: the state file overrides it. Use `config-get` and `config-set`.
- Reload noctalia config: `noctalia msg config-reload`.
- Restart noctalia: `pkill noctalia; setsid noctalia >/dev/null 2>&1 &`.
- Reload labwc: `C-S-r`.
- Scripts in `bin/` run from `/usr/bin` after a package install. While testing, copy: `sudo install -Dm755 bin/<script> /usr/bin/<script>`.
- Bar widget shows `--`: enable `[system.monitor]`.
- `snap` hangs: start `snapd`, or ignore it; the update check skips it.
- Autostart: `~/.config/mabox-noctalia-ce/autostart`. Personal programs (tabdock, Vorta, PIA VPN, `fittsmon-wl --monitor`) go in `~/.config/mabox-noctalia-ce/autostart.local`; copy the template from `/etc/skel/.config/mabox-noctalia-ce/`.
- Session PATH does not include `~/bin`. Use `~/.local/bin` or an absolute path in binds.
