# Install apps

Open the panel with `W-i`, the root menu or a right-click on the launcher button.

- Type in the filter to search by name, package or description.
- Click *Install*. A terminal opens with `sudo pacman -S --needed`: enter your password and confirm. The panel closes; it reopens when you close the terminal.
- The row shows *installed* when pacman reports the package.

Notes:
- Pacman repos only. No AUR, Flatpak or Snap.
- Edit the list in `/usr/share/mabox-noctalia-ce/install.csv`: `category,package,name,description`.
