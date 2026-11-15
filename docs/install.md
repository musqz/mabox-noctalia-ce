# Install apps

Open the panel with `W-i`, the root menu or a right-click on the launcher button.

- Type in the filter to search by name, package or description.
- Click *Install*. Enter your password in the Noctalia window.
- The row shows *installed* when pacman reports the package.

Notes:
- Pacman repos only. No AUR, Flatpak or Snap.
- `pacman -S --needed` runs without `-Sy`. On *target not found*, run the Updates panel or enable the repo (multilib, Mabox).
- Edit the list in `/usr/share/mabox-noctalia-ce/install.csv`: `category,package,name,description`.
