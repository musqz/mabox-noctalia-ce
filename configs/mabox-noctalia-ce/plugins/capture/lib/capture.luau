--!nonstrict
-- Capture: buttons call mb-screenshot, screenrec-toggle, mb-shots-interval and mb-gifmaker.
-- Choices live in <plugin data dir>/settings.

local pinSide = require("./side.luau")
local kbd = require("./kbd.luau")
local logo = require("./celogo.luau")
local hotkey = require("./hotkey.luau")

return function(pinned)
local REFRESH = 2
local HOME = noctalia.getenv("HOME")

local DEFAULTS = {
  shot_delay = "0",
  shot_format = "png",
  shot_output = "focus",
  rec_container = "mp4",
  rec_fps = "30",
  rec_audio = "none",
  interval = "5",
  iv_mode = "screen",
  gif_size = "1280",
}
local S = {}
for k, v in pairs(DEFAULTS) do
  S[k] = v
end

-- Output folders; empty means the default. The scripts read the same keys from the settings file.
local DIRS = {
  { key = "shot_dir", label = "Screenshots", default = "~/Pictures/screenshots" },
  { key = "rec_dir", label = "Recordings", default = "~/Videos/Recordings" },
  { key = "iv_dir", label = "Interval screenshots", default = "~/Pictures/shot_interval" },
  { key = "gif_dir", label = "GIF animations", default = "~/Pictures/Mabox-Animations" },
}
local D = {}
local showSettings = false

local PROBE = [[
p=${XDG_RUNTIME_DIR:-/tmp}/mb-shots-interval.pid
r=${XDG_RUNTIME_DIR:-/tmp}/mb-screenrec/pid
{ pgrep -x wl-screenrec >/dev/null || { [ -f "$r" ] && kill -0 "$(cat "$r")" 2>/dev/null; }; } && echo rec=1 || echo rec=0
{ [ -f "$p" ] && kill -0 "$(cat "$p")" 2>/dev/null; } && echo iv=1 || echo iv=0
wlr-randr 2>/dev/null | sed -n 's/^\([^ ][^ ]*\) .*/out=\1/p'
echo n=$(mb-shots-interval -n 2>/dev/null || echo 0)
find "$1" "$2" "$3" -maxdepth 1 -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -5 | cut -d' ' -f2-
]]

local recording = false
local intervalOn = false
local recent = {}
local outputs = { "focus" }
local THUMBS = (noctalia.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/mb-capture-thumbs"
local thumbs = {} -- path -> thumbnail file, "pending" or "failed"
local hovered = nil
local recentSig = ""
local ivCount = 0
local armed = false
local armedAt = 0
local ticks = 0
local lastRun = 0
local render

-- Keyboard cursor. Row 1 is the top bar.
local kr = 1
local function nextRow()
  kr += 1
  return kr
end
-- Button with a keyboard stop; ringProps carries layout growth for the frame around it.
local block = ""
local function kbtn(id, row, col, props, ringProps)
  kbd.stop(id, row, col, props.onClick)
  ringProps = ringProps or {}
  ringProps.key = "k-" .. id
  ringProps.align = "stretch"
  ringProps.padding = 3
  ringProps.radius = 8
  ringProps.border = "on_surface"
  ringProps.borderWidth = kbd.sel(id) and 3 or 0
  return ui.column(ringProps, { ui.button(props) })
end

-- Settings

local function settingsPath()
  local dir = noctalia.pluginDataDir()
  return dir and dir .. "/settings" or nil
end

local function isDirKey(k)
  for _, d in ipairs(DIRS) do
    if d.key == k then
      return true
    end
  end
  return false
end

local function loadSettings()
  D = {}
  local path = settingsPath()
  local raw = path and noctalia.readFile(path)
  for l in string.gmatch(raw or "", "[^\n]+") do
    local k, v = string.match(l, "^([%w_]+)=(.*)$")
    if k and DEFAULTS[k] and string.match(v, "^[%w-]+$") then
      S[k] = v
    elseif k and isDirKey(k) then
      D[k] = noctalia.string.trim(v)
    end
  end
end

-- The folder in use, with ~ expanded.
local function dirPath(key)
  local v = D[key]
  if not v or v == "" then
    for _, d in ipairs(DIRS) do
      if d.key == key then
        v = d.default
      end
    end
  end
  if string.sub(v, 1, 1) == "~" then
    v = HOME .. string.sub(v, 2)
  end
  return v
end

local function setSetting(k, v)
  loadSettings()
  if isDirKey(k) then
    D[k] = v
  else
    S[k] = v
  end
  local dir = noctalia.pluginDataDir()
  if not dir then
    return
  end
  noctalia.mkdirAll(dir)
  local out = {}
  for key in pairs(DEFAULTS) do
    table.insert(out, key .. "=" .. S[key])
  end
  for _, d in ipairs(DIRS) do
    if D[d.key] and D[d.key] ~= "" then
      table.insert(out, d.key .. "=" .. D[d.key])
    end
  end
  table.sort(out)
  noctalia.writeFile(settingsPath(), table.concat(out, "\n") .. "\n")
end

-- Thumbnails: made on first hover into the runtime dir; pruned to the files in Recent.

local THUMB_CMD = [[
mkdir -p "$1" || exit 1
case "$2" in
  *.mp4|*.mkv|*.webm) ffmpeg -loglevel error -y -ss 0.5 -i "$2" -frames:v 1 -vf scale=320:-2 "$3" ;;
  *) magick "$2[0]" -thumbnail 320x "$3" ;;
esac
]]

