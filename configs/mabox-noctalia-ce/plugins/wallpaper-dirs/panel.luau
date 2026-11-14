--!nonstrict
-- Saved wallpaper folders. Click one to make it the wallpaper directory.

local kbd = require("./lib/kbd.luau")
local dirs = require("./lib/dirs.luau")
local logo = require("./lib/celogo.luau")
local hotkey = require("./lib/hotkey.luau")

local function card(key)
  return { key = key, fill = "surface_variant", radius = 10, padding = 12, gap = 10, border = "primary", borderWidth = 1 }
end

local items = {}
local current = ""
local err = nil
local note = nil
local armed = nil
local minutes = nil
local draft = nil
local auto = false
local order = nil

local EFFECTS = { "crt", "diamond", "disc", "fade", "golden", "honeycomb", "melt", "pixel", "stripes", "vortex", "wipe", "zoom" }
local tr = { open = false, effects = {}, duration = 1500, smooth = 0.3, startup = false, sync = false }

local THUMBS = (noctalia.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/mb-wallpaper-dirs-thumbs"
-- One random image of the folder as a 320 px png; a new file name per hover, because ui.image caches by path.
local THUMB_CMD = [[d=$1; out=$2; mkdir -p "$out" || exit 1
f=$(find "$d" -maxdepth 2 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.avif' \) 2>/dev/null | shuf -n1)
[ -n "$f" ] || exit 1
rm -f "$out"/*.png
magick "$f[0]" -thumbnail 320x "$out/$3.png" && echo "$out/$3.png"]]
local preview = nil
local hoverPath = nil
local pvGen = 0
local pvBusy = false

local render

local function showPreview(p)
  if pvBusy then
    return
  end
  pvBusy = true
  pvGen += 1
  noctalia.runAsync({ "sh", "-c", THUMB_CMD, "sh", p, THUMBS, tostring(pvGen) }, function(r)
    pvBusy = false
    local f = noctalia.string.trim(r.stdout or "")
    preview = r.exitCode == 0 and f ~= "" and f or nil
    render()
  end)
end

local function openFile()
  return noctalia.pluginDataDir() .. "/transition-open"
end

local function loadTransition()
  tr.open = noctalia.fileExists(openFile())
  dirs.get("transition", function(v)
    tr.effects = {}
    for e in string.gmatch(v or "", "'(%w+)'") do
      tr.effects[e] = true
    end
    render()
  end)
  dirs.get("transition_duration", function(v) tr.duration = tonumber(v) or tr.duration; render() end)
  dirs.get("edge_smoothness", function(v) tr.smooth = tonumber(v) or tr.smooth; render() end)
  dirs.get("transition_on_startup", function(v) tr.startup = v == "true"; render() end)
  dirs.get("sync_transitions", function(v) tr.sync = v == "true"; render() end)
end

local function toggleTransition()
  tr.open = not tr.open
  noctalia.mkdirAll(noctalia.pluginDataDir())
  if tr.open then
    noctalia.writeFile(openFile(), "1\n")
  else
    noctalia.removeFile(openFile())
  end
  render()
end

local function setTr(key, value, apply)
  dirs.set(key, value, function(ok)
    if ok then
      apply()
      err = nil
    else
      err = "Could not change the transition"
    end
    render()
  end)
end

local function toggleEffect(e)
  local list, n = {}, 0
  for _, x in ipairs(EFFECTS) do
    local on = tr.effects[x]
    if x == e then
      on = not on
    end
    if on then
      table.insert(list, "'" .. x .. "'")
      n += 1
    end
  end
  if n == 0 then
    err = "Keep at least one effect"
    render()
    return
  end
  setTr("transition", "[ " .. table.concat(list, ", ") .. " ]", function() tr.effects[e] = not tr.effects[e] or nil end)
end

local function transitionCard()
  local head = ui.row({ gap = 8, align = "center" }, {
    ui.label({ text = "Transition", flexGrow = 1 }),
    ui.button({ key = "trtoggle", glyph = tr.open and "chevron-up" or "chevron-down", variant = "ghost", controlSize = "sm", tooltip = tr.open and "Hide" or "Show", onClick = toggleTransition }),
  })
  if not tr.open then
    return ui.column(card("transition"), { head })
  end
  local chips, rows = {}, {}
  for _, e in ipairs(EFFECTS) do
    local on = tr.effects[e] == true
    table.insert(chips, ui.button({ key = "fx" .. e .. (on and "1" or "0"), text = e, glyph = on and "check" or nil, variant = on and "primary" or "ghost", controlSize = "sm", onClick = function() toggleEffect(e) end }))
  end
  for i = 1, #chips, 4 do
    table.insert(rows, ui.row({ key = "fxr" .. i, gap = 6 }, { chips[i], chips[i + 1], chips[i + 2], chips[i + 3] }))
  end
  return ui.column(card("transition"), {
    head,
    ui.label({ text = "Effects (one is picked at random per change)", color = "on_surface_variant", fontSize = 12 }),
    ui.column({ gap = 6 }, rows),
    ui.row({ gap = 8, align = "center" }, {
      ui.label({ text = "Duration", color = "on_surface_variant", width = 70 }),
      ui.slider({ key = "trdur", min = 200, max = 5000, step = 100, value = tr.duration, controlSize = "sm", flexGrow = 1,
        onChange = function(v) tr.duration = tonumber(v) or tr.duration; render() end,
        onDragEnd = function() setTr("transition_duration", tostring(tr.duration), function() end) end }),
      ui.label({ text = tostring(math.floor(tr.duration)) .. " ms", width = 60 }),
    }),
    ui.row({ gap = 8, align = "center" }, {
      ui.label({ text = "Smoothness", color = "on_surface_variant", width = 70 }),
      ui.slider({ key = "trsm", min = 0, max = 1, step = 0.05, value = tr.smooth, controlSize = "sm", flexGrow = 1,
        onChange = function(v) tr.smooth = tonumber(v) or tr.smooth; render() end,
        onDragEnd = function() setTr("edge_smoothness", string.format("%.2f", tr.smooth), function() end) end }),
      ui.label({ text = string.format("%.2f", tr.smooth), width = 60 }),
    }),
    ui.row({ gap = 8, align = "center" }, {
      ui.label({ text = "Animate on startup", flexGrow = 1 }),
      ui.toggle({ key = "trstart", checked = tr.startup, onChange = function(v)
        local want = v == true or v == "true"
        setTr("transition_on_startup", want and "true" or "false", function() tr.startup = want end)
      end }),
    }),
    ui.row({ gap = 8, align = "center" }, {
      ui.label({ text = "Same effect on all monitors", flexGrow = 1 }),
      ui.toggle({ key = "trsync", checked = tr.sync, onChange = function(v)
        local want = v == true or v == "true"
        setTr("sync_transitions", want and "true" or "false", function() tr.sync = want end)
      end }),
    }),
  })
end

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

local function setAuto(key, value, apply)
  dirs.setAuto(key, value, function(ok)
    if ok then
      apply()
      err = nil
      note = nil
    else
      err = "Could not change the slideshow"
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
  local seen = {}
  for _, p in ipairs(items) do
    seen[dirs.name(p)] = (seen[dirs.name(p)] or 0) + 1
  end
  for i, p in ipairs(items) do
    local label = dirs.name(p)
    if seen[label] > 1 then
      label = (string.match(p, "([^/]+)/[^/]+/*$") or "") .. "/" .. label
    end
    kbd.stop("p" .. i, i, 1, function() pick(p) end)
    kbd.stop("d" .. i, i, 2, function() remove(i) end)
    table.insert(rows, ui.row({ key = "r" .. i, gap = 6, align = "center", padding = 4, onHover = function(state)
      if state == "true" then
        hoverPath = p
        showPreview(p)
      end
    end }, {
      ui.label({ text = label, flexGrow = 1, maxLines = 1, color = p == current and "primary" or "on_surface" }),
      ui.button({ key = "p" .. i, glyph = p == current and "circle-check" or "circle", variant = p == current and "primary" or "ghost", controlSize = "sm", selected = kbd.sel("p" .. i), tooltip = "Select as wallpaper folder", onClick = function() pick(p) end }),
      ui.button({ key = "d" .. i, glyph = "trash", selected = kbd.sel("d" .. i), text = armed == i and "Click again" or nil, variant = armed == i and "destructive" or "ghost", controlSize = "sm", tooltip = "Remove from list", onClick = function() remove(i) end }),
    }))
  end
  if #rows == 0 then
    table.insert(rows, ui.label({ text = "No saved folders", color = "on_surface_variant" }))
  end
  panel.render(ui.column({ gap = 10, padding = 12 }, {
    ui.row({ gap = 8, align = "center" }, {
      logo(),
      ui.label({ text = "Wallpaper folders" }),
      ui.label({ text = hotkey("mabox/wallpaper-dirs:dirs"), color = "outline_variant", flexGrow = 1 }),
      ui.button({ key = "add", glyph = "folder-open", text = "Add folder", variant = "ghost", controlSize = "sm", selected = kbd.sel("add"), onClick = addFolder }),
    }),
    transitionCard(),
    ui.column(card("slideshow"), {
      ui.row({ gap = 8, align = "center" }, {
        ui.label({ text = "Slideshow" }),
        ui.label({ text = hotkey("mb-slideshow"), color = "outline_variant" }),
        ui.toggle({ key = "auto", checked = auto, onChange = function(v)
          local want = v == true or v == "true"
          setAuto("enabled", want and "true" or "false", function() auto = want end)
        end }),
        ui.box({ flexGrow = 1 }),
        ui.button({ key = "random", text = "Random", variant = order == "random" and "primary" or "ghost", controlSize = "sm", onClick = function()
          setAuto("order", '"random"', function() order = "random" end)
        end }),
        ui.button({ key = "alpha", text = "Alphabetical", variant = order == "alphabetical" and "primary" or "ghost", controlSize = "sm", onClick = function()
          setAuto("order", '"alphabetical"', function() order = "alphabetical" end)
        end }),
      }),
      ui.row({ gap = 6, align = "center" }, {
        ui.label({ text = "Slideshow every", color = "on_surface_variant" }),
        ui.input({ key = "mins" .. tostring(minutes), value = draft or (minutes and tostring(minutes)) or "", width = 64, controlSize = "sm", frameVisible = true, tooltip = "Minutes between wallpapers", onChange = function(t) draft = t end, onSubmit = setMinutes }),
        ui.label({ text = "min", color = "on_surface_variant" }),
        ui.button({ key = "savemins", glyph = "device-floppy", text = "Save", variant = "ghost", controlSize = "sm", onClick = setMinutes }),
      }),
    }),
    err and ui.label({ text = err, color = "error" }) or note and ui.label({ text = note, color = "primary" }) or ui.box({ height = 0 }),
    ui.column(card("folders"), {
      ui.column({ key = "listbox", height = 300 }, {
        ui.scroll({ key = "list", gap = 0, flexGrow = 1, revealKey = kbd.reveal() }, rows),
      }),
      ui.label({ text = hoverPath or "", fontSize = 12, color = "on_surface_variant", maxLines = 2 }),
      preview and ui.image({ path = preview, width = 300, height = 170, fit = "contain", radius = 6 }) or ui.box({ height = 0 }),
    }),
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
  auto = false
  order = nil
  items = dirs.load()
  loadTransition()
  err = nil
  note = nil
  armed = nil
  render()
  dirs.getAuto("enabled", function(v)
    auto = v == "true"
    render()
  end)
  dirs.getAuto("order", function(v)
    order = v
    render()
  end)
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
