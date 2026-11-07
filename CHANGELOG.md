# Changelog

## Unreleased

- Show a still spectrum in the Cava panel header with the bar width, spacing and colors of the cava settings (solid, gradient or followed wallpaper colors).
- Add a Layer switch (normal, always on top, always below) to the Cava panel; the window rules are added to rc.xml by mb-migrate.
- Add Follow wallpaper colors to the Cava panel: 2 bar colors from the Noctalia palette (mb-cava-theme), updated when the wallpaper changes.
- Add Cava (mb-cava toggle: start or stop) and Cava settings to the Tools menu and the /mb launcher.
- Add a Cava panel (mabox/cava): start and stop the transparent cava, change bar color or a gradient of 2 to 8 colors, bar width and spacing, framerate and noise reduction.
- Add Ctrl+Alt+V to show or hide a transparent cava (mb-cava): foot without frame, 60% of the screen width, bottom centre.
- Install fittsmon, fittsmon-wl-gui, skippy-wl, tabdock, mabox-snapshot and mabox-persistence-usb from the maboxlinux repo with pacman; the GitHub builds are disabled.
- Make All in the Snapshot kernel row a switch: a second click keeps only the running kernel; wrap the kernel buttons over rows of three.
- Remove the Refresh button from the Snapshot panel.
- Add a Snapshot plugin (mabox/snapshot) with profiles to build an ISO with mabox-snapshot; Explain shows the plan, Build opens a terminal.
- List the newest ISOs in the Snapshot panel and write one to a USB stick with mabox-persistence-usb.
- Add an encrypt on/off switch to the Personal snapshot card in the Snapshot panel.
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
- Replace pamac-manager with neoarch for Add/Remove software, moved to the settings menu.
- Add Edit autostart to the settings menu.
- Add Ctrl+Keypad0 to launch scrcpy.
- Add Ctrl+Alt+Left and Ctrl+Alt+Right to send a window to the previous or next workspace.
- List Ctrl+Keypad0, Ctrl+Alt+Left and Ctrl+Alt+Right in the Keys panel.
- Add neoarch as an optional dependency.
