--!nonstrict
-- Saved wallpaper folders. Click one to make it the wallpaper directory.

local kbd = require("./lib/kbd.luau")
local dirs = require("./lib/dirs.luau")

local items = {}
local current = ""
local err = nil
local note = nil
local armed = nil
local minutes = nil
local draft = nil

local render

local function remove(i)
  if armed == i then
    local p = table.remove(items, i)
    armed = nil
    kbd.clear()
    if not dirs.save(items) then
      table.insert(items, i, p)
    end
  else
    armed = i
  end
  render()
end

local function pick(p)
  note = "Setting " .. p
  err = nil
  render()
  dirs.apply(p, function(r)
    if r.exitCode == 0 then
      current = p
      err = nil
      note = "Wallpaper folder set"
    else
      note = nil
      err = "Could not set the folder (see the notification)"
    end
    render()
  end)
end

local function setMinutes()
  if not draft then
    return
  end
  local n = tonumber(string.match(noctalia.string.trim(draft), "^%d+$"))
  if not n or n < 1 or n > 1440 then
    err = "Enter whole minutes, 1 to 1440"
    render()
    return
  end
  dirs.setInterval(n, function(ok)
    if ok then
      minutes = n
      draft = nil
      err = nil
      note = "Slideshow every " .. n .. " min"
    else
      note = nil
      err = "Could not set the interval"
    end
    render()
  end)
end

local function addFolder()
  dirs.browse(current ~= "" and current or noctalia.getenv("HOME"))
end

function render()
  kbd.begin()
  kbd.stop("add", 0, 1, addFolder)
  local rows = {}
  for i, p in ipairs(items) do
    kbd.stop("p" .. i, i, 1, function() pick(p) end)
    kbd.stop("d" .. i, i, 2, function() remove(i) end)
    table.insert(rows, ui.row({ key = "r" .. i, gap = 6, align = "center", padding = 4 }, {
      ui.label({ text = p, flexGrow = 1, maxLines = 1, color = p == current and "primary" or "on_surface" }),
      ui.button({ key = "p" .. i, glyph = p == current and "circle-check" or "circle", variant = p == current and "primary" or "ghost", controlSize = "sm", selected = kbd.sel("p" .. i), tooltip = "Select as wallpaper folder", onClick = function() pick(p) end }),
      ui.button({ key = "d" .. i, glyph = "trash", selected = kbd.sel("d" .. i), text = armed == i and "Click again" or nil, variant = armed == i and "destructive" or "ghost", controlSize = "sm", tooltip = "Remove from list", onClick = function() remove(i) end }),
    }))
  end
  if #rows == 0 then
    table.insert(rows, ui.label({ text = "No saved folders", color = "on_surface_variant" }))
  end
  panel.render(ui.column({ gap = 8, padding = 12 }, {
    ui.button({ key = "add", glyph = "folder-open", text = "Add folder", variant = "ghost", selected = kbd.sel("add"), onClick = addFolder }),
    ui.row({ gap = 6, align = "center" }, {
      ui.label({ text = "Slideshow every", color = "on_surface_variant" }),
      ui.input({ key = "mins", value = draft or (minutes and tostring(minutes)) or "", width = 64, controlSize = "sm", frameVisible = true, tooltip = "Minutes between wallpapers", onChange = function(t) draft = t end, onSubmit = setMinutes }),
      ui.label({ text = "min", color = "on_surface_variant" }),
      ui.button({ key = "savemins", glyph = "device-floppy", text = "Save", variant = "ghost", controlSize = "sm", onClick = setMinutes }),
    }),
    err and ui.label({ text = err, color = "error" }) or note and ui.label({ text = note, color = "primary" }) or ui.box({ height = 0 }),
    ui.scroll({ key = "list", gap = 0, height = 300, revealKey = kbd.reveal() }, rows),
  }))
end

function onKey(chord, pressed)
  if not pressed then
    return
  end
  if chord == "alt+s" then
    kbd.clear()
    armed = nil
    render()
  elseif kbd.key(chord) == "moved" then
    armed = nil
    render()
  end
end

function onOpen()
  kbd.clear()
  draft = nil
  items = dirs.load()
  err = nil
  note = nil
  armed = nil
  render()
  dirs.interval(function(m)
    minutes = m
    render()
  end)
  dirs.current(function(p)
    current = p
    local known = false
    for _, q in ipairs(items) do
      known = known or q == p
    end
    if p ~= "" and not known then
      table.insert(items, 1, p)
      dirs.save(items)
    end
    render()
  end)
end
