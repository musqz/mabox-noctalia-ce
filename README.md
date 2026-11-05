# mabox-noctalia-ce

Noctalia session on labwc for Mabox Linux. Pick **Noctalia CE** at the login screen. It differs from the original mabox-noctalia in config, scripts and packages.

**Screenshots:** [Themes](#themes) · [Windows and menus](#windows-and-menus) · [Launcher and bar panels](#launcher-and-bar-panels) · [Notes and colors](#notes-and-colors)

Work in progress. Take what you like, or install it as is.

## Install

Needs Mabox Linux and `noctalia` 5.4 or newer (repo `[maboxlinux]`).

```sh
git clone https://github.com/musqz/mabox-noctalia-ce
cd mabox-noctalia-ce
./install.sh
```

- Installs the missing packages and builds `mabox-noctalia-ce`.
- Skips packages you already have; rebuilds `mabox-noctalia-ce` on every run.
- Ends with a `[done]` / `[skip]` / `[todo]` summary.
- Config lives in `~/.config/mabox-noctalia-ce/`. Other sessions are not touched.
- Several monitors: panels can open on the wrong screen until `noctalia` ships the fix ([PR 5173](https://github.com/noctalia-dev/noctalia/pull/5173)). One screen is not affected.

## Update

```sh
cd mabox-noctalia-ce
git pull
./install.sh
```

- Run each `meld` line listed under `[todo]` and merge what you want.
- Apply the merged config: `labwc --reconfigure`.
- Log out and back in after changes to `environment` or the plugins.

## Autostart

Add your own programs, one per line:

```sh
echo 'myapp &' >> ~/.config/mabox-noctalia-ce/autostart.local
```

`autostart` stays the shared default.

## Remove

```sh
./install.sh --uninstall
rm -rf ~/.config/mabox-noctalia-ce
```

`--uninstall` removes the package and the packages the script installed.

## Screenshots

### Themes

<table>
  <tr>
    <td valign="top"><a href="docs/theme-blue-2.png"><img alt="Blue theme" src="docs/theme-blue-2.png" width="430" /></a></td>
    <td valign="top"><a href="docs/theme-red-2.png"><img alt="Red theme" src="docs/theme-red-2.png" width="430" /></a></td>
  </tr>
  <tr>
    <td align="center">Blue theme</td>
    <td align="center">Red theme</td>
  </tr>
</table>

### Windows and menus

<table>
  <tr>
    <td valign="top"><a href="docs/skippy-wl-search.png"><img alt="skippy-wl search" src="docs/skippy-wl-search.png" width="430" /></a></td>
    <td valign="top"><a href="docs/skippy-wl.png"><img alt="skippy-wl expose" src="docs/skippy-wl.png" width="430" /></a></td>
  </tr>
  <tr>
    <td align="center">skippy-wl: <code>/</code> search</td>
    <td align="center">skippy-wl: expose view of all windows</td>
  </tr>
</table>

<table>
  <tr>
    <td valign="top"><a href="docs/skippy-wl-multiselect.png"><img alt="skippy-wl multiselect" src="docs/skippy-wl-multiselect.png" width="430" /></a></td>
  </tr>
  <tr>
    <td align="center">skippy-wl: multiselect</td>
  </tr>
</table>

### Launcher and bar panels

<table>
  <tr>
    <td valign="top"><a href="docs/music-launcher.png"><img alt="/music launcher with keybind cheat sheet" src="docs/music-launcher.png" width="560" /></a></td>
    <td valign="top"><a href="docs/updates-menu.png"><img alt="Update menu on the bar button" src="docs/updates-menu.png" /></a></td>
  </tr>
  <tr>
    <td align="center">/music launcher</td>
    <td align="center">Update menu</td>
  </tr>
</table>

### Notes and colors

<table>
  <tr>
    <td valign="top"><a href="docs/notes.png"><img alt="Notes dropdown with color filter next to the pinned notes window" src="docs/notes.png" width="640" /></a></td>
  </tr>
  <tr>
    <td align="center">Notes (W-n) and pinned window (W-A-n)</td>
  </tr>
</table>

<table>
  <tr>
    <td valign="top"><a href="docs/colors-dropdown.png"><img alt="Colors panel on the bar button with the color selector open" src="docs/colors-dropdown.png" width="520" /></a></td>
    <td valign="top"><a href="docs/colors-pinned.png"><img alt="Pinned Colors window with the built-in flat_character palette" src="docs/colors-pinned.png" width="240" /></a></td>
  </tr>
  <tr>
    <td align="center">Colors panel (W-A-c)</td>
    <td align="center">Pinned window</td>
  </tr>
</table>

## Guide

Elements, keys and tips: [docs/guide.md](docs/guide.md).

Files, paths and tools: [docs/overview.md](docs/overview.md).

## Custom tools

| Tool | Key | Setup |
|---|---|---|
| `/music` launcher player | `W-m` | [docs/music.md](docs/music.md) |
| Music: add track | `C-S-2` | [docs/music.md](docs/music.md) |
| `mb-updates-ce` bar update indicator | left: update panel (Status plugin), right: recheck | autostart |
| `mb-calendar-setup` local calendar (radicale) | run once in a terminal | Thunderbird + Noctalia Settings > Calendar > Local (vdir) |
| `mb-colorpick` + Colors bar panel | bar button: pick from screen, recent colors, palettes | `~/.config/colormenu/*.clr` |
| System panel: overview, hardware, logs, and a report without personal data to copy or save for the forum | `W-A-i` | [docs/guide.md](docs/guide.md#system-info) |
| Keys panel: hotkey list with search, Basics and All; opens on the application you called it from, with hotkey lists for installed applications; `/keys` in the launcher runs a bind | `W-k` | [docs/guide.md](docs/guide.md#keys) |
| Insert: `/hist` types a shell history line, `/es` an Espanso snippet into the previous window; panel to add and edit snippets | `W-A-h`, `W-A-e` | [docs/guide.md](docs/guide.md#keys) |
| Wallpaper folders: saved list, click to switch the wallpaper directory; `/wp` in the launcher, root menu | `W-A-w` | [docs/guide.md](docs/guide.md#wallpaper-directory) |
| Notes panel: notes with colors | `W-n`, pinned window `W-A-n` | `~/.local/state/noctalia/plugins/data/mabox/notes/path`: one line, folder to sync (optional) |
| Status panel: system info, discs, cleanup rows; bar button turns warning-colored when a disc is full (`mb-status-warn`, left click opens it, right click pins it) | `W-A-s`, pinned window `W-S-s` | settings (gear button) in `~/.local/state/noctalia/plugins/data/mabox/status/settings` |
| Sysinfo desktop widget: date, system info, CPU/RAM graphs, top processes, discs, updates | `noctalia msg desktop-widgets-toggle-edit`, then add *Sysinfo* | needs `[desktop_widgets] enabled = true` |
| Info desktop widget: logo, About line, basic hotkeys | `noctalia msg desktop-widgets-toggle-edit`, then add *Info* | same setting as Sysinfo |
| Quoter desktop widget: random quote, new one every 10 minutes | `noctalia msg desktop-widgets-toggle-edit`, then add *Quoter* | other quotes file: path on one line in `~/.config/quoter/quoter.conf` |
| Polaroids desktop widget: the previous wallpapers as polaroid thumbnails | `noctalia msg desktop-widgets-toggle-edit`, then add *Polaroids* | number of polaroids in the widget settings; needs `magick` |
| `mpv-play-stream` play URL | `C-S-1` | [docs/music.md](docs/music.md) |
| Media keys | `XF86Audio*` | [docs/music.md](docs/music.md) |