local PRUNE_CMD = [[
cd "$1" 2>/dev/null || exit 0
shift
for f in *; do
  [ -e "$f" ] || continue
  keep=0
  for k; do [ "$f" = "$k" ] && keep=1; done
  [ "$keep" = 1 ] || rm -f -- "$f"
done
]]

local function thumbName(path)
  return (string.gsub(string.match(path, "([^/]+)$") or path, "[^%w._-]", "_")) .. ".png"
end

local function ensureThumb(path)
  if thumbs[path] then
    return
  end
  thumbs[path] = "pending"
  local out = THUMBS .. "/" .. thumbName(path)
  noctalia.runAsync({ "sh", "-c", THUMB_CMD, "sh", THUMBS, path, out }, function(result)
    thumbs[path] = result.exitCode == 0 and out or "failed"
    render()
  end)
end

local function pruneThumbs(files)
  local names, sig = {}, table.concat(files, "\n")
  if sig == recentSig then
    return
  end
  recentSig = sig
  local keep = {}
  for _, f in ipairs(files) do
    table.insert(names, thumbName(f))
    keep[f] = true
  end
  for path in pairs(thumbs) do
    if not keep[path] then
      thumbs[path] = nil
    end
  end
  local argv = { "sh", "-c", PRUNE_CMD, "sh", THUMBS }
  for _, n in ipairs(names) do
    table.insert(argv, n)
  end
  noctalia.runAsync(argv)
end

-- Probe

local function refresh()
  lastRun = ticks
  noctalia.runAsync({ "sh", "-c", PROBE, "sh", dirPath("shot_dir"), dirPath("rec_dir"), dirPath("gif_dir") }, function(result)
    local files = {}
    local outs = { "focus" }
    for l in string.gmatch(result.stdout or "", "[^\n]+") do
      local k, v = string.match(l, "^(%w+)=(%d+)$")
      local o = string.match(l, "^out=(.+)$")
      if o then
        table.insert(outs, o)
      elseif k == "rec" then
        recording = v == "1"
      elseif k == "iv" then
        intervalOn = v == "1"
      elseif k == "n" then
        ivCount = tonumber(v) or 0
      else
        table.insert(files, l)
      end
    end
    recent = files
    outputs = outs
    pruneThumbs(files)
    render()
  end)
end

-- Run a command with the panel out of the way. Pinned panels come back afterwards
-- (not for recordings, they would end up in the video).
local function launch(argv, reopen)
  pinSide.close("capture", pinned)
  local sh = 'sleep 0.4; "$@"'
  if reopen and pinned then
    sh = sh .. "; " .. pinSide.reopenCmd("capture")
  end
  local cmd = { "setsid", "-f", "sh", "-c", sh, "sh" }
  for _, a in ipairs(argv) do
    table.insert(cmd, a)
  end
  noctalia.runAsync(cmd)
end

local function shot(mode, annotate)
  if annotate then
    launch({ "noctalia", "msg", "screenshot-annotate" }, true)
    return
  end
  local argv = { "mb-screenshot" }
  if S.shot_delay ~= "0" then
    table.insert(argv, "--delay")
    table.insert(argv, S.shot_delay)
  end
  if S.shot_format ~= "png" then
    table.insert(argv, "--format")
    table.insert(argv, S.shot_format)
  end
  for _, a in ipairs(mode) do
    table.insert(argv, a)
  end
  if #mode == 1 and mode[1] == "screenshot-fullscreen" and S.shot_output ~= "focus" then
    for _, o in ipairs(outputs) do
      if o == S.shot_output then
        table.insert(argv, o)
      end
    end
  end
  setSetting("shot_delay", "0")
  launch(argv, true)
