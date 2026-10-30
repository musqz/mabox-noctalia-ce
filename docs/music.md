# Music

Two separate players read `~/.config/mabox/mb-music/yt_music_list.csv`.

| Key | Tool |
|---|---|
| `W-m` | `mb-music` (jgmenu) |
| `W-S-m` | `/music` in the Noctalia launcher |
| `XF86AudioPlay` / `Stop` / `Next` / `Prev` | `noctalia msg media toggle / stop / next / previous` |

## Setup

`./install.sh` installs the `/music` plugin. By hand:

1. Install `mpv`, `socat`, `yt-dlp` and `mpv-mpris`.
2. `noctalia msg plugins source add musqz-local path <repo>/configs/mabox-noctalia-ce/plugins`
3. `noctalia msg plugins enable musqz/music`

## Playlist file

One entry per line: `Title,URL`. A line `Category,-` starts a category; `END,-` ends it.

```
Legendary Albums,-
Portishead - Dummy 1994,https://www.youtube.com/watch?v=qNq9TJ4QCas
END,-
```

## Use

1. Press `W-S-m`.
2. Pick a category, or "Shuffle all".
3. Inside a category: "Shuffle <category>", "Play <category>" or a single track.
4. Pause, skip and stop with the media keys or the bar media widget.

Note: `mpv-mpris` exposes mpv to the media keys and bar widget. `mb-music` uses its own mpv; stop one before starting the other.

## Check

- `playerctl -l` lists `mpv.instance-*` while playing.
- `noctalia msg media toggle` pauses and resumes.
