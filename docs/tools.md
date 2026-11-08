# Tools

Panels, widgets and scripts that Noctalia CE adds. Keys: [keys.md](keys.md).

## Panels

| Tool | Key | Setup |
|---|---|---|
| `mb-colorpick` + Colors bar panel | bar button: pick from screen, recent colors, palettes | `~/.config/colormenu/*.clr` |
| System panel:<br>_overview, hardware, logs, and a report without personal data to copy or save for the forum_ | `W-A-i` | [guide.md](guide.md#system-info) |
| Keys panel:<br>_hotkey list with search, Basics and All; opens on the application you called it from, with hotkey lists for installed applications; `/keys` in the launcher runs a bind_ | `W-k` | [keys.md](keys.md) |
| Insert:<br>_`/hist` types a shell history line, `/es` an Espanso snippet into the previous window; panel to add and edit snippets_ | `W-A-h`, `W-A-e` | [keys.md](keys.md) |
| Wallpaper folders:<br>_saved list, click to switch the wallpaper directory; `/wp` in the launcher, root menu_ | `W-A-w` | [guide.md](guide.md#wallpaper-directory) |
| Notes panel:<br>_notes with colors_ | `W-n`, pinned window `W-A-n` | `~/.local/state/noctalia/plugins/data/mabox/notes/path`: one line, folder to sync (optional) |
| Status panel:<br>_system info, discs, cleanup rows; bar button turns warning-colored when a disc is full (`mb-status-warn`, left click opens it, right click pins it)_ | `W-A-s`, pinned window `W-S-s` | settings (gear button) in `~/.local/state/noctalia/plugins/data/mabox/status/settings` |
| Snapshot panel:<br>_profiles to build an ISO with `mabox-snapshot` (Explain in the panel, Build in a terminal with sudo; then USB or VM)_ | root menu → Mabox noctalia ce → Snapshot, `/mb snapshot` | [snapshot.md](snapshot.md): `mabox-snapshot`, `mabox-persistence-usb`, `quickbox-qt` |
| Cava panel:<br>_start and stop the transparent cava, bar color, gradient or wallpaper colors, bar width and spacing, framerate, noise reduction_ | root menu → Tools noctalia ce → Cava (start or stop) and Cava settings, `/mb cava` and `/mb cava settings` | `cavactl` (mabox-colorizer) |

## Desktop widgets

| Tool | Key | Setup |
|---|---|---|
| Sysinfo desktop widget:<br>_date, system info, CPU/RAM graphs, top processes, discs, updates_ | `noctalia msg desktop-widgets-toggle-edit`, then add *Sysinfo* | needs `[desktop_widgets] enabled = true` |
| Info desktop widget:<br>_logo, About line, basic hotkeys_ | `noctalia msg desktop-widgets-toggle-edit`, then add *Info* | same setting as Sysinfo |
| Quoter desktop widget:<br>_random quote, new one every 10 minutes_ | `noctalia msg desktop-widgets-toggle-edit`, then add *Quoter* | other quotes file: path on one line in `~/.config/quoter/quoter.conf` |
| Polaroids desktop widget:<br>_the previous wallpapers as polaroid thumbnails_ | `noctalia msg desktop-widgets-toggle-edit`, then add *Polaroids* | number of polaroids in the widget settings; needs `magick` |

## Music and media

| Tool | Key | Setup |
|---|---|---|
| `/music` launcher player | `W-m` | [music.md](music.md) |
| Music:<br>_add track_ | `C-S-2` | [music.md](music.md) |
| `mpv-play-stream` play URL | `C-S-1` | [music.md](music.md) |
| Media keys | `XF86Audio*` | [music.md](music.md) |

## Scripts

| Tool | Key | Setup |
|---|---|---|
| `mb-updates-ce` bar update indicator | left: update panel (Status plugin), right: recheck | autostart |
| `mb-calendar-setup` local calendar (radicale) | run once in a terminal | Thunderbird + Noctalia Settings > Calendar > Local (vdir) |
