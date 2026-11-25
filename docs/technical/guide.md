# Technical notes

Commands, paths and config files behind the sections of the Manual. See also [overview.md](overview.md).

## Where things live

| Path | Content |
|---|---|
| `~/.config/mabox-noctalia-ce/` | labwc config: `rc.xml`, `menu.xml`, `autostart`, `environment`, plugins |
| `~/.config/noctalia/` | noctalia config, theme templates, palettes |
| `~/.local/state/noctalia/settings.toml` | settings saved by the noctalia GUI and `config-set`; overrides `config.toml` |

The repo copy under `configs/` is only the default. Edit the live files under `~/.config/`, or copy the repo version over by hand.

## Configs panel: custom list

The list is the file `~/.config/mabox-noctalia-ce/config-paths.local`, one entry per line: `Custom|name|-|path|comment`. The comment is optional.

In the dropdown the card has the fields *Name*, *Path* (`~` allowed) and *Comment*.

## Updates

- Counts repo, AUR, flatpak, snap, npm and pipx updates. npm and pipx count only when you have user-level global packages.
- Tooltip shows the split: `5 updates (2 repo, 1 AUR, 2 flatpak)`.
- Check runs 30 s after login, then every 6 hours, and after every change to `pacman.log` (offline, no refresh).
- `yay` is used when installed, else `pacman`.
- Snap is skipped in the check and hidden in the menu while `snapd` is stopped.
- Command line: `mb-updates-ce [check|offline|upgrade [all|aur|repo|flatpak|snap|npm|pipx]|orphans|mirrors [fasttrack|continent|all|reflector]|menu]`.

For Thunderbird as the calendar app: `xdg-mime default org.mozilla.Thunderbird.desktop text/calendar`.

## Theme targets

| Target | Output |
|---|---|
| labwc window borders and titlebars | `~/.local/share/themes/noctalia/openbox-3/themerc` |
| Geany | `colorschemes/noctalia.conf` |
| PyRadio | `themes/mbcolors.pyradio-theme` |
| Firefox (Pywalfox) | `~/.cache/wal/colors.json` |

Add a target: put a template under `~/.config/noctalia/` and a `[theme.templates.user.<name>]` block with `input_path` and `output_path` in `config.toml`. Apply now: `noctalia msg templates-apply`.

## Screenshots and recording

- `mb-shots-interval [-o OUTPUT|auto | -a] [seconds]` starts: `-o` one monitor (`auto` = `SCREENSHOT_OUTPUT`, the only monitor, or a click on one of several), `-a` select an area once. Run it again to stop. Files go to `~/Pictures/shot_interval`.
- `mb-shots-interval -b` moves the images to `backup/DATE`; `-x` deletes them; `-n` counts them.
- `mb-gifmaker [-s PIXELS]` turns the images into a GIF in `~/Pictures/Mabox-Animations`. Settings: `~/.config/mabox/mb-gifmaker.conf`.
- Interval settings: `~/.config/mabox/mb-interval-shots.conf` (`interval=`, `screenshot_dir=`).
- `W-S-x` stops a running recording and interval screenshots.
- `mb-screenshot --delay N <screenshot-* args>` waits N seconds first; `--format png|jpg|webp|avif` sets the file type.
- `mb-screenshot screenshot-window` shows the skippy-wl picker: click or `Space` toggles windows, `Enter` confirms. Each picked window is saved as its own file, even when hidden or on another monitor. Without skippy-wl it takes the focused window.
- `screenrec-toggle -o auto` records a whole monitor instead of an area; with several monitors you click the one to record.
- Pause and stop from a key: `screenrec-toggle --pause` and `screenrec-toggle --stop`.
- Capture pinned window: `mb-pinned capture`; the side is set like for the other plugins.
- Pinned windows: the layout-sidebar button docks one (other windows make room); press it again to float. Saved per plugin in `~/.config/mabox-noctalia-ce/pinned-dock`.

## Wallpaper

`mb-wallpaper-dir <dir>` sets the wallpaper folder. `mb-wallpaper-image <file>` sets one image and stops the slideshow.

## Power

- The settings are written to the Noctalia idle behaviors `screen_off` and `lock`. Change them here, not in the Noctalia settings.
- Pick *Dim* or *Black layer* when the screens wake up by themselves after switching off, or a monitor keeps showing a power-save icon (seen with a Dell on DisplayPort).
- Input runs `mb-screen-on`: brightness, contrast and the black layer are restored.
- *Dim* uses DDC/CI (`ddcutil`); without it the screens are switched off normally (DPMS).

## Monitors

- `kanshi` sets positions per profile: `~/.config/kanshi/config`.
- Screenshots of a whole screen use the focused monitor. Set `SCREENSHOT_OUTPUT` (for example `HDMI-A-1`) in `~/.config/mabox-noctalia-ce/environment` to always take the same one; re-login to apply.
- Brightness keys control one output; set `BRIGHTNESS_OUTPUT` (default `HDMI-A-1`).

## Import from Mabox Openbox

The Mabox todo lists and the CE Todo panel use the same files in `~/.todo`: a task added in one shows in the other. There is nothing to sync.

`mb-import-openbox` copies the rest of the Mabox todo setup. Run it once, with `--dry-run` first to see what it would do:

```sh
mb-import-openbox --dry-run
mb-import-openbox
```

Pick one by name: `mb-import-openbox todo` or `mb-import-openbox notes`.

| Section | What it does |
|---|---|
| `todo` | Makes the list that is active in the Mabox todo menu the active list in the Todo panel. The lists themselves are shared: both use `~/.todo`. |
| `notes` | Makes a Notes entry of every Cherrytree node in `~/.todo/<list>.ctb`, tagged with the list. A node is imported once. Only the text comes along: images and tables are left out, and the script says which nodes it skipped. |

Reload the Todo plugin after `todo`: `noctalia msg plugins disable mabox/todo; noctalia msg plugins enable mabox/todo`.

## Tips

- Edited `config.toml` and nothing changed: the state file overrides it. Use `config-get` and `config-set`.
- Reload noctalia config: `noctalia msg config-reload`.
- Restart noctalia: `pkill noctalia; setsid noctalia >/dev/null 2>&1 &`.
- Reload labwc: `C-S-r`.
- Scripts in `bin/` run from `/usr/bin` after a package install. While testing, copy: `sudo install -Dm755 bin/<script> /usr/bin/<script>`.
- Bar widget shows `--`: enable `[system.monitor]`.
- `snap` hangs: start `snapd`, or ignore it; the update check skips it.
- Add, delay, switch off and remove startup programs in the Autostart panel (root menu or `/autostart`). Changes apply at next login. The panel edits `~/.config/mabox-noctalia-ce/autostart.local`; the same file opens in Geany.
- Autostart: `~/.config/mabox-noctalia-ce/autostart`. Personal programs, one per line as `(sleep 5 && tabdock) &` (tabdock, Vorta, PIA VPN, `fittsmon-wl --monitor`) go in `~/.config/mabox-noctalia-ce/autostart.local`; copy the template from `/etc/skel/.config/mabox-noctalia-ce/`.
- Session PATH does not include `~/bin`. Use `~/.local/bin` or an absolute path in binds.
