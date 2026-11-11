# Changelog

## Unreleased

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
