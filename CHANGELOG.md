# Changelog

## Unreleased
- Make the `W-KP_1..9` snap keys cycle on repeat: corners and sides go half, 1/3, 2/3 of the width; top and bottom go full width, 1/3 centred; the centre goes full, 1/3, 80%. Existing installs keep the old keys until you copy the binds from the default `rc.xml`.

## 0.8.0
- Add a source dropdown to the Music panel on the Add to playlist row: the player buttons go to the player you pick, Active player follows Noctalia again.
- Put the Music player buttons in a capsule and make Refresh an icon on the right.
- Remove the Keep open switch from the Music, Recolor, Equalizer, Autostart, Agents, Install and Todo panels.
- Add an icon to the autostart rows in the Configs panel that opens the Autostart panel.
- Add `mb-import-openbox`: make the Mabox todo list active in the Todo panel and turn Cherrytree todo notes into Notes (`--dry-run` shows what it would do).
- Add a pcmanfm action *Set as wallpaper* for a single image: sets it as the wallpaper and stops the slideshow (`mb-wallpaper-image`).
- Add `mb-files`: opens pcmanfm-qt when installed, else pcmanfm through XWayland (GTK3 menus ran off the screen bottom). Places, `W-f`, the root menu, Status and Recolor use it.
- Right click on a drive in the Places panel opens it in the file manager; `mb-files` brings the window to the front.
- Right click on a file in the Places panel opens its folder in the file manager (it no longer copies the path).
- Add `pcmanfm-qt` and `kimageformats` (AVIF thumbnails) to the install list and as optional dependencies.
- pcmanfm-qt opens folders as tabs in the running window (`mb-migrate` sets `SingleWindowMode`).
- Todo panel: click the open list again to put it on the desktop as a post-it, click once more to remove it.
- Post-its for a filter (Overdue, Today, Tomorrow, Next 7 days, Later, No date) show the tasks of all lists, with the list, group and context next to each task.
- Todo panel: every group and context in the Groups card has a remove button; a group with tasks asks first and is removed from the tasks of the open list.
- Notes: the On screen switch moves out of the editor and the list; it is in the pinned panel and in Select of the top panel. A small dot under each colour puts all notes of that colour on the desktop, a bar takes them off.
- Notes: Select in an open note goes back to the list in select mode.
- Places: right click on an open subfolder opens it in the file manager; its name no longer has the hover colour.
- Places: a QDirStat button in the button row opens the home folder in QDirStat; the collapse button has the Configs icon and stays white.

## 0.7.1
- Add an Agenda switch to the Configs panel (Post-its card) that shows the next events as a post-it.

## 0.7.0
- Add `mb-postits`: notes as small windows on the desktop (`W-A-y` shows or hides them). Type in a note directly; position, size and text size are saved.
- Add an On screen switch to the Notes editor; a note with it on gets a post-it.
- Add post-its for a todo list (`--tasks LIST`: tick a task to strike it through, untick to reopen) and the agenda (`--agenda`: next events from `~/caldir`).
- Add title buttons and a right-click menu to post-its: hide, close all, remove from screen, size and text size.
- Add an On screen switch to every row of the Notes list, also in the pinned window.
- Put a Todo filter on the desktop with a second click on it in the Todo panel and take it off with a third; each filter is its own post-it.
- Color the post-it title bar with the note's color.
- Set renCal as the default calendar app when you have no choice yet; a double click on a date in the Noctalia calendar opens it.
- Start new Todo tasks as Medium, due today; the panel fills the window and the list scrolls.
- List every folder the Places tree search finds under the field, with star, copy and a clear button.
- Add an empty button to the Trash row in Places, with the item count and a confirmation.
- Show the active project and its list when the Quick card in Places is folded.
- Add a Quick card to Places: star folders and files to keep them at the top, and save them as named projects; the active project takes the stars directly.
- Draw a frame around every open folder in Places and alternate the row background.
- Add a Balance slider to Recolor that favours darker or lighter palette colors.
- Fix the Recolor Soft look saving JPEG files in gray.
- Remove the F3 key that opened geany from the default keys.

