# mabox-noctalia-ce

Noctalia session on labwc for Mabox Linux. Pick **Noctalia CE** at the login screen. It differs from the original mabox-noctalia in config, scripts and packages.

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

## Remove

```sh
./install.sh --uninstall
rm -rf ~/.config/mabox-noctalia-ce
```

`--uninstall` removes the package and the packages the script installed.

## Docs

- [docs/guide.md](docs/guide.md): bar, theme, menu, monitors, tips.
- [docs/keys.md](docs/keys.md): hotkeys and the Keys panel.
- [docs/tools.md](docs/tools.md): panels, desktop widgets, music and scripts.
- [docs/snapshot.md](docs/snapshot.md): build an ISO, then USB or VM.
- [docs/music.md](docs/music.md): music launcher and media keys.
- [docs/overview.md](docs/overview.md): files, paths and tools.

## Screenshot

<a href="docs/desktop.png"><img alt="Noctalia CE desktop" src="docs/desktop.png" width="860" /></a>
