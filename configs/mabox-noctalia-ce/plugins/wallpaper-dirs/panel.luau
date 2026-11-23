--!nonstrict
-- Saved wallpaper folders. Click one to make it the wallpaper directory.

local kbd = require("./lib/kbd.luau")
local dirs = require("./lib/dirs.luau")
local favs = require("./lib/favs.luau")
local logo = require("./lib/celogo.luau")
local hotkey = require("./lib/hotkey.luau")

local function card(key)
  return { key = key, fill = "surface_variant", radius = 10, padding = 12, gap = 10, border = "primary", borderWidth = 1 }
end

local items = {}
local current = ""
local revealCurrent = true
local err = nil
local note = nil
local armed = nil
local minutes = nil
local draft = nil
local auto = false
local order = nil
local favList = {}
local closed = {} -- folded cards
local favNow = "" -- wallpaper on screen
local favArmed = nil

local EFFECTS = { "crt", "diamond", "disc", "fade", "golden", "honeycomb", "melt", "pixel", "stripes", "vortex", "wipe", "zoom" }
local tr = { open = false, effects = {}, duration = 1500, smooth = 0.3, startup = false, sync = false }

local THUMBS = (noctalia.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/mb-wallpaper-dirs-thumbs"
-- One random image of the folder as a 320 px png; a new file name per hover, because ui.image caches by path.
local THUMB_CMD = [[d=$1; out=$2; mkdir -p "$out" || exit 1
if [ -f "$d" ]; then f=$d; else f=$(find "$d" -maxdepth 2 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.avif' \) 2>/dev/null | shuf -n1); fi
[ -n "$f" ] || exit 1
magick "$f[0]" -thumbnail 320x "$out/$3.png" || exit 1
find "$out" -name '*.png' ! -name "$3.png" -delete
echo "$out/$3.png"]]
local preview = nil
local hoverPath = nil
local hoverCard = "folders" -- card that shows the preview
local pvGen = 0
local pvBusy = false

local render

local pvNext = nil

local function showPreview(p)
  if pvBusy then
    pvNext = p
    return
  end
  pvBusy = true
  pvGen += 1
  noctalia.runAsync({ "sh", "-c", THUMB_CMD, "sh", p, THUMBS, tostring(pvGen) }, function(r)
    pvBusy = false
    local f = noctalia.string.trim(r.stdout or "")
    preview = r.exitCode == 0 and f ~= "" and f or nil
    render()
    local nxt = pvNext
    pvNext = nil
    if nxt and nxt ~= p then
      showPreview(nxt)
    end
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

-- Card header in the Configs style: one outline button with the chevron and the title; extra controls sit beside it.
local function foldHead(key, title, open, onToggle, extras)
  local row = { ui.button({
    key = "fold-" .. key,
    glyph = open and "chevron-down" or "chevron-right",
    text = title,
    variant = "outline",
    controlSize = "sm",
    contentAlign = "start",
    flexGrow = 1,
    tooltip = open and "Fold the card" or "Show the card",
    onClick = onToggle,
  }) }
  for _, e in ipairs(extras or {}) do
    table.insert(row, e)
  end
  return ui.row({ key = "fh-" .. key, gap = 4, align = "center" }, row)
end

local function transitionCard()
  local head = foldHead("transition", "Transition", tr.open, toggleTransition)
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

local function foldFile()
  return noctalia.pluginDataDir() .. "/folded"
end

local function loadFolds()
  closed = {}
  for l in string.gmatch(noctalia.readFile(foldFile()) or "", "[^\n]+") do
    closed[l] = true
  end
end

local function toggleFold(key)
  closed[key] = (not closed[key]) or nil
  local list = {}
  for k in pairs(closed) do
    table.insert(list, k)
  end
  noctalia.mkdirAll(noctalia.pluginDataDir())
  noctalia.writeFile(foldFile(), table.concat(list, "\n") .. "\n")
  render()
end

local function foldHeadFor(key, title, extras)
  return foldHead(key, title, not closed[key], function() toggleFold(key) end, extras)
end

local function loadFavs()
  favs.list(function(list)
    favList = list
    render()
  end)
  favs.current(function(p)
    favNow = p
    render()
  end)
end

local function isFav(p)
  for _, f in ipairs(favList) do
    if f == p then
      return true
    end
  end
  return false
end

local function addFav()
  -- The wallpaper changes by itself (slideshow): read it again right before saving.
  favs.current(function(p)
    favNow = p
    if p == "" then
      render()
      return
    end
    favs.add(p, function(r)
      err = r.exitCode ~= 0 and "Could not save the favorite" or nil
      loadFavs()
    end)
  end)
end

local function removeFav(p)
  if favArmed ~= p then
    favArmed = p
    render()
    return
  end
  favArmed = nil
  favs.remove(p, function(r)
    err = r.exitCode ~= 0 and "Could not remove the favorite" or nil
    loadFavs()
  end)
end

local function favoritesCard()
  local rows = {}
  for _, p in ipairs(favList) do
    local name = dirs.name(p)
    table.insert(rows, ui.row({ key = "fv" .. p, gap = 6, align = "center", padding = 4, radius = 6, border = p == favNow and "primary" or nil, borderWidth = p == favNow and 1 or 0, onHover = function(state)
      if state == "true" then
        hoverCard, hoverPath = "favs", p
        showPreview(p)
      end
    end }, {
      ui.button({ key = "fvgo" .. p, text = name, variant = "ghost", controlSize = "sm", contentAlign = "start", flexGrow = 1,
        onClick = function() favs.apply(p, function(r) if r.exitCode == 0 then favNow = p end; render() end) end }),
      ui.button({ key = "fvrm" .. p, glyph = "trash", text = favArmed == p and "Click again" or nil, variant = favArmed == p and "destructive" or "ghost", controlSize = "sm", tooltip = "Remove from the favorites", onClick = function() removeFav(p) end }),
    }))
  end
  if #rows == 0 then
    table.insert(rows, ui.label({ text = "No favorites", color = "on_surface_variant" }))
  end
  local head = foldHeadFor("favorites", "Favorites", {
      ui.button({ key = "favadd", glyph = isFav(favNow) and "star-filled" or "star", text = "Add current", variant = isFav(favNow) and "primary" or "ghost", controlSize = "sm", enabled = favNow ~= "" and not isFav(favNow), tooltip = "Add the wallpaper on screen, with the current theme, to the favorites", onClick = addFav }),
    })
  if closed.favorites then
    return ui.column(card("favorites"), { head })
  end
  return ui.column(card("favorites"), {
    head,
    ui.column({ key = "favbox", height = math.min(math.max(#rows, 1), 5) * 38 + 4 }, {
      ui.scroll({ key = "favlist", gap = 0, flexGrow = 1 }, rows),
    }),
    ui.label({ text = hoverCard == "favs" and hoverPath or "", fontSize = 12, color = "on_surface_variant", maxLines = 1 }),
    (hoverCard == "favs" and preview) and ui.image({ path = preview, width = 300, height = 170, fit = "contain", radius = 6 }) or ui.box({ height = 0 }),
  })
end

local function addFolder()
  dirs.browse(current ~= "" and current or noctalia.getenv("HOME"), true)
  panel.close()
end

function render()
  kbd.begin()
  kbd.stop("add", 0, 1, addFolder)
  local rows = {}
  local seen = {}
  for _, p in ipairs(items) do
    seen[dirs.name(p)] = (seen[dirs.name(p)] or 0) + 1
  end
  local currentKey, currentLabel = nil, nil
  for i, p in ipairs(items) do
    local label = dirs.name(p)
    if seen[label] > 1 then
      label = (string.match(p, "([^/]+)/[^/]+/*$") or "") .. "/" .. label
    end
    kbd.stop("p" .. i, i, 1, function() pick(p) end)
    kbd.stop("d" .. i, i, 2, function() remove(i) end)
    if p == current then
      currentKey, currentLabel = "r" .. i .. "c", label
    end
    table.insert(rows, ui.row({ key = "r" .. i .. (p == current and "c" or ""), gap = 6, align = "center", padding = 4, radius = 6, border = p == current and "primary" or nil, borderWidth = p == current and 1 or nil, onHover = function(state)
      if state == "true" then
        hoverCard, hoverPath = "folders", p
        showPreview(p)
      end
    end }, {
      ui.button({ key = "pn" .. i .. (p == current and "c" or ""), text = label, variant = "ghost", controlSize = "sm", contentAlign = "start", flexGrow = 1, onClick = function() pick(p) end }),
      ui.button({ key = "p" .. i .. (p == current and "c" or ""), glyph = p == current and "circle-check" or "circle", variant = p == current and "primary" or "ghost", controlSize = "sm", selected = kbd.sel("p" .. i), tooltip = "Select as wallpaper folder", onClick = function() pick(p) end }),
      ui.button({ key = "d" .. i, glyph = "trash", selected = kbd.sel("d" .. i), text = armed == i and "Click again" or nil, variant = armed == i and "destructive" or "ghost", controlSize = "sm", tooltip = "Remove from list", onClick = function() remove(i) end }),
    }))
  end
  if #rows == 0 then
    table.insert(rows, ui.label({ text = "No saved folders", color = "on_surface_variant" }))
  end
  local reveal = kbd.reveal() or (revealCurrent and currentKey or nil)
  if currentKey then
    revealCurrent = false
  end
  local slideHead = foldHeadFor("slideshow", "Slideshow  " .. hotkey("mb-slideshow"), {
    ui.toggle({ key = "auto", checked = auto, onChange = function(v)
      local want = v == true or v == "true"
      setAuto("enabled", want and "true" or "false", function() auto = want end)
    end }),
  })
  panel.render(ui.column({ gap = 10, padding = 12 }, {
    ui.row({ gap = 8, align = "center" }, {
      logo(),
      ui.label({ text = "Wallpaper folders" }),
      ui.label({ text = hotkey("mabox/wallpaper-dirs:dirs"), color = "outline_variant", flexGrow = 1 }),
      ui.button({ key = "recolor", glyph = "wand", variant = "ghost", controlSize = "sm", tooltip = "Recolor or generate wallpapers",
        onClick = function() noctalia.runAsync({ "setsid", "-f", "sh", "-c", "noctalia msg panel-close; sleep 0.2; noctalia msg panel-open mabox/recolor:main" }) end }),
      ui.button({ key = "add", glyph = "folder-open", text = "Add folder", variant = "ghost", controlSize = "sm", selected = kbd.sel("add"), onClick = addFolder }),
    }),
    ui.column(card("inuse"), closed.inuse and {
      foldHeadFor("inuse", "Folder in use: " .. (current == "" and "unknown" or dirs.name(current))),
    } or {
      foldHeadFor("inuse", "Wallpaper folder in use"),
      ui.label({ text = current == "" and "unknown" or dirs.name(current), fontSize = 18, fontWeight = "bold", color = "primary", maxLines = 1 }),
      ui.label({ text = current, fontSize = 11, color = "on_surface_variant", maxLines = 2 }),
    }),
    transitionCard(),
    ui.column(card("slideshow"), closed.slideshow and { slideHead } or {
      slideHead,
      ui.row({ gap = 6, align = "center" }, {
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
    favoritesCard(),
    err and ui.label({ text = err, color = "error" }) or note and ui.label({ text = note, color = "primary" }) or ui.box({ height = 0 }),
    ui.column(card("folders"), closed.folders and {
      foldHeadFor("folders", "Wallpaper folders"),
    } or {
      foldHeadFor("folders", "Wallpaper folders"),
      current == "" and ui.box({ height = 0 }) or ui.label({ text = currentLabel and ("In use: " .. currentLabel) or "In use: a folder that is not in this list", color = "primary", fontSize = 12, maxLines = 1 }),
      ui.column({ key = "listbox", height = 220 }, {
        ui.scroll({ key = "list", gap = 0, flexGrow = 1, revealKey = reveal }, rows),
      }),
      ui.label({ text = hoverCard == "folders" and hoverPath or "", fontSize = 12, color = "on_surface_variant", maxLines = 1 }),
      (hoverCard == "folders" and preview) and ui.image({ path = preview, width = 300, height = 170, fit = "contain", radius = 6 }) or ui.box({ height = 0 }),
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
  revealCurrent = true
  current = dirs.currentSync()
  kbd.clear()
  draft = nil
  auto = false
  order = nil
  items = dirs.load()
  minutes = dirs.intervalSync()
  loadTransition()
  favArmed = nil
  loadFolds()
  loadFavs()
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
    minutes = m or minutes
    render()
  end)
  current = dirs.currentSync()
  dirs.current(function(p)
    if p == "" then
      p = current
    end
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