## 0.6.2
- Add a Resume switch to Recolor that skips images already in the output folder, to continue a stopped run on a large folder.
- Delete a saved Recolor palette with a right-click and a confirmation.
- Fold the Recolor folder cards into one line.
- Make the Recolor My palettes fold hide the whole list; the header shows the palette in use.
- Add a Keep open switch to the Recolor, Autostart, Music, Agents, Equalizer, Install, Insert, System, Todo and Keys panels: the panel stays open when another panel opens.
- Add Recolor profiles (Poster, Dreamy, Neon night, Film, Clean) and your own, saved by name with palette, group, look, blur and the colors that are off.
- Fix the Music sleep timer: it now stops the music, offers 15 to 180 minutes and your own minutes, and can shut the computer down.
- Turn one Polaroid upside down in about one pile out of nine, not in every pile.
- Add a left/right swap button to the header of the pinned Colors window.
- List every palette with a strip of its colors in the Colors Wallpaper, Built-in and My palettes profiles.

## 0.6.1
- Show the path of the marked folder under the Places folder search, with a copy button.
- Cycle the Places drive button between folders only, folders and drives, and drives only.
- Click the now-playing title in the Music panel to jump to the list and the row of the playing track.
- Keep the selected list and the list with the playing track visible when a Music sidebar group is folded.
- Fix the Equalizer being very quiet when switched on: its sink volume no longer multiplies with the hardware volume.
- List an Equalizer preset once when the shipped and the user folder hold the same name.
- Fix the Music panel skipping tracks in Recent: a track that plays on by itself is added too, also while the panel is closed (an mpv script logs tracks that play for 4 seconds).
- Move the previous, play/pause, next and stop buttons of the Music panel to the header next to Refresh.
- Find a station played from Find stations with the now-playing title of the Music panel: the click shows its row in the results, or says it is not in your lists.
- Fix the Equalizer staying on a stream after it is switched off: `mb-eq off` moves streams left on the Equalizer back to the output.
- Add a folder set with the pcmanfm action *Set wallpaper dir* to the Wallpaper folders panel list.
- Fix the Recolor panel stopping during a run over a large folder: the progress count no longer goes over the panel time budget.
- Change, add, remove and switch off the colors of a palette in the Recolor panel and keep them with *Save as*; saved palettes are in a folded *My palettes* list.
- Add the palettes vibrant, cyberpunk, tokyo-night, rose-pine and monochrome to Recolor and Wallgen.

## 0.6.0
- Search the System panel Fixes tab and filter it with topic buttons (Packages, Sound, Network, Noctalia, System); a search matches the title, symptoms, description and keywords of a fix.
- Fix the Music panel showing the title of another mpv window (for example one opened with `C-S-1`) instead of its own track.
- Add an Autostart panel (root menu, `/autostart`): add, edit, delay, switch off and remove the entries of `autostart.local`, switch off the shipped defaults, and see what the session always starts.
- Add 18 more fixes to the System panel Fixes tab (microphone, Bluetooth audio, monitor layout, DNS, clock, printer, Flatpak, AUR builds, fonts, USB drives, old kernel, hotkeys, plugin reload, notifications).
- Add a Text size card to the Configs panel: `<` and `>` step the size of text and widgets of the whole shell from 80% to 150%.
- Start Calamares from the launcher with `sudo -E env DISPLAY= calamares`, so it opens in the Wayland session (migration rewrites the `DISPLAY=:0` launcher).
- Add a Text size setting (50% to 200%) to the Info, Sysinfo and Todo today desktop widgets; the global Text size no longer shrinks them.
- Add a Corner radius setting (0 to 32) to the Info, Sysinfo and Todo today widgets, and in Configs → Widgets an Edit layout button and a Corner radius section (all widgets together or one kind at a time).
- Add a folder search to the Places panel: type a name and it opens the section and folders above the match and jumps to it, Enter for the next match; a drive button includes the mounted drives, and mounted drives open their folders in place.
- Add a button to every pinned window that closes it and opens the same panel from the bar; the Notes panel has Reload, Pin and Close as icons at the top right.
- Add an Exclude list view to the Snapshot panel: add and remove patterns of `/etc/mabox-snapshot/excludes.list`, keep a path inside an excluded folder, and pick a folder with a chooser; changes ask for your password in the Noctalia prompt.
- Publish the manual (`docs/`) as a website with mdBook on GitHub Pages.

