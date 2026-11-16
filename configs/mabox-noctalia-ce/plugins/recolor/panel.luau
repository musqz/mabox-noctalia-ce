--!nonstrict
-- Recolor: front end for mb-recolor (image or folder to a palette).
local logo = require("./lib/celogo.luau")
local hotkey = require("./lib/hotkey.luau")
local switch = require("./lib/switch.luau")

local function card(key)
  return { key = key, fill = "surface_variant", radius = 10, padding = 12, gap = 10, border = "primary", borderWidth = 1 }
end

local palettes = {}
local palette = "nord"
local group = "all"
local mode = "clut"
local blur = 0
local src = ""
local out = ""
local gen = 0
local running = false
local swatches = {}
local off = {}
local colGen = 0
local previews = {}
local pvGen = 0
local pvName = nil
local pvFile = nil
local pvDir = false
local err = nil
local done = nil
local outDir = nil
local prog = nil
local runStart = nil
local render

local function pickFile(name)
  return noctalia.pluginDataDir() .. "/" .. name
end

-- The panel script restarts on every open; the settings live in a file so a running job keeps its path and look.
local function offList()
  local t = {}
  for c in pairs(off) do
    table.insert(t, c)
  end
  table.sort(t)
  return table.concat(t, ",")
end

local function offCount()
  local n = 0
  for _ in pairs(off) do n = n + 1 end
  return n
end

local function saveState()
  noctalia.mkdirAll(noctalia.pluginDataDir())
  noctalia.writeFile(pickFile("state"), string.format("src=%s\nout=%s\npalette=%s\ngroup=%s\nmode=%s\nblur=%d\noff=%s\n", src, out, palette, group, mode, blur, offList()))
end

local function loadState()
  for line in string.gmatch(noctalia.readFile(pickFile("state")) or "", "[^\n]+") do
    local k, v = string.match(line, "^(%a+)=(.*)$")
    if k == "src" then src = v
    elseif k == "out" then out = v
    elseif k == "palette" then palette = v
    elseif k == "group" then group = v
    elseif k == "mode" then mode = v
    elseif k == "blur" then blur = tonumber(v) or 0
    elseif k == "off" then
      off = {}
      for c in string.gmatch(v, "#%x+") do off[c] = true end
    end
  end
end

-- "name: group group ..." per line.
local function loadPalettes()
  noctalia.runAsync({ "mb-recolor", "--list" }, function(r)
    palettes = {}
    for line in string.gmatch((r.stdout or "") .. "\n", "([^\n]*)\n") do
      local name, rest = string.match(line, "^([%w_-]+):%s*(.*)$")
      if name then
        local groups = {}
        for g in string.gmatch(rest, "%S+") do
          table.insert(groups, g)
        end
        table.insert(palettes, { name = name, groups = groups })
      end
    end
    if #palettes == 0 then
      err = "mb-recolor found no palettes"
    else
      local known = false
      for _, p in ipairs(palettes) do
        known = known or p.name == palette
      end
      if not known then
        palette = palettes[1].name
      end
    end
    if mode ~= "clut" and mode ~= "remap" and mode ~= "smooth" and mode ~= "lut" then
      mode = "clut"
    end
    render()
  end)
end

local function expand(t)
  t = noctalia.string.trim(t)
  return (string.gsub(t, "^~/", noctalia.getenv("HOME") .. "/"))
end

local function destDir()
  local dest = expand(out)
  if dest == "" then
    dest = noctalia.getenv("HOME") .. "/Pictures/" .. palette .. "/" .. group
  end
  return dest
end

local function loadColors()
  colGen = colGen + 1
  local mine = colGen
  noctalia.runAsync({ "mb-recolor", "--colors", "-g", group, palette }, function(r)
    if mine ~= colGen then
      return
    end
    swatches = {}
    for c in string.gmatch(r.stdout or "", "#%x+") do
      table.insert(swatches, c)
    end
    render()
  end)
end

