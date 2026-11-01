# Music

The `/music` launcher plugin and `mpv-play-stream` read `~/.config/mabox/mb-music/yt_music_list.csv`.

| Key | Tool |
|---|---|
| `W-m` | `/music` in the Noctalia launcher |
| `C-S-2` | `mb-music-add-url`: add a track to the playlist |
| `C-S-1` | `mpv-play-stream`: play a copied URL in mpv |
| `XF86AudioPlay` / `Stop` / `Next` / `Prev` | `noctalia msg media toggle / stop / next / previous` |

## Setup

`./install.sh` installs the `/music` plugin. By hand:

1. Install `mpv`, `socat`, `yt-dlp`, `mpv-mpris` and `yad`.
2. `noctalia msg plugins source add musqz-local path <repo>/configs/mabox-noctalia-ce/plugins`
3. `noctalia msg plugins enable musqz/music`

## Playlist file

One entry per line: `Title,URL`. A line `Category,-` starts a category; `END,-` ends it.

```
Legendary Albums,-
Portishead - Dummy 1994,https://www.youtube.com/watch?v=qNq9TJ4QCas
END,-
```

## Add a track

1. Copy a YouTube or stream URL.
2. Press `C-S-2`.
3. Fill in Artist, Title and Category, then press Enter.

The URL is pre-filled from the clipboard. On Wayland this needs `wl-clipboard`.

## Play a URL

1. Copy a video or stream URL.
2. Press `C-S-1`.
3. Press Enter to play it in mpv.

## Use

1. Press `W-m`.
2. Pick a category, or "Shuffle all".
3. Inside a category: "Shuffle <category>", "Play <category>" or a single track.
4. Pause, skip and stop with the media keys or the bar media widget.

Note: `mpv-mpris` exposes mpv to the media keys and bar widget.

## Check

- `playerctl -l` lists `mpv.instance-*` while playing.
- `noctalia msg media toggle` pauses and resumes.