## 0.5.2
- Open Recolor and Wallgen from a wand button in the header of the Wallpaper folders panel.
- Put the recording button in the bar back to the camera after a recording (left: screenshot, right: Capture panel).
- Show the whole playlist name in the *Add to playlist* chooser of the Music panel.
- Open Wallgen from the root menu (Tools, next to Recolor), `/mb wallgen` in the launcher or `mb-wallgen --panel`.
- Generate in Wallgen as a background job with a *Stop* button and a notification; a stopped run leaves no half written image; one image per run.
- Show *Open folder* and *Use folder as wallpapers* in Wallgen all the time, and keep the chosen palette visible when *My palettes* is folded away.
- Open Wallgen in a compact layout with three tabs on a small screen (narrowest output under 1900 px wide); the *Wide* and *Compact* button in the header switches by hand.
- Make wallpapers in the Wallgen panel (second panel of Recolor, switch in the header) or with `mb-wallgen`: blend, bilinear, mesh, voronoi, plasma, contour, waves, twisted, linear, radial, dither or solid from a palette or your own colors; pattern, angle, balance and blur settings.
- Change, switch off and add colors of a palette copy in the Wallgen panel (pick from the screen or the color chooser) and keep it with *Save as* under *My palettes*; saved palettes also work in Recolor.
- Show the wallpaper folder in use at the top of the Wallpaper folders panel and frame only that one.

## 0.5.1
- Show the category or radio group of the playing track in the Music panel, colour the playing row, and show the title as Artist - Title like the bar.
- Search the Music panel with several words, also in the stream's own title and artist, so `dj 1985` finds a track; the card with the playing track comes first.
- Add an Equalizer icon to the Music panel title row; it is blue while the equalizer is on.
- Play one mpv at a time from the Music panel: a new track ends every mpv on its socket, so a track no longer plays twice.

