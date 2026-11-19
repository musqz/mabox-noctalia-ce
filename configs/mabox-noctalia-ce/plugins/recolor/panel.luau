--!nonstrict
-- Recolor: front end for mb-recolor (image or folder to a palette).
local logo = require("./lib/celogo.luau")
local hotkey = require("./lib/hotkey.luau")
local switch = require("./lib/switch.luau")

local function card(key)
  return { key = key, fill = "surface_variant", radius = 10, padding = 12, gap = 10, border = "primary", borderWidth = 1 }
end

local palettes = {}
local mineNames = {} -- palettes saved by the user, shown in a fold of their own
local mineOpen = false
local pathsOpen = true
local palette = "nord"
local group = "all"
local mode = "clut"
local blur = 0
local src = ""
local out = ""
local gen = 0
local running = false
local swatches = {}
local work, dis = {}, {} -- the colors of the palette group as a working copy, and the indexes switched off
local sel, hexDraft = nil, nil
local edited = false
local resume = false
local delAsk, delAt = nil, 0 -- palette waiting for a delete confirmation, and when it lapses
local saveName = ""
local note = nil
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
local render, loadPreviews

local function pickFile(name)
  return noctalia.pluginDataDir() .. "/" .. name
end

-- The panel script restarts on every open; the settings live in a file so a running job keeps its path and look.
local function offList()
  -- A changed copy is written with only the colors that are on.
  if edited then
    return ""
  end
  local t = {}
  for i, c in ipairs(work) do
    if dis[i] then
      table.insert(t, c)
    end
  end
  return table.concat(t, ",")
end

local function disIdx()
  local t = {}
  for i in pairs(dis) do
    table.insert(t, tostring(i))
  end
  table.sort(t)
  return table.concat(t, ",")
end

-- mb-recolor finds a changed copy as a palette of its own; the dot keeps it out of the palette lists.
local function writeWork()
  if not edited then
    return
  end
  local dir = noctalia.getenv("HOME") .. "/.local/share/mabox-noctalia-ce/palettes"
  noctalia.mkdirAll(dir)
  local on = {}
  for i, c in ipairs(work) do
    if not dis[i] then
      table.insert(on, c)
    end
  end
  noctalia.writeFile(dir .. "/.work.pal", "all: " .. table.concat(on, " ") .. "\n")
end

local function effPalette()
  return edited and ".work" or palette
end

local function effGroup()
  return edited and "all" or group
end

local function saveState()
  noctalia.mkdirAll(noctalia.pluginDataDir())
  noctalia.writeFile(pickFile("state"), string.format("src=%s\nout=%s\npalette=%s\ngroup=%s\nmode=%s\nblur=%d\nwork=%s\ndis=%s\nedited=%d\nsel=%s\nmineopen=%d\nresume=%d\npathsopen=%d\n", src, out, palette, group, mode, blur, table.concat(work, ","), disIdx(), edited and 1 or 0, sel and tostring(sel) or "", mineOpen and 1 or 0, resume and 1 or 0, pathsOpen and 1 or 0))
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
    elseif k == "mineopen" then mineOpen = v == "1"
    elseif k == "resume" then resume = v == "1"
    elseif k == "pathsopen" then pathsOpen = v == "1"
    elseif k == "work" then
      work = {}
      for c in string.gmatch(v, "#%x+") do table.insert(work, c) end
    elseif k == "dis" then
      dis = {}
      for n in string.gmatch(v, "%d+") do dis[tonumber(n)] = true end
    elseif k == "edited" then edited = v == "1"
    elseif k == "sel" then sel = tonumber(v)
    end
  end
end

-- "name: group group ..." per line.
local function loadPalettes()
  noctalia.runAsync({ "sh", "-c", 'for f in "$HOME"/.local/share/mabox-noctalia-ce/palettes/*.pal; do [ -f "$f" ] && basename "$f" .pal; done' }, function(r)
    mineNames = {}
    for l in string.gmatch(r.stdout or "", "[^\n]+") do
      mineNames[l] = true
    end
    render()
  end)
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
    dest = noctalia.getenv("HOME") .. "/Pictures/" .. (edited and "custom/all" or (palette .. "/" .. group))
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
    -- a fresh copy of the palette unless the copy was changed by hand
    if not edited or #work == 0 then
      work = {}
      for _, c in ipairs(swatches) do
        table.insert(work, c)
      end
      dis = {}
      sel = nil
    end
    saveState()
    render()
    loadPreviews()
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