end

local function record(area)
  local argv = { "screenrec-toggle", "-c", S.rec_container, "-f", S.rec_fps, "-a", S.rec_audio }
  if not area then
    table.insert(argv, "-o")
    table.insert(argv, "auto")
  end
  launch(argv, false)
end

-- Rows

local function card(children)
  return ui.column({ fill = "surface_variant", radius = 8, padding = 8, gap = 4 }, children)
end

local function heading(text)
  return ui.label({ text = string.upper(text), fontSize = 11, color = "primary" })
end

-- Section heading with an outlined button that opens the folder of that section.
local function headingWithFolder(text, path)
  return ui.row({ gap = 6, align = "center" }, {
    ui.label({ text = string.upper(text), fontSize = 11, color = "primary", flexGrow = 1 }),
    kbtn(block .. "folder", nextRow(), 1, { text = "Folder", glyph = "folder-open", variant = "outline", controlSize = "sm", onClick = function()
      noctalia.runAsync({ "sh", "-c", 'mkdir -p "$1" && xdg-open "$1"', "sh", path })
      if not pinned then
        panel.close()
      end
    end }),
  })
end

-- Setting shown as one small button; a click moves to the next value.
local function cycle(row, col, label, key, values, suffix, names, hint)
  local at = 0
  for n, v in ipairs(values) do
    if v == S[key] then
      at = n
    end
  end
  local shown = names and names[S[key]] or S[key] .. (suffix or "")
  return kbtn("y-" .. key, row, col, { text = label and (label .. " " .. shown) or shown, variant = "ghost", controlSize = "sm", flexGrow = 1, tooltip = (hint or label or key) .. ": click for the next value", onClick = function()
    setSetting(key, values[at % #values + 1])
    render()
  end }, { flexGrow = 1 })
end

local function action(row, col, text, glyph, onClick, variant)
  return kbtn(block .. text, row, col, { text = text, glyph = glyph, variant = variant or "primary", flexGrow = 1, onClick = onClick }, { flexGrow = 1 })
end

local function shotBlock()
  block = "shot-"
  local head = headingWithFolder("Screenshot", dirPath("shot_dir"))
  local r1, r2, r3, r4 = nextRow(), nextRow(), nextRow(), nextRow()
  return card({
    head,
    ui.row({ gap = 4 }, {
      action(r1, 1, "Screen", "device-desktop", function() shot({ "screenshot-fullscreen" }) end),
      action(r1, 2, "All", "layout-grid", function() shot({ "screenshot-fullscreen", "all" }) end),
      action(r1, 3, "Window", "app-window", function() shot({ "screenshot-window" }) end),
    }),
    ui.row({ gap = 4 }, {
      action(r2, 1, "Area", "crop", function() shot({ "screenshot-region" }) end),
      action(r2, 2, "Annotate", "pencil", function() shot(nil, true) end),
    }),
    ui.row({ gap = 4 }, {
      cycle(r3, 1, "Delay", "shot_delay", { "0", "3", "5", "10", "30" }, "s", nil, "Delay for the next screenshot only"),
      cycle(r3, 2, "Format", "shot_format", { "png", "jpg", "webp", "avif" }),
    }),
    ui.row({ gap = 4 }, {
      cycle(r4, 1, "Screen", "shot_output", outputs, nil, { focus = "focused" }, "Monitor for the Screen button"),
    }),
  })
end

local function recBlock()
  block = "rec-"
  local rows = { headingWithFolder(recording and "Recording" or "Record", dirPath("rec_dir")) }
  if recording then
    table.insert(rows, action(nextRow(), 1, "Stop recording", "player-stop", function()
      launch({ "pkill", "-INT", "-x", "wl-screenrec" }, false)
    end, "destructive"))
  else
    local r1, r2 = nextRow(), nextRow()
    table.insert(rows, ui.row({ gap = 4 }, {
      action(r1, 1, "Screen", "device-desktop", function() record(false) end),
      action(r1, 2, "Area", "crop", function() record(true) end),
    }))
    table.insert(rows, ui.row({ gap = 4 }, {
      cycle(r2, 1, nil, "rec_container", { "mp4", "mkv" }, nil, nil, "Container"),
      cycle(r2, 2, nil, "rec_fps", { "15", "30", "60" }, " fps", nil, "Frame rate"),
      cycle(r2, 3, "Audio", "rec_audio", { "none", "system", "mic" }),
    }))
  end
  return card(rows)
end

local function intervalBlock()
  block = "iv-"
  local title = (intervalOn and "Interval (running)" or "Interval") .. (ivCount > 0 and ("  " .. ivCount .. " images") or "")
  local rows = { headingWithFolder(title, dirPath("iv_dir")) }
  local r1 = nextRow()
  table.insert(rows, ui.row({ gap = 4 }, {
    action(r1, 1, intervalOn and "Stop" or "Start", intervalOn and "player-stop" or "player-play", function()
      if intervalOn then
        launch({ "mb-shots-interval", "-s" }, false)
      elseif S.iv_mode == "area" then
        launch({ "mb-shots-interval", "-a", S.interval }, false)
      else
        launch({ "mb-shots-interval", "-o", "auto", S.interval }, false)
      end
    end, intervalOn and "destructive" or "primary"),
    action(r1, 2, "GIF", "gif", function() launch({ "mb-gifmaker", "-s", S.gif_size }, true) end),
  }))
  if not intervalOn and ivCount > 0 then
    local r2 = nextRow()
    table.insert(rows, ui.row({ gap = 4 }, {
      kbtn("iv-backup", r2, 1, { text = "Backup", glyph = "archive", variant = "outline", controlSize = "sm", flexGrow = 1, tooltip = "Move the images to backup/DATE", onClick = function()
        noctalia.runAsync({ "mb-shots-interval", "-b" }, function() refresh() end)
      end }, { flexGrow = 1 }),
      kbtn("iv-delete", r2, 2, { text = armed and "Click again to delete" or "Delete all", glyph = "trash", variant = armed and "destructive" or "outline", controlSize = "sm", flexGrow = 1, onClick = function()
        if armed then
          armed = false
          noctalia.runAsync({ "mb-shots-interval", "-x" }, function() refresh() end)
        else
          armed = true
          armedAt = ticks
          render()
        end
      end }, { flexGrow = 1 }),
    }))
  end
  local opts = {}
  local r3 = nextRow()
  if not intervalOn then
    table.insert(opts, cycle(r3, 1, "Every", "interval", { "2", "5", "10", "30", "60" }, "s"))
    table.insert(opts, cycle(r3, 2, nil, "iv_mode", { "screen", "area" }, nil, nil, "Capture"))
  end
  table.insert(opts, cycle(r3, 3, "GIF", "gif_size", { "480", "800", "1280", "1920", "0" }, nil, { ["0"] = "original" }, "GIF size (longest side)"))
  table.insert(rows, ui.row({ gap = 4 }, opts))
  return card(rows)
end

-- Detached (setsid) so the dialog outlives the panel; the pick goes to a file read when the panel reopens.
local BROWSE = [[s=${1:-$HOME}
case $s in "~"*) s=$HOME${s#"~"} ;; esac
p=$(yad --file --directory --center --width=1000 --height=650 --title="$3" --filename="$s/")
[ -n "$p" ] && readlink -f "$p" > "$2"
if [ -n "$4" ]; then eval "$4"; else noctalia msg panel-close; noctalia msg panel-open mabox/capture:main; fi]]

local function pickFile(key)
  local dir = noctalia.pluginDataDir()
  return dir and (dir .. "/picked-" .. key) or nil
end

local function applyPicks()
  for _, d in ipairs(DIRS) do
    local f = pickFile(d.key)
    local pick = f and noctalia.string.trim(noctalia.readFile(f) or "") or ""
    if pick ~= "" then
      noctalia.writeFile(f, "")
      setSetting(d.key, pick)
      showSettings = true
    end
  end
end

local function settingsBlock()
  block = "set-"
  local rows = { heading("Folders") }
  table.insert(rows, ui.label({ text = "Where the files are saved. Empty: the default folder.", fontSize = 11, color = "on_surface_variant" }))
  for _, d in ipairs(DIRS) do
    local r = nextRow()
    table.insert(rows, ui.label({ text = d.label, fontSize = 12 }))
    table.insert(rows, ui.row({ gap = 6, align = "center" }, {
      ui.input({
        key = "dir-" .. d.key,
        value = D[d.key] or "",
        placeholder = d.default,
        controlSize = "sm",
        flexGrow = 1,
        onChange = function(text)
          setSetting(d.key, noctalia.string.trim(text))
        end,
      }),
      kbtn("open-" .. d.key, r, 1, { glyph = "folder-open", variant = "outline", controlSize = "sm", tooltip = "Open this folder", onClick = function()
        noctalia.runAsync({ "sh", "-c", 'mkdir -p "$1" && xdg-open "$1"', "sh", dirPath(d.key) })
      end }),
      kbtn("browse-" .. d.key, r, 2, { text = "Browse", variant = "outline", controlSize = "sm", onClick = function()
        local f = pickFile(d.key)
        if f then
          noctalia.mkdirAll(noctalia.pluginDataDir())
          noctalia.runAsync({ "setsid", "-f", "sh", "-c", BROWSE, "sh", dirPath(d.key), f, d.label, pinned and pinSide.reopenCmd("capture") or "" })
        end
      end }),
    }))
  end
  return card(rows)
end

local function recentBlock()
  block = "recent-"
  local rows = { heading("Recent") }
  if #recent == 0 then
    table.insert(rows, ui.label({ text = "Nothing yet", color = "on_surface_variant" }))
  end
  local preview = hovered
  for _, path in ipairs(recent) do
    local name = string.match(path, "([^/]+)$") or path
    if not hovered and kbd.sel("rc-" .. path) then
      preview = path
    end
    table.insert(rows, kbtn("rc-" .. path, nextRow(), 1, { text = name, variant = "ghost", controlSize = "sm", contentAlign = "start", onHover = function(state)
      hovered = state == "true" and path or nil
      if hovered then
        ensureThumb(path)
      end
      render()
    end, onClick = function()
      noctalia.runAsync({ "xdg-open", path })
    end }))
  end
  if preview then
    ensureThumb(preview)
    local t = thumbs[preview]
    if t and t ~= "failed" and t ~= "pending" then
      table.insert(rows, ui.image({ path = t, width = 300, height = 170, fit = "contain", radius = 6 }))
    end
  end
  return card(rows)
end

render = function()
  kbd.begin()
  kr = 1
  local title = ui.row({ gap = 6, align = "center" }, {
    logo(),
    ui.label({ text = showSettings and "Capture settings" or (recording and "Capture  (recording)" or "Capture") }),
    ui.label({ text = hotkey(pinned and "mb-pinned capture" or "mabox/capture:main"), color = "outline_variant", flexGrow = 1 }),
  })
  local top = ui.row({ gap = 6, align = "center" }, {
    ui.spacer({ flexGrow = 1 }),
    pinned and pinSide.dockButton("capture", pinned, render) or ui.spacer({ width = 0 }),
    pinned and pinSide.panelButton("capture", "main") or ui.spacer({ width = 0 }),
    pinned and kbtn("swap", 1, 1, { glyph = "arrows-left-right", variant = "ghost", controlSize = "sm", tooltip = "Move to the other side", onClick = function() pinSide.swap("capture", pinned) end }) or ui.spacer({ width = 0 }),
    kbtn("gear", 1, 2, { glyph = showSettings and "arrow-left" or "settings", variant = showSettings and "primary" or "ghost", controlSize = "sm", tooltip = showSettings and "Back to the buttons" or "Settings: output folders", onClick = function()
      showSettings = not showSettings
      kbd.clear()
      render()
    end }),
    kbtn("pin", 1, 3, { glyph = pinned and "x" or "pin", variant = "ghost", controlSize = "sm", tooltip = pinned and "Close" or "Pin window", onClick = function()
      pinSide.close("capture", pinned)
      if not pinned then
        pinSide.toggle("capture")
      end
    end }),
  })
  local body = showSettings and ui.column({ gap = 8 }, { settingsBlock() }) or ui.column({ gap = 8 }, { shotBlock(), intervalBlock(), recBlock(), recentBlock() })
  if pinned then
    pinSide.render(pinned, ui.column({ gap = 8, padding = 10, flexGrow = 1 }, { title, top, ui.scroll({ gap = 8, flexGrow = 1, key = "list", revealKey = kbd.reveal() and "k-" .. kbd.reveal() or nil }, { body }) }))
  else
    panel.render(ui.column({ gap = 8, padding = 12 }, { title, top, body }))
  end
end

local function handleKey(chord)
  if chord == "alt+s" then
    kbd.clear()
    render()
  elseif kbd.key(chord) == "moved" then
    render()
  end
end

local function open()
  kbd.clear()
  hovered = nil
  armed = false
  showSettings = false
  loadSettings()
  applyPicks()
  ticks = 0
  render()
  refresh()
end

local function tick()
  ticks += 1
  -- a folder picked in the dialog while the pinned window stayed loaded
  local before = showSettings
  loadSettings()
  applyPicks()
  if showSettings ~= before then
    render()
  end
  if armed and ticks - armedAt >= 5 then
    armed = false
    render()
  end
  if ticks - lastRun >= REFRESH then
    refresh()
  end
end

return open, tick, handleKey
end
