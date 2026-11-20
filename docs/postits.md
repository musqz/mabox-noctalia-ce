# Post-its

Small windows on the desktop that show a note, a todo list or the agenda. Click in a note to type.

| Key | Tool |
|---|---|
| `W-A-y` | show the post-its; press again to close them |

`mb-postits` has no autostart. Start it from a terminal with options:

```sh
mb-postits --front --tasks First_list --agenda
```

| Option | Effect |
|---|---|
| `--front` | show the post-its above windows (default: on the desktop, under windows) |
| `--tasks LIST` | add a post-it with the open tasks of `~/.todo/LIST.txt` |
| `--agenda` | add a post-it with the next events from `~/caldir` |

## Notes

1. Open a note in the Notes panel.
2. Turn on **On screen**.

The post-it opens within a second. Turn the switch off to remove it. The body is saved after a short pause and when you click away.

## Tasks

- Tick the box to mark a task done. It stays in the list, struck through; untick to reopen it.
- Click the task text to open the Todo panel.
- The title bar has the due colour of the most urgent task.

## Agenda

- Shows the next events from `~/caldir/*/*.ics`, repeats included for 30 days.
- The title bar has the day colour of the nearest event.

## Window

- Drag the title strip to move.
- Right-click the title strip for the size (Small, Medium, Large), the text size and the close entries.
- `–` hides the post-it until the next start. `✕` (or *Remove from screen*) switches a note off for good; the note stays in Notes.
- Position, size and text size are saved in `~/.local/state/mb-postits/layout.json`.
