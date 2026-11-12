# Keys

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
| `C-W-c` | pinned configs window |
| `W-c` | colors panel |
| `W-n` | notes |
| `C-W-n` | pinned notes window |
| `W-y` | todo |
| `W-p` | places |
| `C-W-p` | pinned places window |
| `W-A-s` | status |
| `C-W-s` | pinned status window |
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
