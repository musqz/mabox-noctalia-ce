--!nonstrict
-- Wallgen: front end for mb-wallgen (a wallpaper made from a palette).
local logo = require("./celogo.luau")
local hotkey = require("./hotkey.luau")
local switch = require("./switch.luau")

return function(compact)

local TYPES = { "blend", "bilinear", "mesh", "voronoi", "plasma", "contour", "waves", "twisted", "linear", "radial", "dither", "solid" }
local SIZES = { { "", "Auto" }, { "1920x1080", "1920x1080" }, { "2560x1440", "2560x1440" }, { "3840x2160", "3840x2160" } }
-- What the Pattern slider means per type, and whether the angle applies.
local PATTERN = { mesh = "Points", voronoi = "Cells", plasma = "Shape size", contour = "Bands", waves = "Waves", twisted = "Twist", linear = "Stripes", radial = "Rings", dither = "Grain size" }
local TURNS = { blend = true, linear = true, twisted = true, waves = true }

local function card(key)
  return { key = key, fill = "surface_variant", radius = 10, padding = 12, gap = 10, border = "primary", borderWidth = 1 }
end

local palettes = {}
local palette = "nord"
local group = "all"
local kind = "mesh"
local look = "soft"
local size = ""
local out = ""
local work = {}
local dis = {}
local sel = nil
local edited = false
local MAXC = 64
local hexDraft = nil
local saveName = ""
local blur = 0
local tab = "colors"
local custom = {}
local solidHex = nil
local customOpen = false
local armedDel = nil
local swatches = {}
local colGen = 0
local seed = 1
local previews = {}
local pvGen = 0
local busy = false
local err = nil
local note = nil
local pat, ang = nil, nil
local bal = 50
local gen = 0
local render
local loadPreviews

local function dataFile(name)
  return noctalia.pluginDataDir() .. "/" .. name
end

-- The colors that take part: the working copy without the ones switched off.
local function enabledList()
  local t = {}
  for i, c in ipairs(work) do
    if not dis[i] then
      table.insert(t, c)
    end
  end
  return table.concat(t, ",")
end

-- Solid is one color of its own; without one, Balance picks from the colors that are on.
local function solidColor()
  return solidHex or ""
end

local function disList()
  local t = {}
  for i in pairs(dis) do
    table.insert(t, tostring(i))
  end
  table.sort(t)
  return table.concat(t, ",")
end

local function saveState()
  noctalia.mkdirAll(noctalia.pluginDataDir())
  noctalia.writeFile(dataFile("wg-state"), string.format("palette=%s\ngroup=%s\nkind=%s\nlook=%s\nsize=%s\nout=%s\nwork=%s\ndis=%s\nedited=%d\nsel=%s\nsolid=%s\nopen=%d\nblur=%d\npat=%s\nang=%s\nbal=%d\n", palette, group, kind, look, size, out, table.concat(work, ","), disList(), edited and 1 or 0, sel and tostring(sel) or "", solidHex or "", customOpen and 1 or 0, blur, pat and tostring(pat) or "", ang and tostring(ang) or "", bal))
end

local function loadState()
  for line in string.gmatch(noctalia.readFile(dataFile("wg-state")) or "", "[^\n]+") do
    local k, v = string.match(line, "^(%a+)=(.*)$")
    if k == "palette" then palette = v
    elseif k == "group" then group = v
    elseif k == "kind" then kind = v
    elseif k == "look" then look = v == "flat" and "flat" or "soft"
    elseif k == "size" then size = v
    elseif k == "out" then out = v
    elseif k == "pat" then pat = tonumber(v)
    elseif k == "ang" then ang = tonumber(v)
    elseif k == "bal" then bal = tonumber(v) or 50
    elseif k == "work" then
      work = {}
      for c in string.gmatch(v, "#%x+") do table.insert(work, c) end
    elseif k == "dis" then
      dis = {}
      for i in string.gmatch(v, "%d+") do dis[tonumber(i)] = true end
    elseif k == "edited" then edited = v == "1"
    elseif k == "sel" then sel = tonumber(v)
    elseif k == "open" then customOpen = v == "1"
    elseif k == "solid" then solidHex = string.match(v, "#%x%x%x%x%x%x")
    elseif k == "blur" then blur = tonumber(v) or 0
    end
  end
end

local function expand(t)
  t = noctalia.string.trim(t)
  return (string.gsub(t, "^~/", noctalia.getenv("HOME") .. "/"))
end