## 0.5.0
- Fold and unfold the cards of the Places panel; the fold state is saved with the card order.
- Open terminator on `W-Return` (was foot) and open gmrun without a title bar.
- Add playlists to the Music panel: `.m3u` files in `~/.config/mabox/mb-music/playlists/`, Favourites is one of them; *Add to playlist* with `+` on a row, move, remove and delete, total time per playlist.
- Show *Recent* in the Music panel: the last 15 tracks that really played, with a clear button.
- Add a sleep timer, `-30s` / `+30s` jump buttons with a settable step, a play-on switch and track lengths (clock button) to the Music panel; a click plays the list on from that track and skips streams that fail.
- Check radio streams in the Music panel (stethoscope button): dead streams turn red, *Remove N dead* deletes them from `stations.csv` (a `.bak` stays), *Keep all* keeps them.
- Add PyRadio, Volume and Cava icons to the Music panel title row (Cava: right click opens its settings) and a *Refresh* button.
- Find new radio stations in the Music panel: *Find stations* searches radio-browser.info by name or genre, the play button tries a result and *Add* puts it in a PyRadio group or a new group (`~/.config/pyradio/stations.csv`).
- Add a Music panel (`W-m`, root menu): PyRadio stations and mb-music categories in a sidebar with search, shuffle and play per card, now playing with previous, pause, next and stop; Tools opens the visualiser, PyRadio, volume and the list files. `/music` stays in the launcher.
- Widen the Recolor panel to two columns with the looks in a 2x2 grid; add a Blur slider (`mb-recolor -b N`), a progress bar with the time left, saved settings, and a *Use as wallpapers* button that adds the output folder to the wallpaper folders and starts it.
- Install apps from the pacman repositories with the Install apps panel (`W-i`, root menu, right click on the launcher button, `/mb install`): categories, installed state, Install button runs `sudo pacman -S --needed` in a terminal and the panel reopens when it closes; the list is `/usr/share/mabox-noctalia-ce/install.csv`.
- Close the Status, System, Recolor and Capture panels when they open a terminal or a file manager (pinned windows stay open); Wallpaper folders hides while the folder chooser is open.
- Show the folder in use in the Wallpaper folders panel: an In use line, an outlined row, and the list scrolls to it when the panel opens.
- Right click on the volume bar button opens the Equalizer panel.
- List unmounted disks in the Drives card of the Places panel: every partition with a filesystem except the system mounts; click mounts and opens it, the eject button unmounts it.
- Create a folder from the Places panel: the new folder button next to the terminal button of an expanded folder opens a name field; Enter or the check button creates it.
- Notify when a disc reaches the alert level: buttons Open status and Snooze 24 h, one notification per change of the full-disc list; `mb-status-warn` checks every 5 minutes (`systemctl --user enable --now mb-status-warn.timer`).
- Turn the updates bar button into a disc warning when a disc is full: alert icon in the warning color, tooltip lists the disc and the updates; middle click checks for updates now, right click opens the Status panel.
- Show the numbers in the Status settings buttons: disc alert levels in two rows, package count in the label.
- Places: left click on a folder expands it in place (subfolders, files, no dotfiles), right click opens it in the file manager; expanded folders get an open-in-terminal button that follows the Agents terminal; add Close all and a clear button for the search box.
- Recolor Smooth mode softens the edges slightly.
- Equalizer presets keep the Pre level: a preset or Revert changes only the ten bands, and the preset in use is highlighted by its bands.
- Equalizer: the preamp drops by the largest boost, bands use Q 1.4, a 40 Hz high-pass starts the chain, presets also load from `~/.config/mabox-noctalia-ce/eq-presets/*.json` (Adam D3V ships as one), and the panel has two columns. Presets with a negative preamp play quieter by the headroom.
- Fix the Music add panel and `/music` stopping on a long list: the CSV is read and edited by python.
- Show, hide and reorder the cards of the Places panel with the edit button (panel and pinned window).
- Hide the pointer after some idle seconds: switch and seconds in the Configs panel (Power card, off by default); `mb-hide-cursor on [secs]` and `off`.
- Start and resume Claude Code, Codex and Agy sessions from `/ag` or the AI agents panel (`S-W-a`): session details, new sessions in favorite, GitHub or AUR folders, Add folder with a folder chooser; `mb-agent-sessions` does the work.
- Choose the terminal for agent sessions with the gear button in the AI agents panel (Auto, foot, kitty, alacritty, terminator, xfce4-terminal, xterm); `mb-agent-sessions --set terminal NAME`.
- Show the last answer of a Claude session in the detail card of the AI agents panel.

