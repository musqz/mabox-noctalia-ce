# Guide

What the Noctalia CE session adds on top of Mabox, and how to use it.

## Where things live

| Path | Content |
|---|---|
| `~/.config/mabox-noctalia-ce/` | labwc config: `rc.xml`, `menu.xml`, `autostart`, `environment`, conky, menuscripts, plugins |
| `~/.config/noctalia/` | noctalia config, theme templates, palettes |
| `~/.local/state/noctalia/settings.toml` | settings saved by the noctalia GUI and `config-set`; overrides `config.toml` |
| `~/.config/mabox-noctalia-ce/jgmenurc` | generated; do not edit |

The repo copy under `configs/` is only the default. Edit the live files under `~/.config/`, or copy the repo version over by hand.

## Keys

The desktop cheat sheet (conky, left side) lists every bind from the live `rc.xml`. Edit `rc.xml`, press `C-S-r`, and the sheet follows.

| Key | Action |
|---|---|
| `W-space` | launcher |
| `W-s` | control center |
| `W-,` | noctalia settings |
| `W-x` | session menu |
| `W-l` | lock screen |
| `W-=` | wallpaper panel |
| `C-A-a` | random wallpaper |
| `W-c` | conky on/off |
| `W-S-c` | caffeine (no idle) |
| `W-t` | terminal |
| `F12` | quake terminal |
| `W-h` | btop |
| `W-S-r` | record region / stop |
| `C-S-a` | screenshot |
| `C-Insert` | open last screenshot |
| `W-A-c` | color picker |
| `A-Space` | root menu |
| `C-S-r` | reload labwc |

Windows:

| Key | Action |
|---|---|
| `W-Tab` | skippy-wl window switcher |
| `W-q` | close |
| `W-A-1` … `W-A-6` | snap to an edge or corner |
| `W-A-7` | maximize |
| `C-Space` | pick up to 4 windows and tile them |
| `W-A-C-7`, `W-A-C-9` | send window to HDMI-A-1, DP-1 |
| `W-1`, `W-2` | previous, next workspace |
| `W-S-1`, `W-S-2` | send window to previous, next workspace |
| `W-grave` | tabdock find |

## Bar

The bar is noctalia's. Extra buttons:

| Button | Left click | Right click |
|---|---|---|
| Updates | menu: update all, repo + AUR, repo only, flatpak, snap, npm, pipx, remove orphans (when any), check now | check now |
| Screen recording | start / stop | |

Click the updates button again to close the menu. The snap entry is hidden while `snapd` is stopped.

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
| conky colors | `conky/colors.lua`, conky restarts |
| update menu | `jgmenurc` |
| Geany | `colorschemes/noctalia.conf` |
| PyRadio | `themes/mbcolors.pyradio-theme` |
| Firefox (Pywalfox) | `~/.cache/wal/colors.json` |

Add a target: put a template under `~/.config/noctalia/` and a `[theme.templates.user.<name>]` block with `input_path` and `output_path` in `config.toml`. Apply now: `noctalia msg templates-apply`.

## Root menu

`A-Space`. Entries: favorites, Mabox Config (settings, control center, wallpaper, conky manager, edit and reload labwc), applications, running windows, screenshot, screen recording, converter.

Converter: pick a preset, then files; output lands next to the source and never overwrites. Video to MP4 / WebM / MKV / GIF, audio extraction, image formats. Command line: `mb-convert <preset> [file...]`.

## Wallpaper directory

Right-click a folder in pcmanfm → *Set wallpaper dir*. Command line: `mb-wallpaper-dir <dir>`.

## Conky

- Widgets: clock, sysinfo, cpu, ram, network, mount points, shortcuts, todo, polaroid and more.
- Pick which run: root menu → Mabox Config → Conky manager.
- All on/off: root menu → Mabox Config → Conky on/off.
- Restart the set: `~/.config/mabox-noctalia-ce/menuscripts/conky-start`.
- Colors follow the theme.

## Monitors

- `kanshi` sets positions per profile: `~/.config/kanshi/config`.
- `W-A-C-7` / `W-A-C-9` move a window to a monitor.
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
