# mabox-noctalia-ce

musqz's community edition of Mabox Noctalia: a [Noctalia](https://github.com/noctalia-dev/noctalia-shell) session on labwc, selectable as **Noctalia CE** at the login screen. It differs from the original mabox-noctalia in config, scripts and package choices.

Work in progress. This repo is for inspiration and development: take what you like, or install it as is.

- **Separate:** own session entry and own config in `~/.config/mabox-noctalia-ce/`. Other sessions are not touched.
- **Install:** `./install.sh` installs the needed packages and builds the `mabox-noctalia-ce` package. Packages you already have are skipped.
- **Remove:** `./install.sh --uninstall` removes the package and the packages the script installed. Then `rm -rf ~/.config/mabox-noctalia-ce`.

Requires Mabox Linux with `noctalia` 5.4 or newer (repo `[maboxlinux]`).

<img width="2560" height="1440" alt="Image" src="https://github.com/user-attachments/assets/8f4e52f4-16f8-47b7-a161-cad705316ce2" />

<p>
  <img alt="Root menu with icons" src="docs/root-menu.png" width="32%" />
  <img alt="skippy-wl window switcher" src="docs/skippy-wl.png" width="32%" />
  <img alt="skippy-wl multiselect" src="docs/skippy-wl-multiselect.png" width="32%" />
</p>