## 0.4.9
- Set the screens-off and lock times in the Configs panel (Power card); *Screens off by* Dim (brightness and contrast to 0 over DDC/CI), Black layer or Both; `mb-screen-off` and `mb-screen-on` do the work and fall back to DPMS without DDC/CI.
- Set background, wallpaper (file picker), blur, tint and transition of the lock screen in the Configs panel (Lockscreen card).
- Show the same Power and Lockscreen values in the dropdown and the pinned Configs window.
- Set the wallpaper transition in the Wallpaper folders panel (Transition card, collapsible): effects, duration, edge smoothness, animate on startup, same effect on all monitors.
- Hover a folder in the Wallpaper folders panel to see a random image from it; the full path shows below the list.
- Show `mb-pinned <plugin>` with a copy button in the Configs panel for plugins that have a pinned window.
- Lock the Recolor panel while a job runs: only *Stop* works until it finishes.
- Show Trash, a Drives card (USB and `/run/media` partitions; click mounts and opens, eject unmounts) and a separate Bookmarks card in the Places panel.
- Scroll the folder list in the Wallpaper folders panel: it has a fixed height and a scrollbar.
- Recolor (beta, still being tested and tuned): recolor images from the Recolor panel (root menu → Tools, `/mb recolor`): pick an image or folder, palette, colors, look (Soft, Hard, Smooth) and output folder; `mb-recolor -m smooth` gives flat areas with clean edges.
- Show three previews (Soft, Hard, Smooth) and the palette colors in the Recolor panel; *Another* previews a random image from a folder; avif images are accepted.
- Run Recolor in the background with a notification at the end; the button turns into *Stop* while it runs.
- Recolor images to a palette with `mb-recolor [-m clut|remap|smooth] [-g group] [-o outdir] <palette> <files or folder>`; palettes: nord, gruvbox, catppuccin-mocha, dracula, solarized (`mb-recolor --list`); output goes to `~/Pictures/<palette>/<group>/`.
- Open two quake terminals side by side: `F12` right, `C-grave` left (`q-term-toggle [right|left]`).
- Copy the unit status in the Services tab with the copy button; user timers get a Repair button (daemon-reload, reset-failed, enable --now, status).
- Fix the Polaroids toggle in the widgets panel: widgets with letters in their id are read correctly.
- Snap windows to a 3x3 area with `W-KP_1` … `W-KP_9` (press again to restore); `W-drag` snaps to the quarter under the pointer.
- Show the logo, title and hotkey in grey at the top of every panel; the hotkey is read from `rc.xml`, and pinned windows show their pinned hotkey.
- Add a *Random pictures* setting to the Polaroids widget: random pictures from the wallpaper folder instead of the previous wallpapers.
- Update the bar launcher logo when the theme colour or logo style changes (`mb-logo-refresh`).
- Show the logo and framed sections in the wallpaper folders panel; right-click on the wallpaper widget opens it.
- Set the slideshow interval in minutes, turn it on or off, and choose random or alphabetical order in the wallpaper folders panel.
- Add a wallpaper slideshow entry to the root menu.
- Turn the wallpaper slideshow on or off with `W-A-a` or `mb-slideshow [toggle|on|off]`, with a notification.
- Open rencal with a right-click on the clock; `rencal` and `jumpapp-ng` are optional dependencies.
- Open the Keys panel on All binds with the search focused instead of the focused application.
- Reopen the Snapshot panel on the ISO list after a successful build; the list shows every ISO, scrolls, and deletes an ISO with its checksum; a folder button opens the ISO folder.
- Switch the Mabox logo between round, square, 3d, ce (theme-coloured M-CE) and your own SVG from the Configs panel (Logo card); every panel header and the info and sysinfo widgets follow the choice.
- Show the whole Todo sidebar (Lists, Sort tasks, Groups) instead of cutting it off at a fixed height.
- Order the root menu's Tools submenu alphabetically by block, with separators between the blocks.
- Hide desktop widgets of disabled or removed plugins in `mb-widget` and the widgets panel.
- Add a *Todo today* desktop widget (mabox/todo): open tasks that are overdue or due today from every list; click the header to open the Todo panel; `max` setting for the number of rows.
- Show due dates in the Todo panel in the order of your locale (`dd-mm-yyyy`, `mm/dd/yyyy`); typed dates are accepted in that order or as `YYYY-MM-DD`; the file keeps `due:YYYY-MM-DD`.
- Show the date of an ISO in the Snapshot panel in your locale format.
- Add `mb-widget` to show or hide a desktop widget by name (`mb-widget toggle <name>`), a *Desktop widgets* entry in the root menu, `/mb` launcher entries and a widgets panel (`noctalia msg panel-toggle mabox/tools:widgets`) for a bar button.
- Show the chosen Mabox logo in the Cava, Equalizer, Reset, Snapshot, Tools and System panel headers.
- Remove the Quoter desktop widget (mabox/quoter).
- Add a button to the Todo panel that hides the add part; the task list then uses the freed space.
- Add View archive to the Todo panel's Done tasks card.
- Give Next 7 days and Later than 7 days their own colour in the Todo panel.
- Keep ticked tasks struck through in the Todo panel's Overdue, Today, Tomorrow, Next 7 days, Later, No date and Pinned views.
- Add a Todo panel (mabox/todo, `W-y`): todo.txt lists in `~/.todo` with due dates and a calendar picker, priorities, `+group` sub-groups, notes, search, sort and filter views (Overdue, Today, Tomorrow, Next 7 days, Later), struck-through done tasks with archive, list rename; mb-migrate adds the key to an existing rc.xml.
- Pre-fill the drop-in with a commented template when Edit opens a packaged unit in the Services tab; saving it unchanged keeps nothing.

## 0.4.8