-- Three small renders of the first image, one per look, in a fresh folder each time (ui.image caches by path).
local PREVIEW = [[src=$4; dir=0
if [ -d "$src" ]; then
  dir=1
  list=$(find "$src" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.avif' -o -iname '*.bmp' \))
  if [ "$5" != 1 ] && [ -n "$8" ] && [ -f "$8" ] && [ "$(dirname "$8")" = "${src%/}" ]; then src=$8
  elif [ "$5" = 1 ]; then src=$(printf '%s\n' "$list" | shuf -n1); else src=$(printf '%s\n' "$list" | sort | head -n1); fi
fi
[ -f "$src" ] || exit 1
rm -rf "$1"; mkdir -p "$1"
magick "$src" -resize 400x "$1/in.png" || exit 1
for m in clut remap smooth lut; do mb-recolor -m "$m" -b "$6" -g "$3" -x "$7" -o "$1/$m" "$2" "$1/in.png" >/dev/null 2>&1 & done
wait
echo "src=$src"; echo "dir=$dir"
ls "$1"/*/*]]

local function loadPreviews(random)
  local path = expand(src)
  if path == "" then
    previews = {}
    pvName = nil
    pvDir = false
    render()
    return
  end
  pvGen = pvGen + 1
  local mine = pvGen
  local base = noctalia.pluginDataDir() .. "/pv"
  noctalia.runAsync({ "sh", "-c", PREVIEW, "sh", base .. "/" .. mine, palette, group, path, random and "1" or "0", tostring(blur), offList(), pvFile or "" }, function(r)
    if mine ~= pvGen then
      return
    end
    previews = {}
    pvName = nil
    pvDir = false
    for line in string.gmatch(r.stdout or "", "[^\n]+") do
      local file = string.match(line, "^src=(.+)$")
      if file then
        pvFile = file
        pvName = string.match(file, "([^/]+)$")
      elseif line == "dir=1" then
        pvDir = true
      elseif line == "dir=0" then
        pvDir = false
      else
        local m = string.match(line, "/(%a+)/[^/]+$")
        if m then
          previews[m] = line
        end
      end
    end
    noctalia.runAsync({ "sh", "-c", 'for d in "$1"/*; do [ "$d" = "$2" ] || rm -rf "$d"; done', "sh", base, base .. "/" .. mine })
    render()
  end)
end

local function groupsOf(name)
  for _, p in ipairs(palettes) do
    if p.name == name then
      return p.groups
    end
  end
  return { "all" }
end

local function choosePalette(name)
  palette = name
  off = {}
  local ok = false
  for _, g in ipairs(groupsOf(name)) do
    ok = ok or g == group
  end
  if not ok then
    group = "all"
  end
  saveState()
  done = nil
  render()
  loadColors()
  loadPreviews()
end

-- Runs detached (setsid) so the dialog survives the panel closing; the pick goes to a file and the panel reopens.
local BROWSE = [[if [ "$3" != file ]; then
  p=$(yad --file --directory --center --width=1000 --height=650 --title="Recolor: folder" --filename="$1/") || p=
else
  p=$(yad --file --center --width=1000 --height=650 --title="Recolor: image" --filename="$1/" --file-filter="Images|*.png *.jpg *.jpeg *.webp *.avif *.bmp" --file-filter="All|*") || p=
fi
[ -n "$p" ] && readlink -f "$p" > "$2"
noctalia msg panel-close; noctalia msg panel-open mabox/recolor:main]]

-- kind: file or dir (source), out (output folder).
local function browse(kind)
  noctalia.mkdirAll(noctalia.pluginDataDir())
  local start = noctalia.getenv("HOME") .. "/Pictures"
  noctalia.runAsync({ "setsid", "-f", "sh", "-c", BROWSE, "sh", start, pickFile(kind == "out" and "out" or "src"), kind })
end

local function check()
  noctalia.runAsync({ "pgrep", "-f", "mb-recolor-job" }, function(r)
    local now = r.exitCode == 0
    if now ~= running then
      running = now
      outDir = outDir or destDir()
      if running then
        done = done or "Running: a notification follows when it is finished"
      end
      if not running then
        done = "Finished"
      end
      render()
    end
  end)
end

local function stop()
  noctalia.runAsync({ "sh", "-c", 'for p in $(pgrep -f mb-recolor-job); do pkill -s "$p"; done; true' }, function()
    running = false
    done = "Stopped"
    render()
  end)
end

-- Detached (setsid) so a long folder run survives the panel closing; a notification reports the result.
local RUN = [[pd=$8; mkdir -p "$pd"; rm -f "$pd/total" "$pd/start"; log=$pd/out; : > "$log"; err=$(mktemp)
if [ -d "$5" ]; then find "$5" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.avif' -o -iname '*.bmp' \) | wc -l > "$pd/total"; else echo 1 > "$pd/total"; fi
date +%s > "$pd/start"
trap 'rm -f "$log" "$err"; exit 1' TERM
mb-recolor -m "$1" -b "$6" -g "$2" -x "$7" -o "$3" "$4" "$5" > "$log" 2> "$err"
n=$(wc -l < "$log"); f=$(grep -c '^failed' "$err")
if [ "$n" -gt 0 ]; then
  [ "$f" -gt 0 ] && x=" ($f failed)" || x=
  notify-send -a Recolor "Recolor" "$n images written to $3$x"
else
  notify-send -a Recolor -u critical "Recolor failed" "$(tail -n1 "$err")"
fi
rm -f "$log" "$err"]]

-- Adds the output folder to the Wallpaper folders list and switches to it.
local USE = [[d=${XDG_STATE_HOME:-$HOME/.local/state}/noctalia/plugins/data/mabox/wallpaper-dirs
mkdir -p "$d"
grep -qxF -- "$1" "$d/dirs" 2>/dev/null || echo "$1" >> "$d/dirs"
mb-wallpaper-dir "$1"]]

local function progressDir()
  return noctalia.pluginDataDir() .. "/progress"
end

-- Images written so far, out of the total, and the time left from the pace so far.
local function readProgress()
  local pd = progressDir()
  local total = tonumber(noctalia.string.trim(noctalia.readFile(pd .. "/total") or ""))
  local start = tonumber(noctalia.string.trim(noctalia.readFile(pd .. "/start") or ""))
  if not (total and start and total > 0) or (runStart and start < runStart) then
    return
  end
  local count = select(2, string.gsub(noctalia.readFile(pd .. "/out") or "", "\n", ""))
  local left = nil
  if count > 0 then
    left = math.floor((os.time() - start) / count * math.max(0, total - count))
  end
  local changed = not prog or prog.count ~= count or prog.left ~= left
  prog = { count = count, total = total, left = left }
  return changed
end

local function eta(sec)
  if sec < 60 then
    return sec .. " s"
  end
  return math.floor(sec / 60) .. " min " .. sec % 60 .. " s"
end

local function run()
  if running then
    stop()
    return
  end
  local path = expand(src)
  if path == "" then
    err = path == "" and "Pick an image or a folder first" or err
    render()
    return
  end
  err = nil
  done = nil
  local argv = { "setsid", "-f", "sh", "-c", RUN, "mb-recolor-job", mode, group }
  local dest = destDir()
  table.insert(argv, dest)
  table.insert(argv, palette)
  table.insert(argv, path)
  table.insert(argv, tostring(blur))
  table.insert(argv, offList())
  table.insert(argv, progressDir())
  outDir = dest
  prog = nil
  runStart = os.time()
  noctalia.runAsync(argv)
  running = true
  done = "Running: a notification follows when it is finished"
  render()
end

-- While a job runs only Stop works; the rest is inert so inputs cannot change under it.
local function idle(fn)
  return function(...)
    if not running then
      fn(...)
    end
  end
end

local function chip(key, text, on, onClick)
  return ui.button({ key = key, text = text, glyph = on and "check" or nil, variant = on and "primary" or "outline", controlSize = "sm", enabled = not running, onClick = idle(onClick) })
end

function render()
  local pal = {}
  for _, p in ipairs(palettes) do
    table.insert(pal, chip("p" .. p.name, p.name, p.name == palette, function() choosePalette(p.name) end))
  end
  local grp = {}
  for _, g in ipairs(groupsOf(palette)) do
    table.insert(grp, chip("g" .. g, g, g == group, function() group = g; off = {}; saveState(); done = nil; render(); loadColors(); loadPreviews() end))
  end
  -- Five chips per row: the wide panel fits the whole palette list in one line.
  local function chunk(items, prefix)
    local rows = {}
    for i = 1, #items, 5 do
      local cells = {}
      for k = i, math.min(i + 4, #items) do
        table.insert(cells, items[k])
      end
      table.insert(rows, ui.row({ key = prefix .. i, gap = 6 }, cells))
    end
    return rows
  end
  local palRows = chunk(pal, "pr")
  local grpRows = chunk(grp, "gr")

  local swatchBoxes = {}
  for i, c in ipairs(swatches) do
    local skipped = off[c]
    table.insert(swatchBoxes, ui.box({ key = "sw" .. i, fill = c, flexGrow = 1, height = 26, radius = 3, opacity = skipped and 0.2 or 1,
      tooltip = c .. (skipped and " (off)" or ""),
      onClick = idle(function()
        if skipped then
          off[c] = nil
        elseif #swatches - offCount() > 1 then
          off[c] = true
        end
        saveState(); done = nil; render(); loadPreviews()
      end) }))
  end
  if #swatchBoxes == 0 then
    table.insert(swatchBoxes, ui.box({ key = "sw0", height = 26 }))
  end

  local lookCols = {}
  for _, l in ipairs({ { "clut", "Soft" }, { "remap", "Hard" }, { "smooth", "Smooth" }, { "lut", "Blend" } }) do
    local m, label = l[1], l[2]
    local pick = function() mode = m; saveState(); done = nil; render() end
    local thumb = previews[m] and ui.image({ key = "pv" .. m .. pvGen, path = previews[m], width = 240, height = 140, radius = 6, fit = "cover", border = m == mode and "primary" or "on_surface_variant", borderWidth = m == mode and 3 or 1, onClick = idle(pick) })
      or ui.box({ key = "pvb" .. m, fill = "surface", width = 240, height = 140, radius = 6, border = m == mode and "primary" or "on_surface_variant", borderWidth = m == mode and 3 or 1, onClick = idle(pick) })
    table.insert(lookCols, ui.column({ key = "look" .. m, gap = 6, align = "center" }, { thumb, chip(m, label, m == mode, pick) }))
  end

  local srcCard = ui.column(card("src"), {
    ui.label({ text = "Image or folder", fontWeight = "bold" }),
    ui.input({ key = "src" .. gen, value = src, placeholder = "/path/to/image or folder", frameVisible = true, onChange = idle(function(t) src = t; pvFile = nil; saveState() end), onSubmit = idle(function() loadPreviews() end) }),
    ui.row({ gap = 6 }, {
      ui.button({ key = "file", glyph = "photo", text = "Image", variant = "outline", controlSize = "sm", enabled = not running, onClick = idle(function() browse("file") end) }),
      ui.button({ key = "dir", glyph = "folder-open", text = "Folder", variant = "outline", controlSize = "sm", enabled = not running, onClick = idle(function() browse("dir") end) }),
    }),
  })
  local outCard = ui.column(card("out"), {
    ui.label({ text = "Output folder", fontWeight = "bold" }),
    ui.input({ key = "out" .. gen, value = out, placeholder = "~/Pictures/" .. palette .. "/" .. group, frameVisible = true, onChange = idle(function(t) out = t; saveState() end), onSubmit = idle(run) }),
    ui.row({ gap = 6 }, {
      ui.button({ key = "outdir", glyph = "folder-open", text = "Folder", variant = "outline", controlSize = "sm", enabled = not running, onClick = idle(function() browse("out") end) }),
      ui.button({ key = "outclear", glyph = "x", text = "Default", variant = "ghost", controlSize = "sm", enabled = not running, onClick = idle(function() out = ""; saveState(); render() end) }),
    }),
  })
  local palCard = ui.column(card("pal"), {
    ui.label({ text = "Palette", fontWeight = "bold" }),
    ui.column({ gap = 6 }, palRows),
    ui.label({ text = "Colors", fontWeight = "bold" }),
    ui.column({ gap = 6 }, grpRows),
    ui.row({ key = "sw", gap = 2 }, swatchBoxes),
  })
  local lookCard = ui.column(card("mode"), {
    ui.row({ gap = 8, align = "center" }, {
      ui.label({ text = "Look", fontWeight = "bold" }),
      ui.label({ text = pvName or "", color = "outline_variant", fontSize = 11, maxLines = 1, flexGrow = 1 }),
      pvDir and ui.button({ key = "shuffle", glyph = "arrows-shuffle", text = "Another", variant = "outline", controlSize = "sm", tooltip = "Preview another image from the folder", enabled = not running, onClick = idle(function() loadPreviews(true) end) }) or ui.box({ height = 0 }),
    }),
    ui.row({ key = "look-top", gap = 12 }, { lookCols[1], lookCols[2] }),
    ui.row({ key = "look-bottom", gap = 12 }, { lookCols[3], lookCols[4] }),
    ui.label({ text = mode == "clut" and "Brightness mapped over the palette; keeps gradients and detail."
      or mode == "remap" and "Every pixel becomes the nearest palette color; flat areas."
      or mode == "lut" and "Colors blend smoothly between palette colors; keeps detail."
      or "Flat areas of palette colors with clean edges.", color = "on_surface_variant", fontSize = 11 }),
    ui.row({ gap = 8, align = "center" }, {
      ui.label({ text = "Blur", fontWeight = "bold", width = 44 }),
      ui.slider({ key = "blur", min = 0, max = 20, step = 1, value = blur, controlSize = "sm", flexGrow = 1,
        onChange = idle(function(v) blur = math.floor(tonumber(v) or blur); saveState(); done = nil; render() end),
        onDragEnd = idle(function() loadPreviews() end) }),
      ui.label({ text = blur == 0 and "off" or string.format("%.1f%%", blur / 10), width = 40 }),
    }),
    ui.label({ text = "Softens the source before the colors are mapped; the size follows the image width.", color = "on_surface_variant", fontSize = 11 }),
  })

  panel.render(ui.column({ gap = 10, padding = 12 }, {
    ui.row({ gap = 8, align = "center" }, {
      logo(),
      ui.label({ text = "Recolor" }),
      ui.label({ text = hotkey("mabox/recolor:main"), color = "outline_variant", flexGrow = 1 }),
      switch("main"),
      ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "Close", onClick = function() panel.close() end }),
    }),
    ui.row({ key = "columns", gap = 10, align = "start" }, {
      ui.column({ key = "col-left", gap = 10, flexGrow = 1, minWidth = 380 }, { srcCard, outCard, palCard }),
      ui.column({ key = "col-right", gap = 10, flexGrow = 1, minWidth = 380 }, { lookCard }),
    }),
    ui.row({ gap = 8, align = "center" }, {
      ui.button({ key = "run", glyph = running and "player-stop" or "wand", text = running and "Stop" or "Recolor", variant = running and "destructive" or "primary", onClick = run }),
      done and not running and ui.button({ key = "open", glyph = "folder-open", text = "Open folder", variant = "outline", onClick = function()
        if outDir then
          noctalia.runAsync({ "xdg-open", outDir })
          panel.close()
        end
      end }) or ui.box({ height = 0 }),
      done and not running and ui.button({ key = "use", glyph = "photo-up", text = "Use as wallpapers", variant = "outline", tooltip = "Add the output folder to the wallpaper folders and start it", onClick = function()
        if outDir then
          noctalia.runAsync({ "sh", "-c", USE, "sh", outDir })
          panel.close()
        end
      end }) or ui.box({ height = 0 }),
    }),
    running and prog and ui.column({ key = "prog", gap = 4 }, {
      ui.progress({ progress = prog.count / prog.total, fill = "primary", track = "surface_variant", height = 8, radius = 4 }),
      ui.label({ text = prog.count .. " of " .. prog.total .. " images" .. (prog.left and ("  -  about " .. eta(prog.left) .. " left") or ""), color = "on_surface_variant", fontSize = 11 }),
    }) or nil,
    err and ui.label({ text = err, color = "error" }) or done and ui.label({ text = done .. " in " .. (outDir or ""), color = "primary", maxLines = 2 }) or ui.box({ height = 0 }),
  }))
end

function onOpen()
  err = nil
  done = nil
  loadState()
  for name, set in pairs({ src = function(v) src = v end, out = function(v) out = v end }) do
    local picked = noctalia.readFile(pickFile(name))
    if picked and picked ~= "" then
      if not running then
        set(noctalia.string.trim(picked))
        pvFile = nil
        gen = gen + 1
      end
      noctalia.writeFile(pickFile(name), "")
    end
  end
  saveState()
  render()
  loadPalettes()
  loadColors()
  loadPreviews()
  check()
  panel.setWantsSecondTicks(true)
end

function update()
  if running then
    check()
    if readProgress() then
      render()
    end
  end
end