local function destDir()
  local d = expand(out)
  if d == "" then
    d = noctalia.getenv("HOME") .. "/Pictures/" .. (edited and "custom" or palette) .. "/generated"
  end
  return d
end

local function groupsOf(name)
  for _, p in ipairs(palettes) do
    if p.name == name then
      return p.groups
    end
  end
  return { "all" }
end

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
    local known = false
    for _, p in ipairs(palettes) do
      known = known or p.name == palette
    end
    if #palettes > 0 and not known then
      palette = palettes[1].name
    end
    render()
  end)
  -- palettes saved by the user live in this folder
  noctalia.runAsync({ "sh", "-c", 'for f in "$HOME"/.local/share/mabox-noctalia-ce/palettes/*.pal; do [ -f "$f" ] && printf "%s %s\n" "$(basename "$f" .pal)" "$(head -n1 "$f")"; done' }, function(r)
    custom = {}
    for line in string.gmatch(r.stdout or "", "[^\n]+") do
      local n = string.match(line, "^(%S+)")
      if n then
        local cols = {}
        for c in string.gmatch(line, "#%x%x%x%x%x%x") do
          table.insert(cols, c)
        end
        custom[n] = cols
      end
    end
    render()
  end)
end

local function loadColors()
  colGen += 1
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

-- One small image per type with the same seed, in a fresh folder each time (ui.image caches by path).
local PREVIEW = [[dir=$1; seed=$2; pal=$3; grp=$4; cust=$5; look=$6; pat=$7; ang=$8; bal=$9; blur=${10}; solid=${11}; shift 11
wg() { if [ -n "$cust" ]; then mb-wallgen -c "$cust" "$@"; else mb-wallgen -p "$pal" -g "$grp" "$@"; fi; }
rm -rf "$dir"; mkdir -p "$dir"
tile() { [ "$1" = solid ] && [ -n "$solid" ] && cust=$solid; wg -t "$1" -s "$seed" -l "$look" ${pat:+-a "$pat"} ${ang:+-A "$ang"} -b "$bal" -B "$blur" -S 480x270 -o "$dir/$1"; }
for t; do tile "$t" >/dev/null 2>&1 & done
wait
ls "$dir"/*/*]]

function loadPreviews()
  pvGen += 1
  local mine = pvGen
  local base = noctalia.pluginDataDir() .. "/wg-pv"
  local argv = { "sh", "-c", PREVIEW, "sh", base .. "/" .. mine, tostring(seed), palette, group, enabledList(), look, pat and tostring(pat) or "", ang and tostring(ang) or "", tostring(bal), tostring(blur), solidColor() }
  for _, t in ipairs(TYPES) do
    table.insert(argv, t)
  end
  noctalia.runAsync(argv, function(r)
    if mine ~= pvGen then
      return
    end
    previews = {}
    for line in string.gmatch(r.stdout or "", "[^\n]+") do
      local t = string.match(line, "/(%a+)/[^/]+$")
      if t then
        previews[t] = line
      end
    end
    noctalia.runAsync({ "sh", "-c", 'for d in "$1"/*; do [ "$d" = "$2" ] || rm -rf "$d"; done', "sh", base, base .. "/" .. mine })
    render()
  end)
end

local function changed()
  edited = true
  note = nil
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
  changed()
end

local function removeColor(i)
  if #work <= 1 then
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
      if not dis[k] then on += 1 end
    end
    if on <= 1 then
      note = "Keep at least one color on"
      render()
      return
    end
    dis[i] = true
  end
  changed()
end

local function setAll(list)
  work = {}
  for _, c in ipairs(list) do
    if #work < MAXC then
      table.insert(work, string.upper(c))
    end
  end
  dis = {}
  sel = nil
  changed()
end

-- The panel closes while a picker is open (the eyedropper must see the screen, the chooser is a window of its own)
-- and opens again with the result in a file; onOpen applies it.
-- source: "screen" (eyedropper) or "dialog" (GTK color chooser, starting at the color of the selected box).
local PICK = [[noctalia msg panel-close
sleep 0.3
if [ "$3" = screen ]; then c=$(mb-colorpick); else c=$(yad --color --center --title="Wallgen color" --init-color="$4"); fi
[ -n "$c" ] && printf "%s" "$c" > "$1"
noctalia msg panel-open mabox/recolor:PANELID]]

local function pickColor(source, mode)
  local replace = mode == "replace"
  noctalia.mkdirAll(noctalia.pluginDataDir())
  noctalia.writeFile(dataFile("wg-pick"), "")
  noctalia.writeFile(dataFile("wg-pickmode"), mode == "solid" and "solid" or ((replace and sel) and "replace" or "add"))
  local start = (replace and sel and work[sel]) or (mode == "solid" and solidHex) or "#88C0D0"
  saveState()
  noctalia.runAsync({ "setsid", "-f", "sh", "-c", (string.gsub(PICK, "PANELID", compact and "wallgen-compact" or "wallgen")), "sh", dataFile("wg-pick"), "", source, start })
end

local function applyPick()
  local c = string.match(noctalia.readFile(dataFile("wg-pick")) or "", "#%x%x%x%x%x%x")
  if not c then
    return
  end
  local mode = noctalia.string.trim(noctalia.readFile(dataFile("wg-pickmode")) or "")
  noctalia.writeFile(dataFile("wg-pick"), "")
  if mode == "solid" then
    solidHex = string.upper(c)
    note = nil
    saveState()
    render()
    loadPreviews()
  elseif mode == "replace" and sel and work[sel] then
    setColorAt(sel, c)
  else
    addColor(c)
  end
end

local function fromWallpaper()
  noctalia.runAsync({ "sh", "-c", 'mb-wallgen --extract "$(noctalia msg wallpaper-get | head -n1)" "$1" "$2"', "sh", "4", tostring(math.random(1, 999999)) }, function(r)
    local list = {}
    for c in string.gmatch(r.stdout or "", "#%x+") do
      table.insert(list, c)
    end
    if #list == 0 then
      err = "Could not read colors from the wallpaper"
      render()
    else
      setAll(list)
    end
  end)
end

-- Back to the colors of the chosen palette.
local function resetColors()
  edited = false
  note = nil
  loadColors()
end

-- Saves the working copy as a palette of its own; the packaged palettes are never overwritten.
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
  customOpen = true
  gen += 1
  loadPalettes()
  loadColors()
end

local function refresh()
  edited = false
  saveState()
  render()
  loadColors()
end

-- Two clicks: the first arms, the second removes the file of a palette you saved.
local function deletePalette(name)
  if armedDel ~= name then
    armedDel = name
    render()
    return
  end
  armedDel = nil
  noctalia.runAsync({ "rm", "-f", "--", noctalia.getenv("HOME") .. "/.local/share/mabox-noctalia-ce/palettes/" .. name .. ".pal" }, function()
    if palette == name then
      palette = "nord"
      group = "all"
      edited = false
    end
    loadPalettes()
    loadColors()
  end)
end

local function choosePalette(name)
  palette = name
  local ok = false
  for _, g in ipairs(groupsOf(name)) do
    ok = ok or g == group
  end
  if not ok then
    group = "all"
  end
  note = nil
  refresh()
end

-- n images at full size; the seed counts up so each one differs. Prints the written paths.
-- Detached (setsid) like the Recolor job: ten big images take longer than runAsync allows. The paths go to a log file.
local GENERATE = [[kind=$1; seed=$2; pal=$3; grp=$4; cust=$5; look=$6; size=$7; dest=$8; n=$9; shift 9
pat=$1; ang=$2; bal=$3; blur=$4; solid=$5; setw=$6; log=$7
[ "$kind" = solid ] && [ -n "$solid" ] && cust=$solid
wg() { if [ -n "$cust" ]; then mb-wallgen -c "$cust" "$@"; else mb-wallgen -p "$pal" -g "$grp" "$@"; fi; }
: > "$log"
i=0
while [ "$i" -lt "$n" ]; do
  wg -t "$kind" -s $(( seed + i )) -l "$look" ${size:+-S "$size"} ${pat:+-a "$pat"} ${ang:+-A "$ang"} -b "$bal" -B "$blur" -o "$dest" >> "$log" || { notify-send -u critical -a Wallgen "Wallgen failed" "image $(( i + 1 )) of $n"; exit 1; }
  i=$(( i + 1 ))
done
[ "$setw" = 1 ] && noctalia msg wallpaper-set "$(tail -n1 "$log")" >/dev/null
notify-send -a Wallgen "Wallgen" "$n images written to $dest"]]

local function logFile()
  return noctalia.pluginDataDir() .. "/wg-gen-log"
end

local function countLines()
  return select(2, string.gsub(noctalia.readFile(logFile()) or "", "\n", ""))
end

local totalImages = 0

-- Looks every 2 s whether the job still runs (short commands only), and shows the number of images done.
local function watchJob()
  noctalia.runAsync({ "sh", "-c", "sleep 2; pgrep -f 'mb-wallgen-jo[b]' >/dev/null && echo busy" }, function(r)
    if string.find(r.stdout or "", "busy", 1, true) then
      note = "Generating..."
      render()
      watchJob()
      return
    end
    busy = false
    local files = {}
    for line in string.gmatch(noctalia.readFile(logFile()) or "", "[^\n]+") do
      table.insert(files, line)
    end
    if #files == 0 then
      note = nil
      err = "Nothing was generated"
    else
      if #files < totalImages then
        err = "Only " .. #files .. " of " .. totalImages .. " images were written (see the notification)"
      else
        note = #files .. (#files == 1 and " image written to " or " images written to ") .. destDir()
      end
    end
    render()
  end)
end

local function generate(thenSet)
  if busy then
    return
  end
  busy = true
  err = nil
  totalImages = 1
  note = "Generating..."
  render()
  noctalia.mkdirAll(noctalia.pluginDataDir())
  noctalia.runAsync({ "setsid", "-f", "sh", "-c", GENERATE, "mb-wallgen-job", kind, tostring(seed), palette, group, enabledList(), look, size, destDir(), "1", pat and tostring(pat) or "", ang and tostring(ang) or "", tostring(bal), tostring(blur), solidColor(), thenSet and "1" or "0", logFile() })
  watchJob()
end

local function stopJob()
  noctalia.runAsync({ "sh", "-c", "for p in $(pgrep -f 'mb-wallgen-jo[b]'); do pkill -s \"$p\"; done; true" }, function()
    busy = false
    note = "Stopped"
    render()
  end)
end

local USE = [[d=${XDG_STATE_HOME:-$HOME/.local/state}/noctalia/plugins/data/mabox/wallpaper-dirs
mkdir -p "$d"
grep -qxF -- "$1" "$d/dirs" 2>/dev/null || echo "$1" >> "$d/dirs"
mb-wallpaper-dir "$1"]]

local BROWSE = [[p=$(yad --file --directory --center --width=1000 --height=650 --title="Wallgen: folder" --filename="$1/") || p=
[ -n "$p" ] && readlink -f "$p" > "$2"
noctalia msg panel-close; noctalia msg panel-open mabox/recolor:PANELID]]

local function browse()
  noctalia.mkdirAll(noctalia.pluginDataDir())
  noctalia.runAsync({ "setsid", "-f", "sh", "-c", (string.gsub(BROWSE, "PANELID", compact and "wallgen-compact" or "wallgen")), "sh", noctalia.getenv("HOME") .. "/Pictures", dataFile("wg-out") })
end

local function chip(key, text, on, onClick)
  return ui.button({ key = key .. (on and "1" or "0"), text = text, glyph = on and "check" or nil, variant = on and "primary" or "outline", controlSize = "sm", onClick = onClick })
end

function render()
  local pal, mine, mineBy = {}, {}, {}
  for _, p in ipairs(palettes) do
    if custom[p.name] then
      -- the colors in small, for a quick look at the range; every row has the same columns so the trash lines up
      local cols = custom[p.name]
      local w = math.max(3, math.min(10, math.floor(190 / math.max(1, #cols))))
      local strip = {}
      for i, c in ipairs(cols) do
        table.insert(strip, ui.box({ key = "mini" .. p.name .. i .. c, fill = c, width = w, height = 18, radius = 1 }))
      end
      local row = ui.row({ key = "my" .. p.name, gap = 6, align = "center" }, {
        ui.button({ key = "p" .. p.name .. (p.name == palette and "1" or "0"), text = p.name, glyph = p.name == palette and "check" or nil, variant = p.name == palette and "primary" or "outline", controlSize = "sm", width = 130, maxLines = 1,
          tooltip = p.name, onClick = function() armedDel = nil; choosePalette(p.name) end }),
        ui.row({ key = "strip" .. p.name, gap = 0, width = 195 }, strip),
        ui.box({ flexGrow = 1, height = 1 }),
        ui.button({ key = "del" .. p.name .. (armedDel == p.name and "1" or "0"), glyph = "trash", text = armedDel == p.name and "Sure?" or nil, variant = armedDel == p.name and "destructive" or "ghost", controlSize = "sm", tooltip = armedDel == p.name and "Click again to delete" or "Delete this palette", onClick = function() deletePalette(p.name) end }),
      })
      table.insert(mine, row)
      mineBy[p.name] = row
    else
      table.insert(pal, chip("p" .. p.name, p.name, p.name == palette, function() choosePalette(p.name) end))
    end
  end
  local myCount = #mine
  local grp = {}
  for _, g in ipairs(groupsOf(palette)) do
    table.insert(grp, chip("g" .. g, g, g == group, function() group = g; note = nil; refresh() end))
  end
  local function chunk(items, prefix, per)
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

  -- The working copy: click selects a color, a dimmed one is switched off.
  local swatchBoxes = {}
  for i, c in ipairs(work) do
    local off = dis[i]
    local on = sel == i
    table.insert(swatchBoxes, ui.box({ key = "sw" .. i .. c .. (off and "x" or "") .. (on and "s" or ""), fill = c, width = 40, height = 40, radius = 6, opacity = off and 0.2 or 1,
      border = on and "primary" or "on_surface_variant", borderWidth = on and 3 or 1,
      tooltip = c .. (off and "  (off)" or "") .. "  - click to change it",
      onClick = function() if sel == i then sel = nil else sel = i end; render() end }))
  end
  if #swatchBoxes == 0 then
    table.insert(swatchBoxes, ui.box({ key = "sw0", height = 40 }))
  end
  local swatchRows = {}
  local per = compact and 12 or 8
  for i = 1, #swatchBoxes, per do
    table.insert(swatchRows, ui.row({ key = "swr" .. i, gap = 6 }, { table.unpack(swatchBoxes, i, math.min(i + per - 1, #swatchBoxes)) }))
  end

  local editor
  if sel and work[sel] then
    local i = sel
    local c = work[i]
    editor = ui.column({ key = "editor", gap = 6 }, {
      ui.row({ gap = 6, align = "center" }, {
        ui.label({ text = "Color " .. i, color = "on_surface_variant" }),
        ui.input({ key = "hex" .. i .. c, value = c, width = 110, controlSize = "sm", frameVisible = true, tooltip = "Type #RRGGBB and press Enter",
          onChange = function(t) hexDraft = t end,
          onSubmit = function()
            local h = string.match(noctalia.string.trim(hexDraft or c), "^#?(%x%x%x%x%x%x)$")
            if h then
              setColorAt(i, "#" .. h)
            else
              err = "Use a color like #88C0D0"
              render()
            end
          end }),
      }),
      ui.row({ gap = 6 }, {
        ui.button({ key = "editscreen", glyph = "color-picker", text = "From screen", variant = "outline", controlSize = "sm", tooltip = "Click a color anywhere on the screen", onClick = function() pickColor("screen", "replace") end }),
        ui.button({ key = "editchoose", glyph = "palette", text = "Choose", variant = "outline", controlSize = "sm", tooltip = "Open the color chooser", onClick = function() pickColor("dialog", "replace") end }),
        ui.button({ key = "editoff", text = dis[i] and "Switch on" or "Switch off", variant = "outline", controlSize = "sm", onClick = function() toggleColor(i) end }),
        ui.button({ key = "editrm", glyph = "trash", text = "Remove", variant = "ghost", controlSize = "sm", onClick = function() removeColor(i) end }),
      }),
    })
  else
    editor = ui.label({ text = "Click a color to change it or switch it off.", color = "on_surface_variant", fontSize = 11 })
  end

  local tiles = {}
  for _, t in ipairs(TYPES) do
    local on = t == kind
    local pick = function() kind = t; note = nil; saveState(); render() end
    local thumb = previews[t] and ui.image({ key = "tv" .. t .. pvGen, path = previews[t], width = 200, height = 113, radius = 6, fit = "cover", border = on and "primary" or "on_surface_variant", borderWidth = on and 3 or 1, onClick = pick })
      or ui.box({ key = "tb" .. t, fill = "surface", width = 200, height = 113, radius = 6, border = on and "primary" or "on_surface_variant", borderWidth = on and 3 or 1, onClick = pick })
    table.insert(tiles, ui.column({ key = "tile" .. t, gap = 4, align = "center" }, { thumb, chip("tc" .. t, t, on, pick) }))
  end
  local tileRows = {}
  for i = 1, #tiles, 4 do
    table.insert(tileRows, ui.row({ key = "tr" .. i, gap = 12 }, { table.unpack(tiles, i, math.min(i + 3, #tiles)) }))
  end

  local sizeChips = {}
  for _, s in ipairs(SIZES) do
    table.insert(sizeChips, chip("sz" .. s[1], s[2], s[1] == size, function() size = (s[1] == size) and "" or s[1]; saveState(); render() end))
  end
  local palCard = ui.column(card("pal"), {
    ui.label({ text = "Palette", fontWeight = "bold" }),
    ui.column({ gap = 6 }, chunk(pal, "pr", compact and 5 or 3)),
    myCount > 0 and ui.button({ key = "myhead", glyph = customOpen and "chevron-down" or "chevron-right", text = "My palettes (" .. myCount .. ")", variant = "outline", controlSize = "sm", contentAlign = "start",
      tooltip = "Palettes you saved with Save as; they are also in Recolor", onClick = function() customOpen = not customOpen; armedDel = nil; saveState(); render() end }) or ui.box({ height = 0 }),
    (myCount > 0 and customOpen) and ui.column({ key = "mypals", gap = 4 }, {
      ui.column({ gap = 4 }, mine),
      ui.label({ text = "Saved in ~/.local/share/mabox-noctalia-ce/palettes/", color = "on_surface_variant", fontSize = 11, maxLines = 2 }),
    }) or ((myCount > 0 and not customOpen and mineBy[palette]) and ui.column({ key = "mysel", gap = 4 }, { mineBy[palette] }) or ui.box({ height = 0 })),
    ui.column({ gap = 6 }, chunk(grp, "gr", compact and 6 or 4)),
    ui.row({ gap = 8, align = "center" }, {
      ui.label({ text = edited and "Colors (changed copy)" or "Colors", fontWeight = "bold", flexGrow = 1 }),
      ui.button({ key = "reset", glyph = "refresh", text = "Reset", variant = "ghost", controlSize = "sm", tooltip = "Back to the colors of the palette", onClick = resetColors }),
    }),
    ui.column({ gap = 6 }, swatchRows),
    editor,
    ui.row({ gap = 6 }, {
      ui.button({ key = "addchoose", glyph = "plus", text = "Add", variant = "outline", controlSize = "sm", tooltip = "Add a color from the color chooser", onClick = function() pickColor("dialog", "add") end }),
      ui.button({ key = "addscreen", glyph = "color-picker", text = "Add from screen", variant = "outline", controlSize = "sm", tooltip = "Click a color anywhere on the screen to add it", onClick = function() pickColor("screen", "add") end }),
      ui.button({ key = "fromwp", glyph = "photo", text = "From wallpaper", variant = "outline", controlSize = "sm", tooltip = "Four colors from the current wallpaper; click again for other ones", onClick = fromWallpaper }),
    }),
    ui.label({ text = "Palette changes stay in this copy; the palette itself is not touched.", color = "on_surface_variant", fontSize = 11 }),
    ui.row({ gap = 6, align = "center" }, {
      ui.input({ key = "savename" .. gen, value = saveName, placeholder = "name of a new palette", controlSize = "sm", frameVisible = true, flexGrow = 1, onChange = function(t) saveName = t end, onSubmit = savePalette }),
      ui.button({ key = "savepal", glyph = "device-floppy", text = "Save as", variant = "outline", controlSize = "sm", tooltip = "Keep these colors as a palette of your own", onClick = savePalette }),
    }),
  })
  local sizeCard = ui.column(card("size"), {
    ui.label({ text = "Size", fontWeight = "bold" }),
    ui.row({ key = "sizes", gap = 6 }, sizeChips),
    ui.label({ text = "Auto uses the size of the first monitor.", color = "on_surface_variant", fontSize = 11 }),
  })
  local outCard = ui.column(card("out"), {
    ui.label({ text = "Output folder", fontWeight = "bold" }),
    ui.input({ key = "wout" .. gen, value = out, placeholder = "~/Pictures/" .. (edited and "custom" or palette) .. "/generated", frameVisible = true, onChange = function(t) out = t; saveState() end }),
    ui.row({ gap = 6 }, {
      ui.button({ key = "outdir", glyph = "folder-open", text = "Folder", variant = "outline", controlSize = "sm", onClick = browse }),
      ui.button({ key = "outclear", glyph = "x", text = "Default", variant = "ghost", controlSize = "sm", onClick = function() out = ""; saveState(); render() end }),
    }),
  })
  local function slider(label, key, min, max, step, value, valueText, onChange, onEnd)
    return ui.row({ key = "adj-" .. key, gap = 8, align = "center" }, {
      ui.label({ text = label, color = "on_surface_variant", width = 90 }),
      ui.slider({ key = "sl-" .. key, min = min, max = max, step = step, value = value, controlSize = "sm", flexGrow = 1, onChange = onChange, onDragEnd = onEnd }),
      ui.label({ text = valueText, width = 48 }),
    })
  end
  local adjust = {}
  if kind == "solid" then
    table.insert(adjust, ui.column({ key = "solidbox", gap = 6 }, {
      ui.label({ text = "Solid color", fontWeight = "bold" }),
      ui.row({ gap = 8, align = "center" }, {
        ui.box({ key = "solidsw" .. (solidHex or "-"), fill = solidHex or "surface", width = 48, height = 32, radius = 6, border = "on_surface_variant", borderWidth = 1 }),
        ui.label({ text = solidHex or "auto: Balance picks one of your colors", color = "on_surface_variant", flexGrow = 1, maxLines = 2 }),
      }),
      ui.row({ gap = 6 }, {
        ui.button({ key = "solidchoose", glyph = "palette", text = "Choose", variant = "outline", controlSize = "sm", onClick = function() pickColor("dialog", "solid") end }),
        ui.button({ key = "solidscreen", glyph = "color-picker", text = "From screen", variant = "outline", controlSize = "sm", onClick = function() pickColor("screen", "solid") end }),
        ui.button({ key = "solidsel", text = "Selected", variant = "outline", controlSize = "sm", tooltip = "Use the color selected in Colors", enabled = sel ~= nil and work[sel] ~= nil, onClick = function() solidHex = work[sel]; saveState(); render(); loadPreviews() end }),
        ui.button({ key = "solidauto", glyph = "x", text = "Auto", variant = "ghost", controlSize = "sm", onClick = function() solidHex = nil; saveState(); render(); loadPreviews() end }),
      }),
    }))
  end
  if PATTERN[kind] then
    table.insert(adjust, slider(PATTERN[kind], "pat", 0, 100, 1, pat or 50, pat and tostring(pat) or "auto",
      function(v) pat = math.floor(tonumber(v) or 50); render() end, function() saveState(); loadPreviews() end))
  end
  if TURNS[kind] then
    table.insert(adjust, slider("Angle", "ang", 0, 345, 15, ang or 0, ang and (tostring(ang) .. "°") or "auto",
      function(v) ang = math.floor(tonumber(v) or 0); render() end, function() saveState(); loadPreviews() end))
  end
  table.insert(adjust, slider("Balance", "bal", 0, 100, 5, bal, bal == 50 and "even" or (bal < 50 and "dark" or "light"),
    function(v) bal = math.floor(tonumber(v) or 50); render() end, function() saveState(); loadPreviews() end))
  table.insert(adjust, slider("Blur", "blur", 0, 20, 1, blur, blur == 0 and "off" or string.format("%.1f%%", blur / 10),
    function(v) blur = math.floor(tonumber(v) or 0); render() end, function() saveState(); loadPreviews() end))
  table.insert(adjust, ui.button({ key = "adjreset", glyph = "refresh", text = "Reset", variant = "ghost", controlSize = "sm", tooltip = "Back to the seed's own values", onClick = function() pat = nil; ang = nil; bal = 50; blur = 0; saveState(); render(); loadPreviews() end }))
  table.insert(adjust, ui.label({ text = "The sliders apply to every tile. Balance gives more of the dark or the light colors.", color = "on_surface_variant", fontSize = 11, maxLines = 3 }))
  local adjustCard = ui.column(card("adjust"), adjust)
  local typeCard = ui.column(card("types"), {
    ui.row({ gap = 8, align = "center" }, {
      ui.label({ text = "Type", fontWeight = "bold", flexGrow = 1 }),
      chip("lsoft", "Soft", look == "soft", function() look = "soft"; saveState(); render(); loadPreviews() end),
      chip("lflat", "Flat", look == "flat", function() look = "flat"; saveState(); render(); loadPreviews() end),
      ui.button({ key = "another", glyph = "arrows-shuffle", text = "Another", variant = "outline", controlSize = "sm", tooltip = "New random seed", onClick = function()
        seed = math.random(1, 999999)
        note = nil
        render()
        loadPreviews()
      end }),
    }),
    ui.column({ gap = 10 }, tileRows),
    ui.label({ text = "Soft blends the palette colors; Flat keeps only the palette colors.", color = "on_surface_variant", fontSize = 11 }),
  })

  local other = compact and "wallgen" or "wallgen-compact"
  local layoutButton = ui.button({ key = "layout", glyph = compact and "arrows-maximize" or "arrows-minimize", text = compact and "Wide" or "Compact", variant = "ghost", controlSize = "sm",
    tooltip = compact and "The wide layout with three columns" or "A narrower layout in tabs, for small screens",
    onClick = function() noctalia.runAsync({ "setsid", "-f", "sh", "-c", "noctalia msg panel-close; sleep 0.2; noctalia msg panel-open mabox/recolor:" .. other }) end })

  local actionRow = ui.row({ gap = 8, align = "center" }, {
      ui.button({ key = "gen" .. (busy and "1" or "0"), glyph = busy and "player-stop" or "sparkles", text = busy and "Stop" or "Generate", variant = busy and "destructive" or "primary", onClick = function() if busy then stopJob() else generate(false) end end }),
      ui.button({ key = "genset", glyph = "photo", text = "Generate and set as wallpaper", variant = "outline", enabled = not busy, onClick = function() generate(true) end }),
      ui.button({ key = "open", glyph = "folder-open", text = "Open folder", variant = "outline", tooltip = "Show the output folder in pcmanfm", onClick = function()
        noctalia.runAsync({ "sh", "-c", 'mkdir -p "$1" && exec pcmanfm "$1"', "sh", destDir() })
        panel.close()
      end }),
      ui.button({ key = "use", glyph = "photo-up", text = "Use folder as wallpapers", variant = "outline", tooltip = "Add the output folder to the wallpaper folders and start it", onClick = function()
        noctalia.runAsync({ "sh", "-c", USE, "sh", destDir() })
        panel.close()
      end }),
    })

  local body
  if compact then
    local tabs = {}
    for _, t in ipairs({ { "colors", "Colors" }, { "types", "Types and settings" }, { "output", "Size and output" } }) do
      table.insert(tabs, chip("tab" .. t[1], t[2], tab == t[1], function() tab = t[1]; render() end))
    end
    local page
    if tab == "colors" then
      page = ui.row({ key = "page-colors", gap = 10, align = "start" }, { ui.column({ gap = 10, width = 640 }, { palCard }) })
    elseif tab == "types" then
      page = ui.row({ key = "page-types", gap = 10, align = "start" }, {
        ui.column({ gap = 10, width = 866 }, { typeCard }),
        ui.column({ gap = 10, flexGrow = 1, minWidth = 300 }, { adjustCard }),
      })
    else
      page = ui.row({ key = "page-output", gap = 10, align = "start" }, {
        ui.column({ gap = 10, width = 460 }, { sizeCard }),
        ui.column({ gap = 10, flexGrow = 1, minWidth = 360 }, { outCard }),
      })
    end
    table.insert(tabs, ui.box({ flexGrow = 1, height = 1 }))
    table.insert(tabs, actionRow)
    body = ui.column({ key = "compact-body", gap = 10 }, { ui.row({ key = "tabs", gap = 6, align = "center" }, tabs), page })
  else
    body = ui.row({ key = "columns", gap = 10, align = "start" }, {
      ui.column({ key = "col-left", gap = 10, width = 450 }, { palCard }),
      ui.column({ key = "col-mid", gap = 10, width = 890 }, { typeCard }),
      ui.column({ key = "col-right", gap = 10, flexGrow = 1, minWidth = 340 }, { adjustCard, sizeCard, outCard }),
    })
  end

  panel.render(ui.column({ gap = 10, padding = 12 }, {
    ui.row({ gap = 8, align = "center" }, {
      logo(),
      ui.label({ text = "Wallgen" }),
      ui.label({ text = hotkey("mabox/recolor:" .. (compact and "wallgen-compact" or "wallgen")), color = "outline_variant", flexGrow = 1 }),
      layoutButton,
      switch(compact and "wallgen-compact" or "wallgen"),
      ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "Close", onClick = function() panel.close() end }),
    }),
    body,
    compact and ui.box({ height = 0 }) or actionRow,
    err and ui.label({ text = err, color = "error" }) or note and ui.label({ text = note, color = "primary", maxLines = 2 }) or ui.box({ height = 0 }),
  }))
end

local function onOpen()
  err = nil
  note = nil
  loadState()
  local picked = noctalia.readFile(dataFile("wg-out"))
  if picked and picked ~= "" then
    out = noctalia.string.trim(picked)
    gen += 1
    noctalia.writeFile(dataFile("wg-out"), "")
  end
  seed = math.random(1, 999999)
  saveState()
  render()
  noctalia.runAsync({ "sh", "-c", "pgrep -f 'mb-wallgen-jo[b]' >/dev/null && echo busy" }, function(r)
    if string.find(r.stdout or "", "busy", 1, true) and not busy then
      busy = true
      totalImages = 1
      watchJob()
    end
  end)
  applyPick()
  loadPalettes()
  loadColors()
  loadPreviews()
end

return onOpen
end
