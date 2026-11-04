# Overview: files, paths and tools

Where everything lives: in the repo, after install, and in your home folder.

| Jump to | |
|---|---|
| [Repo tree](#repo-tree) | what is in this repo |
| [Install map](#install-map) | repo path → installed path |
| [Live paths](#live-paths) | config, state, data, logs in `$HOME` |
| [Tools in `bin/`](#tools-in-bin) | every helper, what calls it |
| [Plugins](#plugins) | the three Noctalia plugins and their data |
| [Services](#services) | systemd user units |
| [Packages](#packages) | where the package lists live |
| [Handy commands](#handy-commands) | paste-ready checks |

## Repo tree

```text
mabox-noctalia-ce/
├── install.sh                  installs packages, builds and installs the package, enables plugins
├── README.md
├── bin/                        helper scripts → /usr/bin
├── lib/mabox-noctalia-ce       session launcher → /usr/bin/mabox-noctalia-ce
├── configs/
│   ├── noctalia-ce.desktop     login-screen entry → /usr/share/wayland-sessions/
│   ├── mabox-noctalia-ce/      labwc config set → /etc/skel/.config/
│   │   ├── rc.xml              keybinds and window rules
│   │   ├── menu.xml            root menu
│   │   ├── autostart           shared startup; add your own programs to autostart.local
│   │   ├── autostart.local     your startup programs (template)
│   │   ├── environment         session environment variables
│   │   ├── shutdown            runs when labwc exits
│   │   ├── themerc, themerc-override, noctalia.conf   window theme
│   │   ├── rc.xml.all          reference: every labwc option
│   │   └── plugins/            Noctalia plugins: colors, music, notes, status (installed to `/usr/share/mabox-noctalia-ce/plugins`)
│   ├── noctalia/               Noctalia config and templates → /usr/share/mabox-noctalia-ce/noctalia/
│   │   ├── config.toml         bar, widgets, hooks
│   │   ├── templates/          jgmenu.conf, labwc.conf
│   │   ├── Geany/, PyRadio/, Pywalfox/   theme templates
│   │   └── palettes/           color palette JSON
│   └── file-manager/actions/   file manager action → /usr/share/file-manager/actions/
├── systemd/user/               mb-updates-ce .service .timer .path → /usr/lib/systemd/user/
├── lists/                      pacman.txt, aur.txt, github.txt (what install.sh installs)
├── packaging/                  PKGBUILD, .SRCINFO, .install
└── docs/                       guide.md, music.md, overview.md, screenshots
```

## Install map

| Repo | Installed to | By |
|---|---|---|
| `bin/*` | `/usr/bin/` | package |
| `lib/mabox-noctalia-ce` | `/usr/bin/mabox-noctalia-ce` | package |
| `configs/noctalia-ce.desktop` | `/usr/share/wayland-sessions/noctalia-ce.desktop` | package |
| `configs/mabox-noctalia-ce/` (without `plugins/`) | `/etc/skel/.config/mabox-noctalia-ce/` | package |
| `configs/noctalia/` | `/usr/share/mabox-noctalia-ce/noctalia/` | package |
| `configs/file-manager/actions/*` | `/usr/share/file-manager/actions/` | package |
| `systemd/user/*` | `/usr/lib/systemd/user/` | package |
| `configs/mabox-noctalia-ce/plugins/` | `/usr/share/mabox-noctalia-ce/plugins/` | package |
| `configs/mabox-noctalia-ce/autostart.local` | `~/.config/mabox-noctalia-ce/autostart.local` (only if missing) | `install.sh` |

First session start (`mabox-noctalia-ce`) copies the skel config to `~/.config/mabox-noctalia-ce/` and the Noctalia files to `~/.config/noctalia/`. Existing files are never overwritten (`cp -n`).

## Live paths

| Path | What | Written by |
|---|---|---|
| `~/.config/mabox-noctalia-ce/` | labwc config (`rc.xml`, `menu.xml`, `autostart`, themes) | you; seeded from skel |
| `~/.config/mabox-noctalia-ce/autostart.local` | your own startup programs | you |
| `~/.config/noctalia/config.toml` | Noctalia bar and widgets | you; seeded from package |
| `~/.config/noctalia/{Geany,PyRadio,Pywalfox,templates,palettes}/` | theme templates | seeded from package |
| `~/.local/state/noctalia/settings.toml`, `state.toml` | Noctalia state; wins over `config.toml` | Noctalia, `noctalia msg config-set` |
| `~/.local/state/noctalia/plugins/data/mabox/<plugin>/` | plugin data (notes, color settings) | the plugins |
| `~/.local/share/mabox-noctalia-ce/installed` | packages the script installed | `install.sh` |
| `~/.config/mabox-noctalia-ce.bak-*`, `.save-*` | config backups | `install.sh --reset-config`, `--save-config` |
| `~/.cache/noctalia/noctalia.log` | Noctalia log | Noctalia |
| `~/.config/colormenu/` | recent colors and palettes | Colors plugin |
| `~/.config/mabox/mb-music/yt_music_list.csv` | music playlist | Music plugin |
| `~/.config/kanshi/config` | monitor layout | you |

Notes data: `~/.local/state/noctalia/plugins/data/mabox/notes/notes/*.md`. To sync it, write another folder path into `…/mabox/notes/path`.

## Tools in `bin/`

| Tool | Does | Called by |
|---|---|---|
| `mb-updates-ce` | counts pacman, AUR, flatpak, snap, npm, pipx updates for the bar button | autostart, systemd units, `config.toml` |
| `mb-colorpick` | click a pixel, print `#RRGGBB` | Colors plugin |
| `mb-calendar-setup` | local calendar: radicale user service + vdir path | run by hand |
| `mb-convert` | convert media with ffmpeg / magick | root menu |
| `mb-sysreport` | system info with user, host, addresses, ids and serials removed; `overview`, `hardware`, `logs`, `report [--save]` | System plugin |
| `mpv-play-stream` | play a copied URL in mpv | `C-S-1` |
| `mb-wallpaper-dir` | set the Noctalia wallpaper folder | file manager action "Set wallpaper dir" |
| `brightness-primary` | brightness up/down on the main monitor (`BRIGHTNESS_OUTPUT`) | brightness keys |
| `q-term-toggle` | show/hide the quake terminal | keybind in `rc.xml` |
| `screenrec-toggle` | start/stop recording with `wl-screenrec`; options `-o` output, `-f` fps, `-c` mp4/mkv, `-a` none/system/mic | bar button, root menu, `rc.xml` |
| `mb-shots-interval` | start/stop screenshots of one monitor or an area every N seconds | run by hand |
| `mb-screenshot-menu` | root-menu list of screenshot delays (3, 5, 10, 30 s) | root menu, Screenshot |
| `capture-stop` | stop a running recording and interval screenshots | `W-S-x`, stop button in the bar while recording |
| `mb-gifmaker` | make a GIF from the interval screenshots (`gifski`) | run by hand |
| `skippy-wl-tiling` | pick up to 4 windows and tile them | `C-Space` |
| `skippy-wl-send-to-{philips,dell,desk}` | pick windows, send to a monitor or workspace | `S-C-KP_7`, `S-C-KP_9`, `S-C-KP_8` |

## Plugins

Source: `configs/mabox-noctalia-ce/plugins/`. The package installs them; `autostart` and `install.sh` add the path source `mabox`. Enable each one by hand: `noctalia msg plugins enable mabox/notes`.

| Plugin | Entries | Open | Data / needs |
|---|---|---|---|
| `mabox/notes` | `main` dropdown, pinned window | `W-n`, `W-A-n` | notes in the plugin data folder |
| `mabox/status` | `main` dropdown, pinned window | `W-A-s`, `W-S-s` | none; cleanup rows run in a terminal |
| `mabox/configs` | `main` dropdown, pinned window | none (Mabox Config menu) | Custom section adds files (saved in `~/.config/mabox-noctalia-ce/config-paths.local`) |
| `mabox/reset` | `main` dropdown | none (Mabox Config menu) | `mb-reset-wl` |
| `mabox/capture` | `main` dropdown, pinned window | `noctalia msg panel-toggle mabox/capture:main` | `mb-screenshot`, `screenrec-toggle`, `mb-shots-interval`, `mb-gifmaker`, `gifski`, `wl-screenrec` |
| `mabox/colors` | `picker` dropdown, pinned window | `W-A-c` | `~/.config/colormenu/`, `mb-colorpick`, `grim`, `slurp`, `wtype` |
| `mabox/tools` | `/mb` launcher, also in global search | type `mb` or a tool name | opens the other Mabox plugins; pinned entries need `mb-pinned` |
| `mabox/keys` | `keys` hands over to `keys-wide` (full width), `/keys` launcher | `W-k` (`noctalia msg panel-toggle mabox/keys:keys`) | `mb-keys`, `keys.csv`, `keys-profiles.csv`, `appkeys/` in `/usr/share/mabox-noctalia-ce/`; `wlrctl` for the Focused entry |
| `mabox/system` | `system` dropdown: Overview, Hardware, Logs, Report, Settings | `W-A-i` | `mb-sysreport`; `inxi`, `fastfetch`, `btop` optional; upload address in `…/data/mabox/system/settings` |
| `mabox/insert` | `/hist` and `/es` launcher providers | `W-A-h`, `W-A-e` | `~/.bash_history`, `espanso match list`, `wtype` |
| `mabox/music` | `/music` launcher | `W-m` | playlist CSV, `mpv`, `socat`, `yt-dlp`, `mpv-mpris` |

```sh
noctalia msg plugins list
noctalia msg panel-toggle mabox/notes:main
mb-pinned notes
mb-pinned --side notes right
```

Pinned windows are the layers `pinned-left` and `pinned-right`, shown and hidden by the `pin` service of each plugin. `mb-pinned <plugin>` opens the one on the saved side. Each plugin has its own side, one `plugin=side` line in `~/.config/mabox-noctalia-ce/pinned-side`. Change it with the arrows button in a pinned window or in the Configs panel under Pinned windows.

## Services

| Unit (`systemd/user/`) | Does |
|---|---|
| `mb-updates-ce.timer` | runs the update check 30 s after start, then hourly |
| `mb-updates-ce.service` | the update check (with network) |
| `mb-updates-ce-offline.service` | the same without network |
| `mb-updates-ce.path` | triggers the offline check when `pacman.log` changes |

## Packages

| List | Contents |
|---|---|
| `lists/pacman.txt` | repo packages (`labwc`, `noctalia`, `kanshi`, …) |
| `lists/aur.txt` | AUR packages (`jumpapp-ng`, `wl-screenrec`, `labwc-menu-generator-git`) |
| `lists/github.txt` | built from source with `makepkg`: `fittsmon`, `fittsmon-wl-gui`, `skippy-wl`, `tabdock` |
| `packaging/PKGBUILD` | `depends` and `optdepends` of `mabox-noctalia-ce` itself |

## Handy commands

```sh
# reload labwc after editing rc.xml
labwc --reconfigure

# Noctalia log
tail -f ~/.cache/noctalia/noctalia.log

# back up, reset, restore the config
./install.sh --save-config
./install.sh --reset-config
./install.sh --recover-profile

# copy edited live config back into the repo (review the diff before committing)
./install.sh --sync-configs
git diff
```
