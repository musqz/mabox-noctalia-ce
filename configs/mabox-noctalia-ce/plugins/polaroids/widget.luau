--!nonstrict
-- Polaroids desktop widget: the last wallpapers as polaroid thumbnails.
-- History is recorded by polling `noctalia msg wallpaper-get` while the widget is placed.

local TICK_MS = 5000
local KEEP = 20
local SIZE = 170

local dir = noctalia.pluginDataDir()
local histFile = dir .. "/history"
local thumbDir = dir .. "/thumbs"
local history = {}
local busy = {}
local failed = {}

local function save()
  noctalia.mkdirAll(dir)
  noctalia.writeFile(histFile, table.concat(history, "\n") .. "\n")
end

local function load()
  for line in string.gmatch(noctalia.readFile(histFile) or "", "[^\n]+") do
    table.insert(history, line)
  end
end

local function thumbName(path)
  local h = 5381
  for i = 1, #path do
    h = (h * 33 + string.byte(path, i)) % 4294967296
  end
  return string.format("%08x-%d.png", h, #path)
end

local render

local function done(out, r)
  busy[out] = nil
  -- a zero exit without the file (a format magick cannot read) must not be retried in a loop
  if r.exitCode ~= 0 or not noctalia.fileExists(out) then
    failed[out] = true
  end
  render()
end

-- One thumbnail per wallpaper path, cached by thumbName. "[0]" picks the first frame of an animation and
-- keeps a name with brackets or a colon from being read as a magick spec.
local function makeThumb(path, out)
  if busy[out] or failed[out] then
    return
  end
  busy[out] = true
  noctalia.mkdirAll(thumbDir)
  noctalia.runAsync({
    "magick", path .. "[0]", "-thumbnail", SIZE .. "x" .. SIZE,
    "-bordercolor", "snow", "-background", "gray20", "+polaroid", out,
  }, function(r)
    done(out, r)
  end)
end

local function poll()
  noctalia.runAsync({ "noctalia", "msg", "wallpaper-get" }, function(r)
    local path = string.match(r.stdout or "", "[^\n]+") or ""
    if r.exitCode ~= 0 or path == "" or path == history[1] then
      return
    end
    for i = #history, 1, -1 do
      if history[i] == path then
        table.remove(history, i)
      end
    end
    table.insert(history, 1, path)
    while #history > KEEP do
      noctalia.removeFile(thumbDir .. "/" .. thumbName(table.remove(history)))
    end
    save()
    render()
  end)
end

-- The thumbnails are composed into one pile image: a loose grid with a random shift per cell, so
-- neighbours overlap by at most about a third. Cached per set of thumbnails.
local THUMB_W, THUMB_H = 215, 160
local STEP_X, STEP_Y = 165, 120
local JITTER = 22
local pileFile, pileW, pileH = nil, 0, 0
local pileNameFile = dir .. "/pile"
local stalePile = string.match(noctalia.readFile(pileNameFile) or "", "[^\n]+")

local function pileSize(n)
  local cols = math.ceil(math.sqrt(n))
  local rows = math.ceil(n / cols)
  return (cols - 1) * STEP_X + THUMB_W + 2 * JITTER, (rows - 1) * STEP_Y + THUMB_H + 2 * JITTER, cols
end

local function buildPile(list, out)
  if busy[out] then
    return
  end
  busy[out] = true
  local w, h, cols = pileSize(#list)
  local cells = {}
  for k = 0, #list - 1 do
    table.insert(cells, k)
  end
  for k = #cells, 2, -1 do
    local m = math.random(1, k)
    cells[k], cells[m] = cells[m], cells[k]
  end
  local args = { "magick", "-size", w .. "x" .. h, "xc:none" }
  -- oldest first so the newest ends up on top
  for i = #list, 1, -1 do
    local cell = cells[i]
    local x = (cell % cols) * STEP_X + JITTER + math.random(-JITTER, JITTER)
    local y = (cell // cols) * STEP_Y + JITTER + math.random(-JITTER, JITTER)
    table.insert(args, list[i])
    table.insert(args, "-geometry")
    table.insert(args, string.format("%+d%+d", x, y))
    table.insert(args, "-composite")
  end
  table.insert(args, out)
  noctalia.runAsync(args, function(r)
    done(out, r)
  end)
end

render = function()
  local count = math.max(1, math.min(8, tonumber(noctalia.getConfig("count")) or 3))
  local thumbs, pending = {}, false
  -- history[1] is the wallpaper on the desktop now; the pile shows the ones before it
  for i = 2, math.min(count + 1, #history) do
    local out = thumbDir .. "/" .. thumbName(history[i])
    if noctalia.fileExists(out) then
      table.insert(thumbs, out)
    elseif not failed[out] then
      pending = true
      makeThumb(history[i], out)
    end
  end
  local body = {}
  -- Wait for every thumbnail before building; keep the old pile meanwhile.
  if #thumbs == 0 and not pending then
    pileFile = nil
  elseif #thumbs > 0 and not pending then
    local pile = thumbDir .. "/pile-" .. thumbName(table.concat(thumbs, "|"))
    if noctalia.fileExists(pile) then
      local old = pileFile or stalePile
      if old and old ~= pile then
        noctalia.removeFile(old)
      end
      stalePile = nil
      if pileFile ~= pile then
        noctalia.mkdirAll(dir)
        noctalia.writeFile(pileNameFile, pile .. "\n")
      end
      pileFile = pile
      pileW, pileH = pileSize(#thumbs)
    elseif not failed[pile] then
      buildPile(thumbs, pile)
    end
  end
  if pileFile then
    table.insert(body, ui.image({ path = pileFile, width = pileW, height = pileH, fit = "contain" }))
  elseif not pending then
    table.insert(body, ui.label({ text = "No previous wallpapers yet", fontSize = 10, color = "on_surface_variant" }))
  end
  desktopWidget.render(ui.column({ gap = 0 }, body))
end

function update()
  poll()
end

function onConfigChanged()
  render()
end

noctalia.setUpdateInterval(TICK_MS)
desktopWidget.setWantsSecondTicks(false)
load()
render()
poll()
