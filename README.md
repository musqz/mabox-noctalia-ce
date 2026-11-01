# mabox-noctalia-ce

musqz's community edition of Mabox Noctalia: a [Noctalia](https://github.com/noctalia-dev/noctalia-shell) session on labwc, selectable as **Noctalia CE** at the login screen. It differs from the original mabox-noctalia in config, scripts and package choices.

**Work in progress.** This repo is for inspiration and development: take what you like, or install it as is.

- **Separate:** own session entry and own config in `~/.config/mabox-noctalia-ce/`. Other sessions are not touched.
- **Install:** `./install.sh` installs the needed packages and builds the `mabox-noctalia-ce` package. Packages you already have are skipped. The package is rebuilt when `bin/` differs from `/usr/bin`. The script ends with a `[done]`/`[skip]`/`[todo]` summary.
- **Autostart:** put your own startup programs in `~/.config/mabox-noctalia-ce/autostart.local`. `autostart` stays the shared default.
- **Remove:** `./install.sh --uninstall` removes the package and the packages the script installed. Then `rm -rf ~/.config/mabox-noctalia-ce`.

Requires Mabox Linux with `noctalia` 5.4 or newer (repo `[maboxlinux]`).


<table>
  <tr>
    <td><img alt="skippy-wl search" src="docs/skippy-wl-search.png" /></td>
    <td><img alt="Root menu with icons" src="docs/root-menu.gif" /></td>
    <td><img alt="skippy-wl expose" src="docs/skippy-wl.png" /></td>
    <td><img alt="skippy-wl multiselect" src="docs/skippy-wl-multiselect.png" /></td>
  </tr>
  <tr>
    <td align="center">skippy-wl: <code>/</code> search</td>
    <td align="center">Root menu with icons</td>
    <td align="center">skippy-wl: expose view of all windows</td>
    <td align="center">skippy-wl: multiselect</td>
  </tr>
</table>

<table>
  <tr>
    <td><img alt="Blue theme with matching conky" src="docs/theme-blue-2.png" /></td>
    <td><img alt="Red theme with matching conky" src="docs/theme-red-2.png" /></td>
  </tr>
</table>

<table>
  <tr>
    <td><img alt="/music launcher with keybind cheat sheet and conky" src="docs/music-launcher.png" /></td>
  </tr>
  <tr>
    <td align="center">/music launcher</td>
  </tr>
</table>

<table>
  <tr>
    <td><img alt="Update menu on the bar button" src="docs/updates-menu.png" /></td>
  </tr>
  <tr>
    <td align="center">Update menu</td>
  </tr>
</table>

<table>
  <tr>
    <td valign="top"><img alt="Colors panel on the bar button with the color selector open" src="docs/colors-dropdown.png" width="520" /></td>
    <td valign="top"><img alt="Pinned Colors window with the built-in flat_character palette" src="docs/colors-pinned.png" width="240" /></td>
  </tr>
  <tr>
    <td align="center">Colors panel (W-A-c)</td>
    <td align="center">Pinned window</td>
  </tr>
</table>

## Guide

Elements, keys and tips: [docs/guide.md](docs/guide.md).

## Custom tools

| Tool | Key | Setup |
|---|---|---|
| `/music` launcher player | `W-S-m` | [docs/music.md](docs/music.md) |
| `mb-music-add-url` add track | `C-S-2` | [docs/music.md](docs/music.md) |
| `mb-updates-ce` bar update indicator | left: update menu, right: recheck | autostart |
| `mb-calendar-setup` local calendar (radicale) | run once in a terminal | Thunderbird + Noctalia Settings > Calendar > Local (vdir) |
| `mb-colorpick` + Colors bar panel | bar button: pick from screen, recent colors, palettes | `~/.config/colormenu/*.clr` |
| `mpv-play-stream` play URL | `C-S-1` | [docs/music.md](docs/music.md) |
| Media keys | `XF86Audio*` | [docs/music.md](docs/music.md) |
