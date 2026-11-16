# Music

The `/music` launcher plugin and `mpv-play-stream` read `~/.config/mabox/mb-music/yt_music_list.csv`.

| Key | Tool |
|---|---|
| `W-m` | music panel; `/music` in the launcher does the same search |
| `C-S-2` | add a track to the playlist |
| `C-S-1` | `mpv-play-stream`: play a copied URL in mpv |
| `XF86AudioPlay` / `Stop` / `Next` / `Prev` | `noctalia msg media toggle / stop / next / previous` |

## Setup

`./install.sh` installs the `/music` plugin. By hand:

1. Install `mpv`, `socat`, `yt-dlp`, `mpv-mpris` and `yad`.
2. `noctalia msg plugins source add mabox path /usr/share/mabox-noctalia-ce/plugins`
3. `noctalia msg plugins enable mabox/music`

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
3. Check Artist and Title (filled from `yt-dlp`), pick a category, press Enter or Add.

The category stays selected until you pick another. Choose "+ New category" to create one.

## Play a URL

1. Copy a video or stream URL.
2. Press `C-S-1`.
3. Press Enter to play it in mpv.

## Use

1. Press `W-m`.
2. Pick a radio group or category in the sidebar, or type to search stations and tracks.
3. Press a row to play it; the shuffle and play buttons on a card start the whole group.
4. Pause, skip and stop with the buttons under the search field, the media keys or the bar media widget.

The sidebar Tools open the visualiser, PyRadio, the volume control and the station and playlist files.

Note: `mpv-mpris` exposes mpv to the media keys and bar widget.

## Check

- `playerctl -l` lists `mpv.instance-*` while playing.
- `noctalia msg media toggle` pauses and resumes.