function loadPreviews(random)
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
  writeWork()
  local base = noctalia.pluginDataDir() .. "/pv"
  noctalia.runAsync({ "sh", "-c", PREVIEW, "sh", base .. "/" .. mine, effPalette(), effGroup(), path, random and "1" or "0", tostring(blur), offList(), pvFile or "" }, function(r)
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
  edited = false
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
[ "$9" = 1 ] && rs=-r || rs=
mb-recolor $rs -m "$1" -b "$6" -g "$2" -x "$7" -o "$3" "$4" "$5" > "$log" 2> "$err"
n=$(grep -vc '^skip: ' "$log"); f=$(grep -c '^failed' "$err")
if [ "$n" -gt 0 ]; then
  [ "$f" -gt 0 ] && x=" ($f failed)" || x=
  notify-send -a Recolor "Recolor" "$n images written to $3$x"
elif [ -s "$log" ] && [ "$f" -eq 0 ]; then
  notify-send -a Recolor "Recolor" "Nothing left to do in $3"
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

-- Images done so far (skipped ones included), out of the total; the time left follows the pace of the written ones.
local function readProgress(count, skipped)
  local pd = progressDir()
  local total = tonumber(noctalia.string.trim(noctalia.readFile(pd .. "/total") or ""))
  local start = tonumber(noctalia.string.trim(noctalia.readFile(pd .. "/start") or ""))
  if not (total and start and total > 0) or (runStart and start < runStart) then
    return
  end
  local left = nil
  local written = count - skipped
  if written > 0 then
    left = math.floor((os.time() - start) / written * math.max(0, total - count))
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

local MAXC = 64

local function changed()
  edited = true
  note = nil
  done = nil
  saveState()
  render()
  loadPreviews()
end

local function addColor(c)
  if #work >= MAXC then
    note = "At most " .. MAXC .. " colors"
    render()
    return
  end
  table.insert(work, string.upper(c))
  sel = #work
  changed()
end

local function setColorAt(i, c)
  work[i] = string.upper(c)
  hexDraft = nil
  changed()
end

local function removeColor(i)
  local on = 0
  for k = 1, #work do
    if k ~= i and not dis[k] then on = on + 1 end
  end
  if on < 1 then
    note = "Keep at least one color on"
    render()
    return
  end
  table.remove(work, i)
  local d = {}
  for k in pairs(dis) do
    if k < i then
      d[k] = true
    elseif k > i then
      d[k - 1] = true
    end
  end
  dis = d
  sel = nil
  changed()
end

-- At least one color stays switched on.
local function toggleColor(i)
  if dis[i] then
    dis[i] = nil
  else
    local on = 0
    for k = 1, #work do
      if not dis[k] then on = on + 1 end
    end
    if on <= 1 then
      note = "Keep at least one color on"
      render()
      return
    end
    dis[i] = true
  end
  -- Switching a color off leaves the palette itself in use (-x); only a changed color makes a copy.
  note = nil
  done = nil
  saveState()
  render()
  loadPreviews()
end

-- Back to the colors of the chosen palette.
local function resetColors()
  edited = false
  note = nil
  loadColors()
end

-- The panel closes while a picker is open (the eyedropper must see the screen, the chooser is a window of its own)
-- and opens again with the result in a file; onOpen applies it.
local PICK = [[noctalia msg panel-close
sleep 0.3
if [ "$3" = screen ]; then c=$(mb-colorpick); else c=$(yad --color --center --title="Recolor color" --init-color="$4"); fi
[ -n "$c" ] && printf "%s" "$c" > "$1"
noctalia msg panel-open mabox/recolor:main]]

-- source: screen (eyedropper) or dialog (color chooser); mode: replace the selected color or add one.
local function pickColor(source, mode)
  local replace = mode == "replace" and sel ~= nil
  noctalia.mkdirAll(noctalia.pluginDataDir())
  noctalia.writeFile(pickFile("colorpick"), "")
  noctalia.writeFile(pickFile("colorpickmode"), replace and "replace" or "add")
  local start = (replace and work[sel]) or "#88C0D0"
  saveState()
  noctalia.runAsync({ "setsid", "-f", "sh", "-c", PICK, "sh", pickFile("colorpick"), "", source, start })
end

local function applyPick()
  local c = string.match(noctalia.readFile(pickFile("colorpick")) or "", "#%x%x%x%x%x%x")
  if not c then
    return
  end
  local mode = noctalia.string.trim(noctalia.readFile(pickFile("colorpickmode")) or "")
  noctalia.writeFile(pickFile("colorpick"), "")
  if mode == "replace" and sel and work[sel] then
    setColorAt(sel, c)
  else
    addColor(c)
  end
end

-- Keeps the colors that are on as a palette of your own; the packaged palettes are never overwritten.
local function savePalette()
  local name = string.match(noctalia.string.trim(saveName), "^[%w_-]+$")
  if not name then
    err = "Name the palette with letters, digits, - or _"
    render()
    return
  end
  for _, p in ipairs(palettes) do
    if p.name == name then
      err = "A palette called " .. name .. " exists"
      render()
      return
    end
  end
  local colors = {}
  for i, c in ipairs(work) do
    if not dis[i] then
      table.insert(colors, c)
    end
  end
  local dir = noctalia.getenv("HOME") .. "/.local/share/mabox-noctalia-ce/palettes"
  noctalia.mkdirAll(dir)
  noctalia.writeFile(dir .. "/" .. name .. ".pal", "all: " .. table.concat(colors, " ") .. "\n")
  err = nil
  note = "Saved palette " .. name
  palette = name
  group = "all"
  edited = false
  saveName = ""
  mineOpen = true
  gen = gen + 1
  saveState()
  loadPalettes()
  loadColors()
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
  local argv = { "setsid", "-f", "sh", "-c", RUN, "mb-recolor-job", mode, effGroup() }
  local dest = destDir()
  table.insert(argv, dest)
  table.insert(argv, effPalette())
  table.insert(argv, path)
  table.insert(argv, tostring(blur))
  table.insert(argv, offList())
  table.insert(argv, progressDir())
  table.insert(argv, resume and "1" or "0")
  writeWork()
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

local function deletePalette()
  local name = delAsk
  delAsk = nil
  if not name or not mineNames[name] then
    render()
    return
  end
  noctalia.runAsync({ "rm", "-f", "--", noctalia.getenv("HOME") .. "/.local/share/mabox-noctalia-ce/palettes/" .. name .. ".pal" }, function()
    if palette == name then
      palette = "nord"
      edited = false
      group = "all"
      saveState()
    end
    note = "Deleted palette " .. name
    loadPalettes()
    loadColors()
  end)
end

local function chip(key, text, on, onClick, onRight)
  return ui.button({ key = key .. (on and "-on" or ""), text = text, glyph = on and "check" or nil, variant = on and "primary" or "outline", controlSize = "sm", enabled = not running, onClick = idle(onClick), onRightClick = onRight and idle(onRight) or nil })
end

function render()
  local pal, mine, mineCount = {}, {}, 0
  for _, p in ipairs(palettes) do
    local c = chip("p" .. p.name, p.name, p.name == palette, function() choosePalette(p.name) end,
      mineNames[p.name] and function() delAsk = p.name; delAt = os.time() + 5; panel.setWantsSecondTicks(true); render() end or nil)
    if mineNames[p.name] then
      mineCount += 1
      -- A folded list still shows the palette in use.
      if mineOpen or p.name == palette then
        table.insert(mine, c)
      end
    else
      table.insert(pal, c)
    end
  end
  local grp = {}
  for _, g in ipairs(groupsOf(palette)) do
    table.insert(grp, chip("g" .. g, g, g == group, function() group = g; edited = false; saveState(); done = nil; render(); loadColors() end))
  end
  -- Chips per row: 5 by default, 4 for the palettes.
  local function chunk(items, prefix, per)
    per = per or 5
    local rows = {}
    for i = 1, #items, per do
      local cells = {}
      for k = i, math.min(i + per - 1, #items) do
        table.insert(cells, items[k])
      end
      table.insert(rows, ui.row({ key = prefix .. i, gap = 6 }, cells))
    end
    return rows
  end
  local palRows = chunk(pal, "pr", 4)
  local mineRows = chunk(mine, "mr", 4)
  local grpRows = chunk(grp, "gr")

  -- The working copy: a click selects a color, a dimmed one is switched off.
  local swatchBoxes = {}
  for i, c in ipairs(work) do
    local isOff = dis[i]
    local on = sel == i
    table.insert(swatchBoxes, ui.box({ key = "sw" .. i .. c .. (isOff and "x" or "") .. (on and "s" or ""), fill = c, width = 34, height = 34, radius = 6, opacity = isOff and 0.2 or 1,
      border = on and "primary" or "on_surface_variant", borderWidth = on and 3 or 1,
      tooltip = c .. (isOff and "  (off)" or "") .. "  - click to change it",
      onClick = idle(function() if sel == i then sel = nil else sel = i end; hexDraft = nil; saveState(); render() end) }))
  end
  if #swatchBoxes == 0 then
    table.insert(swatchBoxes, ui.box({ key = "sw0", height = 34 }))
  end
  local swatchRows = {}
  for i = 1, #swatchBoxes, 8 do
    table.insert(swatchRows, ui.row({ key = "swr" .. i, gap = 6 }, { table.unpack(swatchBoxes, i, math.min(i + 7, #swatchBoxes)) }))
  end

  local editor
  if sel and work[sel] then
    local i = sel
    local c = work[i]
    editor = ui.column({ key = "editor", gap = 6 }, {
      ui.row({ gap = 6, align = "center" }, {
        ui.label({ text = "Color " .. i, color = "on_surface_variant" }),
        ui.input({ key = "hex" .. i .. c, value = c, width = 110, controlSize = "sm", frameVisible = true, tooltip = "Type #RRGGBB and press Enter",
          onChange = idle(function(t) hexDraft = t end),
          onSubmit = idle(function()
            local h = string.match(noctalia.string.trim(hexDraft or c), "^#?(%x%x%x%x%x%x)$")
            if h then
              setColorAt(i, "#" .. h)
            else
              err = "Use a color like #88C0D0"
              render()
            end
          end) }),
      }),
      ui.row({ gap = 6 }, {
        ui.button({ key = "editscreen", glyph = "color-picker", text = "From screen", variant = "outline", controlSize = "sm", enabled = not running, tooltip = "Click a color anywhere on the screen", onClick = idle(function() pickColor("screen", "replace") end) }),
        ui.button({ key = "editchoose", glyph = "palette", text = "Choose", variant = "outline", controlSize = "sm", enabled = not running, tooltip = "Open the color chooser", onClick = idle(function() pickColor("dialog", "replace") end) }),
        ui.button({ key = "editoff", text = dis[i] and "Switch on" or "Switch off", variant = "outline", controlSize = "sm", enabled = not running, onClick = idle(function() toggleColor(i) end) }),
        ui.button({ key = "editrm", glyph = "trash", text = "Remove", variant = "ghost", controlSize = "sm", enabled = not running, onClick = idle(function() removeColor(i) end) }),
      }),
    })
  else
    editor = ui.label({ text = "Click a color to change it or switch it off.", color = "on_surface_variant", fontSize = 11 })
  end

  local lookCols = {}
  for _, l in ipairs({ { "clut", "Soft" }, { "remap", "Hard" }, { "smooth", "Smooth" }, { "lut", "Blend" } }) do
    local m, label = l[1], l[2]
    local pick = function() mode = m; saveState(); done = nil; render() end
    local thumb = previews[m] and ui.image({ key = "pv" .. m .. pvGen, path = previews[m], width = 240, height = 140, radius = 6, fit = "cover", border = m == mode and "primary" or "on_surface_variant", borderWidth = m == mode and 3 or 1, onClick = idle(pick) })
      or ui.box({ key = "pvb" .. m, fill = "surface", width = 240, height = 140, radius = 6, border = m == mode and "primary" or "on_surface_variant", borderWidth = m == mode and 3 or 1, onClick = idle(pick) })
    table.insert(lookCols, ui.column({ key = "look" .. m, gap = 6, align = "center" }, { thumb, chip(m, label, m == mode, pick) }))
  end

  local function leaf(p)
    return string.match(p, "([^/]+)/*$") or p
  end
  local pathsText = (src == "" and "no source" or leaf(src)) .. "  ->  " .. (out == "" and "default folder" or leaf(out)) .. (resume and "  (resume)" or "")
  local pathsHead = ui.button({ key = "pathshead", glyph = pathsOpen and "chevron-down" or "chevron-right", text = pathsOpen and "Folders" or ("Folders: " .. pathsText), variant = "outline", controlSize = "sm", contentAlign = "start",
    tooltip = "Fold the source and output folders away", onClick = function() pathsOpen = not pathsOpen; saveState(); render() end })
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
    ui.input({ key = "out" .. gen, value = out, placeholder = "~/Pictures/" .. (edited and "custom/all" or (palette .. "/" .. group)), frameVisible = true, onChange = idle(function(t) out = t; saveState() end), onSubmit = idle(run) }),
    ui.row({ gap = 6 }, {
      ui.button({ key = "outdir", glyph = "folder-open", text = "Folder", variant = "outline", controlSize = "sm", enabled = not running, onClick = idle(function() browse("out") end) }),
      ui.button({ key = "outclear", glyph = "x", text = "Default", variant = "ghost", controlSize = "sm", enabled = not running, onClick = idle(function() out = ""; saveState(); render() end) }),
    }),
    ui.row({ gap = 8, align = "center" }, {
      ui.toggle({ key = "resume" .. (resume and "1" or "0"), checked = resume, enabled = not running, onChange = idle(function(v) resume = v == true or v == "true"; saveState(); render() end) }),
      ui.label({ text = "Resume: skip images already in this folder", color = "on_surface_variant", fontSize = 11 }),
    }),
  })
  local palCard = ui.column(card("pal"), {
    ui.label({ text = "Palette", fontWeight = "bold" }),
    ui.column({ gap = 6 }, palRows),
    mineCount > 0 and ui.button({ key = "minehead", glyph = mineOpen and "chevron-down" or "chevron-right", text = "My palettes (" .. mineCount .. ")", variant = "outline", controlSize = "sm", contentAlign = "start",
      tooltip = "Palettes you saved in the Wallgen panel", onClick = function() mineOpen = not mineOpen; saveState(); render() end }) or ui.box({ height = 0 }),
    #mineRows > 0 and ui.column({ key = "mine", gap = 6 }, mineRows) or ui.box({ height = 0 }),
    delAsk and ui.row({ key = "delask", gap = 8, align = "center" }, {
      ui.label({ text = "Delete " .. delAsk .. "?", color = "error", flexGrow = 1 }),
      ui.button({ key = "delyes", glyph = "trash", text = "Delete", variant = "destructive", controlSize = "sm", onClick = idle(deletePalette) }),
      ui.button({ key = "delno", text = "Cancel", variant = "outline", controlSize = "sm", onClick = function() delAsk = nil; render() end }),
    }) or ui.box({ height = 0 }),
    ui.row({ gap = 8, align = "center" }, {
      ui.label({ text = edited and "Colors (changed copy)" or "Colors", fontWeight = "bold", flexGrow = 1 }),
      ui.button({ key = "reset", glyph = "refresh", text = "Reset", variant = "ghost", controlSize = "sm", enabled = not running, tooltip = "Back to the colors of the palette", onClick = idle(resetColors) }),
    }),
    ui.column({ gap = 6 }, grpRows),
    ui.column({ gap = 6 }, swatchRows),
    editor,
    ui.row({ gap = 6 }, {
      ui.button({ key = "addchoose", glyph = "plus", text = "Add", variant = "outline", controlSize = "sm", enabled = not running, tooltip = "Add a color from the color chooser", onClick = idle(function() pickColor("dialog", "add") end) }),
      ui.button({ key = "addscreen", glyph = "color-picker", text = "Add from screen", variant = "outline", controlSize = "sm", enabled = not running, tooltip = "Click a color anywhere on the screen to add it", onClick = idle(function() pickColor("screen", "add") end) }),
    }),
    ui.label({ text = "Changes stay in this copy; the palette itself is not touched.", color = "on_surface_variant", fontSize = 11 }),
    ui.row({ gap = 6, align = "center" }, {
      ui.input({ key = "savename" .. gen, value = saveName, placeholder = "name of a new palette", controlSize = "sm", frameVisible = true, flexGrow = 1, onChange = function(t) saveName = t end, onSubmit = idle(savePalette) }),
      ui.button({ key = "savepal", glyph = "device-floppy", text = "Save as", variant = "outline", controlSize = "sm", enabled = not running, tooltip = "Keep the colors that are on as a palette of your own", onClick = idle(savePalette) }),
    }),
    note and ui.label({ text = note, color = "primary", fontSize = 11 }) or ui.box({ height = 0 }),
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
      ui.column({ key = "col-left", gap = 10, flexGrow = 1, minWidth = 380 }, pathsOpen and { pathsHead, srcCard, outCard, palCard } or { pathsHead, palCard }),
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
  delAsk = nil
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
  if not running then
    applyPick()
  end
  saveState()
  render()
  loadPalettes()
  loadColors()
  check()
  panel.setWantsSecondTicks(true)
end

-- The images written so far are counted by wc: a folder of tens of thousands of images makes an out file Luau cannot scan within its CPU budget.
local counting = false

function update()
  if delAsk and os.time() >= delAt then
    delAsk = nil
    render()
  end
  if running then
    check()
    if counting then
      return
    end
    counting = true
    noctalia.runAsync({ "sh", "-c", 'n=$(wc -l < "$1/out" 2>/dev/null); k=$(grep -c "^skip: " "$1/out" 2>/dev/null); echo "${n:-0} ${k:-0}"', "sh", progressDir() }, function(r)
      counting = false
      local n, k = string.match(r.stdout or "", "^%s*(%d+)%s+(%d+)")
      if running and n and readProgress(tonumber(n), tonumber(k)) then
        render()
      end
    end)
  end
end