- Add a Timers chip to the System panel's Services tab: user timers with Run now, Start, Stop, Enable, Disable and Edit.
- Add an offline address check to the Crypto panel: format and checksum for Litecoin, Bitcoin and Dogecoin addresses (legacy, SegWit, Taproot); `mb-crypto check <address>`.
- Show the file path of a service in the System panel's Services tab, with Open folder and Edit (your own file in an editor, otherwise a `systemctl edit` drop-in); system services ask for the unit name before Stop, Restart, Start and Reset failed.
- Add a Services tab to the System panel (`W-A-i`): system and user services with Failed/Running/All filters, scrubbed status, and Restart, Stop, Start and Reset failed in a terminal after a prompt; session-critical units show status only.
- Add a button to the Crypto panel that opens kraken.com/prices.
- Add a Crypto panel (mabox/crypto): convert an EUR or USD amount to LTC, BTC, ETH, XMR, DOGE or SOL at the latest Kraken price, refreshed every 15 s; dropdown and pinned window, root menu, `/mb crypto`, `mb-pinned crypto`.
- List the plugins in the Configs panel in alphabetical order.
- Remove the `skippy-wl-send-to-*` and `skippy-wl-tiling` scripts and their keybinds (`S-C-KP_7/8/9`, `C-Space`, `W-A-C-*`); the code is in the wiki.
- Add a Places panel (mabox/places): folders, file manager bookmarks, recent files (5/10/20/50) and FSearch, in the bar panel and a pinned window; `W-p`, root menu, `/mb places`, `mb-pinned places`; mb-migrate adds the key to an existing rc.xml.
- Pinned windows open with `C-W-<letter>`: Configs `C-W-c`, Notes `C-W-n`, Status `C-W-s`, Places `C-W-p`; Colors keeps `W-c`. mb-migrate moves the old defaults.
- Match the default Noctalia config to the live setup for new installs: m3-tonal-spot scheme, tray without capsule, equalizer button in the bar, notifications block.
- Check for updates every 6 hours instead of hourly.
- Start Calamares from the launcher with `DISPLAY=:0`; mb-migrate writes the user launcher.
- Make the remove confirmation in the Configs panel fall back to Remove after 7 seconds.
- Make the Updates panel taller and scroll when the content does not fit.
- Remove the copy icon from notes in the pinned Notes panel; right click on the title copies.
- Start a new note in the Title field; Enter jumps to the text.
- Rename the AUR cache rows in the Status panel to Clean with paru, yay and pamac.
- Add W-A-q to open the Equalizer panel; mb-migrate adds the key to an existing rc.xml.
- Add an Equalizer panel (mabox/equalizer): preamp and 10 bands on a PipeWire filter-chain sink, presets, on/off, and Save as startup values; `mb-eq` does the work and mb-migrate adds `eq.conf` to `~/.config/pipewire/pipewire.conf.d/`. It is in the root menu and `/mb equalizer`. Saving under an existing name replaces that preset; Revert goes back to the gains before the last preset.
- Turn on the Noctalia polkit agent by default so password windows (`pkexec`, pamac) appear.
- Show a dot instead of a chevron on the rows inside Configs panel sections: small when closed, filled when open.
- Add Reset and Undo to each bar button in the Configs panel: Reset fills the fields from `config.toml`, Undo swaps back, Save applies.
- Add `+ Add button` to Bar buttons in the Configs panel: create a button and put it at the end of the bar; click actions get `exec` added.
- Add Remove to each bar button in the Configs panel: takes the button out of the bar; adding the same name again restores its settings.
- Bold subjects, hover-coloured commands and a frame on the open row in the Configs panel plugin list.
- Draw a border around each section of the Configs panel.
- Change the screenrec bar button default: camera icon, right click opens the Capture panel, middle click does nothing; `screenrec-toggle` restores the icon after a recording.
- List a Toggle command for every panel of a plugin in the Configs panel, read from its `plugin.toml`.
- Add a Bar buttons section to the Configs panel: edit icon, tooltip and left, middle and right click of bar buttons, no file needed.
- Add a collapse-all button to the Configs panel.
- Add a Toggle command to each running plugin in the Configs panel.
- Fix the empty Widgets section in the Configs panel.
- Add a Mirrors card to the Updates panel: Fasttrack, Continent and Choose (pacman-mirrors), or Reflector on plain Arch; also `mb-updates-ce mirrors`.
- Group the Updates panel in cards and add a help view and a button for the System panel.

