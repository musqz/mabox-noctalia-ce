# Luciole

## Scripts

Scripts live in `~/.local/share/luciole/scripts/`. Open the folder from Luciole: right click the background, *Scripts*, *Open Scripts Folder*.

Example, `~/.local/share/luciole/scripts/file-size`:

```sh
#!/bin/sh
exec notify-send "Size" "$(du -ch "$@" | tail -1)"
```

```sh
chmod 755 ~/.local/share/luciole/scripts/file-size
```

- The script gets the selected paths as separate arguments; quote `"$@"`. The working directory is the folder of the pane. From the background menu it gets no paths.
- The scripts folder, its parent `luciole` and each script must be owned by you or root and not writable by group or others. Symlinks to such files work.
- Hidden files, non-executable files, `.desktop` files and nested folders are not listed. The menu shows at most 64 scripts.
- Scripts are not sandboxed.

### Mabox scripts

| Script | Command |
|---|---|
| `convert` | `mb-convert pick FILE...` |
| `set-as-wallpaper` | `mb-wallpaper-image FILE` |
| `set-wallpaper-dir` | `mb-wallpaper-dir FOLDER` |

The repo copies are in `configs/luciole/scripts/`. The package installs them to `/usr/share/mabox-noctalia-ce/luciole-scripts/`, and `mb-migrate` links them into the scripts folder. A script of the same name stays.

`mb-convert PRESET FILE...` runs one preset directly: `mp4`, `hevc`, `webm`, `av1`, `mp4-remux`, `mkv-remux`, `gif-low`, `gif-medium`, `gif-high`, `mp3`, `opus`, `ogg`, `m4a`, `flac`, `wav`, `png`, `jpg`, `webp`, `avif`. Output goes next to the source and never overwrites.

## Colours

Luciole reads `~/.config/luciole/colors.toml` and reloads it when the file changes. Noctalia writes it with its builtin template `luciole`, which is listed in `builtin_ids` in `~/.config/noctalia/config.toml`:

```toml
[theme.templates]
builtin_ids = ["btop", "gtk3", "gtk4", "qt", "luciole"]
```

Render the templates again for the current palette:

```sh
noctalia msg templates-apply
```

- A warning `failed to open template input /usr/share/luciole/templates/colors.toml` in `~/.cache/noctalia/noctalia.log` means the old user template `[theme.templates.user.luciole]` is still active. `mb-migrate` removes it and adds the builtin id.
- Check the file: `grep '^primary' ~/.config/luciole/colors.toml` should match the primary colour of the bar.
- Other settings of Luciole are in `~/.config/luciole/settings.toml`.
