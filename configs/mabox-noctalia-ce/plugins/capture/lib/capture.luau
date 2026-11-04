--!nonstrict
-- Capture: buttons call mb-screenshot, screenrec-toggle, mb-shots-interval and mb-gifmaker.
-- Choices live in <plugin data dir>/settings.

local pinSide = require("./side.luau")
local kbd = require("./kbd.luau")

return function(pinned)
local REFRESH = 2
local HOME = noctalia.getenv("HOME")

local DEFAULTS = {
  shot_delay = "0",
  shot_format = "png",
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

local PROBE = [[
p=${XDG_RUNTIME_DIR:-/tmp}/mb-shots-interval.pid
pgrep -x wl-screenrec >/dev/null && echo rec=1 || echo rec=0
{ [ -f "$p" ] && kill -0 "$(cat "$p")" 2>/dev/null; } && echo iv=1 || echo iv=0
echo n=$(mb-shots-interval -n 2>/dev/null || echo 0)
find "$HOME/Pictures/screenshots" "$HOME/Videos/Recordings" "$HOME/Pictures/Mabox-Animations" -maxdepth 1 -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -5 | cut -d' ' -f2-
]]

local recording = false
local intervalOn = false
local recent = {}
local ivCount = 0
local armed = false
local armedAt = 0
local ticks = 0
local lastRun = 0
local render

-- Keyboard cursor. Row 1 is the top bar; the pinned windows take no keys, so they register no stops.
local kr = 1
local function nextRow()
  kr += 1
  return kr
end
-- Button with a keyboard stop; ringProps carries layout growth for the frame around it.
local block = ""
local function kbtn(id, row, col, props, ringProps)
  if pinned then
    return ui.button(props)
  end
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

local function loadSettings()
  local path = settingsPath()
  local raw = path and noctalia.readFile(path)
  for l in string.gmatch(raw or "", "[^\n]+") do
    local k, v = string.match(l, "^([%w_]+)=(.*)$")
    if k and DEFAULTS[k] and string.match(v, "^[%w]+$") then
      S[k] = v
    end
  end
end

local function setSetting(k, v)
  loadSettings()
  S[k] = v
  local dir = noctalia.pluginDataDir()
  if not dir then
    return
  end
  noctalia.mkdirAll(dir)
  local out = {}
  for key in pairs(DEFAULTS) do
    table.insert(out, key .. "=" .. S[key])
  end
  table.sort(out)
  noctalia.writeFile(settingsPath(), table.concat(out, "\n") .. "\n")
end

-- Probe

local function refresh()
  lastRun = ticks
  noctalia.runAsync({ "sh", "-c", PROBE }, function(result)
    local files = {}
    for l in string.gmatch(result.stdout or "", "[^\n]+") do
      local k, v = string.match(l, "^(%w+)=(%d+)$")
      if k == "rec" then
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
    render()
  end)
end

-- Run a command with the panel out of the way. Pinned panels come back afterwards
-- (not for recordings, they would end up in the video).
local function launch(argv, reopen)
  panel.close()
  local sh = 'sleep 0.2; "$@"'
  if reopen and pinned then
    sh = sh .. "; noctalia msg panel-open mabox/capture:pinned-" .. pinned
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
      noctalia.runAsync({ "xdg-open", path })
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
  local head = headingWithFolder("Screenshot", HOME .. "/Pictures/screenshots")
  local r1, r2, r3 = nextRow(), nextRow(), nextRow()
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
  })
end

local function recBlock()
  block = "rec-"
  local rows = { headingWithFolder(recording and "Recording" or "Record", HOME .. "/Videos/Recordings") }
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
  local rows = { headingWithFolder(title, HOME .. "/Pictures/shot_interval") }
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

local function recentBlock()
  block = "recent-"
  local rows = { heading("Recent") }
  if #recent == 0 then
    table.insert(rows, ui.label({ text = "Nothing yet", color = "on_surface_variant" }))
  end
  for _, path in ipairs(recent) do
    local name = string.match(path, "([^/]+)$") or path
    table.insert(rows, kbtn("rc-" .. path, nextRow(), 1, { text = name, variant = "ghost", controlSize = "sm", contentAlign = "start", onClick = function()
      noctalia.runAsync({ "xdg-open", path })
    end }))
  end
  return card(rows)
end

render = function()
  if not pinned then
    kbd.begin()
  end
  kr = 1
  local top = ui.row({ gap = 6, align = "center" }, {
    ui.label({ text = recording and "Capture  (recording)" or "Capture", flexGrow = 1 }),
    pinned and ui.button({ glyph = "arrows-left-right", variant = "ghost", controlSize = "sm", tooltip = "Move to the other side", onClick = function() pinSide.swap("capture", pinned) end }) or ui.spacer({ width = 0 }),
    kbtn("pin", 1, 1, { glyph = pinned and "x" or "pin", variant = "ghost", controlSize = "sm", tooltip = pinned and "Close" or "Pin window", onClick = function()
      panel.close()
      if not pinned then
        pinSide.toggle("capture")
      end
    end }),
  })
  local body = ui.column({ gap = 8 }, { shotBlock(), intervalBlock(), recBlock(), recentBlock() })
  if pinned then
    panel.render(ui.column({ gap = 8, padding = 10, flexGrow = 1 }, { top, ui.scroll({ gap = 8, flexGrow = 1, key = "list" }, { body }) }))
  else
    panel.render(ui.column({ gap = 8, padding = 12 }, { top, body }))
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
  armed = false
  loadSettings()
  ticks = 0
  render()
  refresh()
end

local function tick()
  ticks += 1
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