## 0.4.7

- Pick two palette colors (Pri + Ter, Pri + Sec, Sec + Ter) and a style (Vivid, Soft, Palette) for Follow wallpaper colors in the Cava panel; mb-migrate adds the secondary color to the palette template.
- Draw the Cava panel preview with the bar count and bar width of the real window.
- Add Save as text and Open text folder to the Colors panel, and a Settings tab for the text folder (default `~/.config/mabox-noctalia-ce/color-palettes`).
- Remove Edit palettes and Save as palette from the Colors panel.
- Fix the pinned Colors window not scrolling a long palette.
- Add W-c for the Colors panel and C-W-c for the pinned Colors window; mb-migrate adds them to an existing rc.xml.
- Open a plugin in the Configs panel for a Reload button and copyable start, stop and reload commands.
- Add a Widgets section to the Configs panel for desktop widgets; stopped and failed plugins show "(stopped)".
- Widen the Configs panel to 540 px.

## 0.4.6

- Add a button to open the save folder in the System panel Report tab and Settings.
- Add a save location to the System panel Settings.
- Remove the Upload button and the upload address from the System panel.
- Add a Public/Private switch to the System panel and a list of words to hide in its Settings; Private keeps everything.
- Cut the Logs tab to 120 lines per section so it scrolls.
- Let the System panel Report tab pick its parts: Overview, Hardware, each log and topics (audio, graphics, network, Bluetooth, disks, boot, packages, power, desktop). Add previous boot, kernel, failed services and crashes to its Logs tab.
- Add a Fixes tab to the System panel: 15 common fixes, each with a read-only check and a run-in-terminal button.
- Add a Reverse frequencies switch to the Cava panel.
- Change W-A-c from the color picker to the pinned Configs window.
- Ship the Noctalia CE wallpaper in the package as the default wallpaper on a first login.
- Add mb-iso-next and a VM button in the Snapshot panel: after a build, write the ISO to USB or start it in a VM with quickbox-qt 1.4 or newer.
- Fix install.sh installing an old build: it now builds the working tree in a temp folder.
- Add tests/iso-check.sh --host to check the installed system against the repo before building a snapshot.
- Add W-A-v to open the Cava settings panel.
- Enable new Mabox plugins once on login with mb-plugins-enable, so a fresh user and a snapshot ISO get the panels; mb-migrate adds it to an existing autostart. An existing install keeps its choices.
- Add tests/iso-check.sh to compare a built ISO or its rootfs.sfs with the repo.
- Show a still spectrum in the Cava panel header with the bar width, spacing and colors of the cava settings (solid, gradient or followed wallpaper colors); the panel is wider with two columns.
- Add a Screen button to the Cava panel colors to pick a color from the screen with mb-colorpick; select a gradient color before Pick or Screen.
- Add a Layer switch (normal, always on top, always below) to the Cava panel; the window rules are added to rc.xml by mb-migrate.
- Add Follow wallpaper colors to the Cava panel: 2 bar colors from the Noctalia palette (mb-cava-theme), updated when the wallpaper changes.
- Add Cava (mb-cava toggle: start or stop) and Cava settings to the Tools menu and the /mb launcher.
- Add a Cava panel (mabox/cava): start and stop the transparent cava, change bar color or a gradient of 2 to 8 colors, bar width and spacing, framerate and noise reduction.
- Add Ctrl+Alt+V to show or hide a transparent cava (mb-cava): foot without frame, 60% of the screen width, bottom centre.
- Install fittsmon, fittsmon-wl-gui, skippy-wl, tabdock, mabox-snapshot and mabox-persistence-usb from the maboxlinux repo with pacman; the GitHub builds are disabled.
- Add a Snapshot plugin (mabox/snapshot) to build an ISO with mabox-snapshot: profiles, a kernel row with an All switch, an encrypt switch for the personal snapshot, Explain shows the plan, Build opens a terminal, and the newest ISOs can be written to a USB stick with mabox-persistence-usb.
- Remove Preferred applications from the root menu.
- Open a note straight in the editor with autosave; Esc saves and returns to the list.
- Pick a note color in the editor: alt+Up to the color row, alt+Left/Right, alt+Enter; alt+1..9 and alt+0 as shortcuts.
- Make W-n start a new note in the editor.
- Add an Open: editor/list switch to the Notes side bar.
- Open a note from the pinned Notes window in the editor; show one compact line per note.
- Open the Keys panel on the application it was called from, and scroll the side list to it.
- Add hotkey lists for PyRadio, Audacious, Tabdock, qutebrowser, Meld, Forum Scout and Clementine.
- Remove the Focused entry from the Keys side list.
- Remove the unused jgmenu update menu.
- Restore the separators in the root menu.
- Add Look and Feel (nwg-look) to the settings menu.
- Move Add/Remove software to the settings menu.
- Add Edit autostart to the settings menu.
- Add Ctrl+Keypad0 to launch scrcpy.
- Add Ctrl+Alt+Left and Ctrl+Alt+Right to send a window to the previous or next workspace.
- List Ctrl+Keypad0, Ctrl+Alt+Left and Ctrl+Alt+Right in the Keys panel.

