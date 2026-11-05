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

-- One thumbnail per wallpaper path, cached by thumbName.
local render

local function makeThumb(path, out)
  if busy[out] or failed[out] then
    return
  end
  busy[out] = true
  noctalia.mkdirAll(thumbDir)
  noctalia.runAsync({
    "magick", path, "-thumbnail", SIZE .. "x" .. SIZE,
    "-bordercolor", "snow", "-background", "gray20", "+polaroid", out,
  }, function(r)
    busy[out] = nil
    if r.exitCode ~= 0 then
      failed[out] = true
    end
    render()
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

render = function()
  local count = math.max(1, math.min(8, tonumber(noctalia.getConfig("count")) or 3))
  local items = {}
  for i = 1, math.min(count, #history) do
    local path = history[i]
    local out = thumbDir .. "/" .. thumbName(path)
    if noctalia.fileExists(out) then
      table.insert(items, ui.image({ path = out, width = SIZE + 30, height = SIZE + 30, fit = "contain" }))
    else
      makeThumb(path, out)
    end
  end
  desktopWidget.render(ui.column({ gap = 0, padding = 4 }, items))
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
