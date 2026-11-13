--!nonstrict
-- Polaroids desktop widget: the previous wallpapers, or random ones from the wallpaper folder, as polaroid thumbnails.
-- History is recorded by polling `noctalia msg wallpaper-get` while the widget is placed.

local TICK_MS = 5000
local KEEP = 20
local SIZE = 170
local PAPER = "#f4f1ea"

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
  return string.format("%08x-%d-q.png", h, #path)
end

local render
local randoms = {}
local randomMode = false
local shuffleGen = 0
local shuffledCount = 0

local function wantRandom()
  return noctalia.getConfig("random") == true
end

local function wantCount()
  return math.max(1, math.min(8, tonumber(noctalia.getConfig("count")) or 3))
end

-- Random pictures from the top of the wallpaper folder; drawn again when the wallpaper changes.
local SHUFFLE = [[d=$(noctalia msg config-get wallpaper.directory | tr -d "'")
find "$d" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.avif' \) | shuf -n "$1"]]

local function shuffle()
  shuffleGen = shuffleGen + 1
  local gen = shuffleGen
  shuffledCount = wantCount()
  noctalia.runAsync({ "sh", "-c", SHUFFLE, "sh", tostring(shuffledCount) }, function(r)
    if gen ~= shuffleGen then
      return -- a newer shuffle is running
    end
    local old = randoms
    randoms = {}
    local keep = {}
    for line in string.gmatch(r.stdout or "", "[^\n]+") do
      table.insert(randoms, line)
      keep[line] = true
    end
    for _, p in ipairs(history) do
      keep[p] = true
    end
    -- thumbnails of pictures that left the pile; history ones stay
    for _, p in ipairs(old) do
      if not keep[p] then
        noctalia.removeFile(thumbDir .. "/" .. thumbName(p))
      end
    end
    render()
  end)
end

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
  -- square photo in an off-white frame with a deeper bottom edge; tilt and shadow come with the pile
  noctalia.runAsync({
    "magick", path .. "[0]", "-thumbnail", SIZE .. "x" .. SIZE .. "^", "-gravity", "center", "-extent", SIZE .. "x" .. SIZE,
    "-bordercolor", PAPER, "-border", "9", "-gravity", "south", "-background", PAPER, "-splice", "0x30",
    out,
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
    if randomMode then
      shuffle()
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

-- The thumbnails are composed into one pile image: a loose cluster, one polaroid lying apart from it, one
-- turned about upside down, the rest tilted a little. Layout and angles are drawn again for every new pile.
-- Room around every centre for a tilted polaroid with its shadow: at most 30 degrees off square is about
-- 136 px from the centre, plus the shadow.
local PAD = 155
local STEP_X, STEP_Y = 150, 170
local JITTER = 35
local APART = 260 -- from the cluster's nearest centre to the polaroid lying apart
local APART_DY = 50 -- how far above or below the middle the polaroid lying apart can sit
local pileFile, pileW, pileH = nil, 0, 0
local pileNameFile = dir .. "/pile"
local stalePile = string.match(noctalia.readFile(pileNameFile) or "", "[^\n]+")

local function clusterGrid(n)
  local m = n - 1 -- one lies apart
  local cols = math.max(1, math.ceil(math.sqrt(m)))
  return cols, math.max(1, math.ceil(m / cols))
end

local function pileSize(n)
  if n == 1 then
    return 2 * PAD, 2 * PAD
  end
  local cols, rows = clusterGrid(n)
  local reach = math.max(JITTER, APART_DY) -- how far a centre can stray vertically from the middle row
  return (cols - 1) * STEP_X + 2 * JITTER + APART + 2 * PAD, (rows - 1) * STEP_Y + 2 * reach + 2 * PAD
end

local function buildPile(list, out)
  if busy[out] then
    return
  end
  busy[out] = true
  local n = #list
  local w, h = pileSize(n)
  local cols, rows = clusterGrid(n)
  local apartLeft = math.random(2) == 1
  local clusterX = PAD + JITTER + ((cols - 1) * STEP_X) / 2 + (apartLeft and APART or 0)
  local apart, upside = math.random(1, n), math.random(1, n)
  local cells = {}
  for k = 0, cols * rows - 1 do
    table.insert(cells, k)
  end
  for k = #cells, 2, -1 do
    local m = math.random(1, k)
    cells[k], cells[m] = cells[m], cells[k]
  end
  local spots = {}
  local used = 0
  for i = 1, n do
    local x, y
    if n == 1 then
      x, y = PAD, PAD
    elseif i == apart then
      x = apartLeft and PAD or (PAD + 2 * JITTER + (cols - 1) * STEP_X + APART)
      y = h / 2 + math.random(-APART_DY, APART_DY)
    else
      used = used + 1
      local cell = cells[used]
      x = clusterX + ((cell % cols) - (cols - 1) / 2) * STEP_X + math.random(-JITTER, JITTER)
      y = h / 2 + ((cell // cols) - (rows - 1) / 2) * STEP_Y + math.random(-JITTER, JITTER)
    end
    local angle = i == upside and (180 + math.random(-30, 30)) or math.random(-18, 18)
    spots[i] = { x = math.floor(x - w / 2), y = math.floor(y - h / 2), angle = angle }
  end
  local args = { "magick", "-size", w .. "x" .. h, "xc:none" }
  -- oldest first so the newest ends up on top
  for i = #list, 1, -1 do
    local sp = spots[i]
    for _, a in ipairs({
      "(", list[i], "-background", "none", "-rotate", tostring(sp.angle),
      "(", "+clone", "-background", "black", "-shadow", "55x5+3+4", ")", "+swap",
      "-background", "none", "-layers", "merge", "+repage", ")",
      "-gravity", "center", "-geometry", string.format("%+d%+d", sp.x, sp.y), "-composite",
    }) do
      table.insert(args, a)
    end
  end
  table.insert(args, out)
  noctalia.runAsync(args, function(r)
    done(out, r)
  end)
end

render = function()
  local count = wantCount()
  local thumbs, pending = {}, false
  -- history[1] is the wallpaper on the desktop now; the pile shows the ones before it
  local list = {}
  if randomMode then
    list = randoms
  else
    for i = 2, math.min(count + 1, #history) do
      table.insert(list, history[i])
    end
  end
  for _, path in ipairs(list) do
    local out = thumbDir .. "/" .. thumbName(path)
    if noctalia.fileExists(out) then
      table.insert(thumbs, out)
    elseif not failed[out] then
      pending = true
      makeThumb(path, out)
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
    table.insert(body, ui.label({ text = randomMode and "No wallpapers found" or "No previous wallpapers yet", fontSize = 10, color = "on_surface_variant" }))
  end
  desktopWidget.render(ui.column({ gap = 0 }, body))
end

function update()
  poll()
end

function onConfigChanged()
  local want = wantRandom()
  local was = randomMode
  randomMode = want
  if want and (not was or shuffledCount ~= wantCount()) then
    shuffle()
  end
  render()
end

noctalia.setUpdateInterval(TICK_MS)
desktopWidget.setWantsSecondTicks(false)
load()
randomMode = wantRandom()
if randomMode then
  shuffle()
end
render()
poll()