## 0.4.5

- Use the Noctalia CE wallpaper as the default on a first login.
- Add a keys entry to the root menu.
- Add clicks for the screen recorder: area shot, stop, record.
- Add the wallpaper-dirs plugin.
- Add the Info, Quoter and Polaroids desktop widgets.
- Put the pinned windows in the top layer so the bar keeps its place.
- Keep the bar center lane empty in the default config.

## 0.4.4

- Add a themed Mabox logo template and an `~/.icons` link.
- Take the default look and bar settings from the live setup.
- Add a Noctalia item to `mb-reset-wl` for the bar and theme.
- Point the install notes to `mb-reset-wl`.

## 0.4.3

- Migrate copied configs on login.

## 0.4.2

- Move the update actions from the jgmenu popup to a Status plugin panel; list the pending packages and print a header per step in the update terminal.
- Drop upgraded AUR packages from the offline update count; the count clears when nothing is pending.
- Add the sysinfo desktop widget in place of the conky sysinfo.
- Add a monitor picker, C-S-a area shot and hover thumbnails to the capture panel.
- Add a copy button on each key row in the Keys panel.
- Disable every Mabox plugin on uninstall.

## 0.4.1

- Give the Keys panel a fixed width and put the pinned windows on the overlay layer.
- Leave the screen corners free next to the pinned windows (4 px).

## 0.4.0

- Add the Insert plugin: `/hist` and `/es` in the launcher, and a snippets panel with list, search and delete.
- Add keyboard navigation (alt+arrows, alt+enter) to the Keys, Snippets, Configs, Status, Capture and Reset panels, and to the pinned windows.
- Add profile chips, application hotkey profiles and an application list to the Keys panel; add lists for foot, feh, Double Commander and yazi, and read your own yazi and Double Commander shortcuts.
- Show the pinned windows of Status, Notes, Colors, Configs and Capture as layers with a dock button.
- Reload all plugins from the Configs panel; failed ones turn red.
- Show the fittsmon zone commands per monitor with W-A-k.
- Add W-A-r to open the Capture panel and a bind for Obsidian.

## 0.3.0

- Add the Configs plugin and pin windows to the left or right.
- Add the Reset plugin and menu entry.
- Add config file entries to the root menu and the Mabox Config menu.
- Add the Tools launcher provider.
- Add the Capture plugin: area, window and monitor screenshots with delay and format, interval shots, gifmaker, screen recording.
- Add reload buttons to the Configs panel, per enabled plugin.
- Add an add-track panel to the Music plugin.
- Add W-b to toggle the window decorations.
- Add the Keys panel (W-k) with the labwc binds, and `/keys` in the launcher.

## 0.2.0

- Remove conky from the session: autostart, `W-c`, menu entries, window rule, theme template and the `conky` dependency.
- Clean the old entries from `~/.config/mabox-noctalia-ce/{autostart,rc.xml,menu.xml}` and `~/.config/noctalia/config.toml` after updating.

## 0.1.1

- Name the optional Wayland GUI `fittsmon-wl-gui`, not `fittsmon-gui`.
- Keep `colormenu` optional.

## 0.1.0

- First tagged release: labwc and Noctalia session with default configs for Mabox, and the Notes, Colors, Music and Status plugins.
