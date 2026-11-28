# Luciole scripts

Right click a file or folder in Luciole and open **Scripts**. Every script in the list works on the selected files.

| Script | What it does |
|---|---|
| `convert` | Opens a list with the conversions that fit the file. |
| `set-as-wallpaper` | Sets the selected picture as the wallpaper. |
| `set-wallpaper-dir` | Makes the selected folder the wallpaper folder. |

## Convert

1. Select one or more files of the same kind.
2. Right click, **Scripts**, **convert**.
3. Pick a conversion in the list and press **OK**.

The new file appears next to the original. A notification has the buttons **Open folder** and **Play**.

| File | Conversions |
|---|---|
| Image, also SVG | PNG, JPG, WebP, AVIF |
| Video | MP4 (H.264 and H.265), WebM, MKV (AV1), MKV to MP4 and MP4 to MKV without re-encoding, GIF in three sizes, audio only (MP3, Opus, FLAC) |
| Audio | MP3, Opus, Ogg Vorbis, AAC (m4a), FLAC, WAV |

- An SVG is drawn at four times its size. JPG gets a white background.
- Luciole shows every script for every file. Select files of one kind, or **convert** tells you it cannot mix them.
- The same conversions are in the root menu under *Converter*.

## Add your own script

1. Right click the empty background, **Scripts**, **Open Scripts Folder**.
2. Put your script in the folder and make it executable.
3. Open the **Scripts** menu again. The file name is the menu entry.

An example and the rules are in the [technical notes](https://github.com/musqz/mabox-noctalia-ce/blob/main/docs/technical/luciole.md).
