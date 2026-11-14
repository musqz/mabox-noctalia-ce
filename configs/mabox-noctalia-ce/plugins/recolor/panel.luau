--!nonstrict
-- Recolor: front end for mb-recolor (image or folder to a palette).
local logo = require("./lib/celogo.luau")
local hotkey = require("./lib/hotkey.luau")

local function card(key)
  return { key = key, fill = "surface_variant", radius = 10, padding = 12, gap = 10, border = "primary", borderWidth = 1 }
end

local palettes = {}
local palette = "nord"
local group = "all"
local mode = "clut"
local src = ""
local out = ""
local gen = 0
local running = false
local swatches = {}
local colGen = 0
local previews = {}
local pvGen = 0
local pvName = nil
local pvDir = false
local err = nil
local done = nil
local outDir = nil
local render

local function pickFile(name)
  return noctalia.pluginDataDir() .. "/" .. name
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
    end
    render()
  end)
end

local function expand(t)
  t = noctalia.string.trim(t)
  return (string.gsub(t, "^~/", noctalia.getenv("HOME") .. "/"))
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
  if [ "$5" = 1 ]; then src=$(printf '%s\n' "$list" | shuf -n1); else src=$(printf '%s\n' "$list" | sort | head -n1); fi
fi
[ -f "$src" ] || exit 1
rm -rf "$1"; mkdir -p "$1"
magick "$src" -resize 400x "$1/in.png" || exit 1
for m in clut remap smooth; do mb-recolor -m "$m" -g "$3" -o "$1/$m" "$2" "$1/in.png" >/dev/null 2>&1 & done
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
  noctalia.runAsync({ "sh", "-c", PREVIEW, "sh", base .. "/" .. mine, palette, group, path, random and "1" or "0" }, function(r)
    if mine ~= pvGen then
      return
    end
    previews = {}
    pvName = nil
    pvDir = false
    for line in string.gmatch(r.stdout or "", "[^\n]+") do
      local file = string.match(line, "^src=(.+)$")
      if file then
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
  local ok = false
  for _, g in ipairs(groupsOf(name)) do
    ok = ok or g == group
  end
  if not ok then
    group = "all"
  end
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
local RUN = [[log=$(mktemp)
trap 'rm -f "$log" "$log.err"; exit 1' TERM
mb-recolor -m "$1" -g "$2" -o "$3" "$4" "$5" > "$log" 2> "$log.err"
n=$(wc -l < "$log"); f=$(grep -c '^failed' "$log.err")
if [ "$n" -gt 0 ]; then
  [ "$f" -gt 0 ] && x=" ($f failed)" || x=
  notify-send -a Recolor "Recolor" "$n images written to $3$x"
else
  notify-send -a Recolor -u critical "Recolor failed" "$(tail -n1 "$log.err")"
fi
rm -f "$log" "$log.err"]]

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
  local dest = expand(out)
  if dest == "" then
    dest = noctalia.getenv("HOME") .. "/Pictures/" .. palette .. "/" .. group
  end
  table.insert(argv, dest)
  table.insert(argv, palette)
  table.insert(argv, path)
  outDir = dest
  noctalia.runAsync(argv)
  running = true
  done = "Running: a notification follows when it is finished"
  render()
end

local function chip(key, text, on, onClick)
  return ui.button({ key = key, text = text, glyph = on and "check" or nil, variant = on and "primary" or "outline", controlSize = "sm", onClick = onClick })
end

function render()
  local pal = {}
  for _, p in ipairs(palettes) do
    table.insert(pal, chip("p" .. p.name, p.name, p.name == palette, function() choosePalette(p.name) end))
  end
  local grp = {}
  for _, g in ipairs(groupsOf(palette)) do
    table.insert(grp, chip("g" .. g, g, g == group, function() group = g; done = nil; render(); loadColors(); loadPreviews() end))
  end
  local palRows = {}
  for i = 1, #pal, 2 do
    table.insert(palRows, ui.row({ key = "pr" .. i, gap = 6 }, { pal[i], pal[i + 1] or ui.box({ height = 0 }) }))
  end
  local grpRows = {}
  for i = 1, #grp, 3 do
    table.insert(grpRows, ui.row({ key = "gr" .. i, gap = 6 }, { grp[i], grp[i + 1] or ui.box({ height = 0 }), grp[i + 2] or ui.box({ height = 0 }) }))
  end

  local swatchBoxes = {}
  for i, c in ipairs(swatches) do
    table.insert(swatchBoxes, ui.box({ key = "sw" .. i, fill = c, flexGrow = 1, height = 26, radius = 3, tooltip = c }))
  end
  if #swatchBoxes == 0 then
    table.insert(swatchBoxes, ui.box({ key = "sw0", height = 26 }))
  end

  local lookCols = {}
  for _, l in ipairs({ { "clut", "Soft" }, { "remap", "Hard" }, { "smooth", "Smooth" } }) do
    local m, label = l[1], l[2]
    local pick = function() mode = m; done = nil; render() end
    local thumb = previews[m] and ui.image({ key = "pv" .. m .. pvGen, path = previews[m], width = 116, height = 68, radius = 6, fit = "cover", border = m == mode and "primary" or "on_surface_variant", borderWidth = m == mode and 3 or 1, onClick = pick })
      or ui.box({ key = "pvb" .. m, fill = "surface", width = 116, height = 68, radius = 6, border = m == mode and "primary" or "on_surface_variant", borderWidth = m == mode and 3 or 1, onClick = pick })
    table.insert(lookCols, ui.column({ key = "look" .. m, gap = 6, align = "center" }, { thumb, chip(m, label, m == mode, pick) }))
  end

  panel.render(ui.column({ gap = 10, padding = 12 }, {
    ui.row({ gap = 8, align = "center" }, {
      logo(),
      ui.label({ text = "Recolor" }),
      ui.label({ text = hotkey("mabox/recolor:main"), color = "outline_variant", flexGrow = 1 }),
    }),
    ui.column(card("src"), {
      ui.label({ text = "Image or folder", fontWeight = "bold" }),
      ui.input({ key = "src" .. gen, value = src, placeholder = "/path/to/image or folder", frameVisible = true, onChange = function(t) src = t end, onSubmit = function() loadPreviews() end }),
      ui.row({ gap = 6 }, {
        ui.button({ key = "file", glyph = "photo", text = "Image", variant = "outline", controlSize = "sm", onClick = function() browse("file") end }),
        ui.button({ key = "dir", glyph = "folder-open", text = "Folder", variant = "outline", controlSize = "sm", onClick = function() browse("dir") end }),
      }),
    }),
    ui.column(card("out"), {
      ui.label({ text = "Output folder", fontWeight = "bold" }),
      ui.input({ key = "out" .. gen, value = out, placeholder = "~/Pictures/" .. palette .. "/" .. group, frameVisible = true, onChange = function(t) out = t end, onSubmit = run }),
      ui.row({ gap = 6 }, {
        ui.button({ key = "outdir", glyph = "folder-open", text = "Folder", variant = "outline", controlSize = "sm", onClick = function() browse("out") end }),
        ui.button({ key = "outclear", glyph = "x", text = "Default", variant = "ghost", controlSize = "sm", onClick = function() out = ""; render() end }),
      }),
    }),
    ui.column(card("pal"), {
      ui.label({ text = "Palette", fontWeight = "bold" }),
      ui.column({ gap = 6 }, palRows),
      ui.label({ text = "Colors", fontWeight = "bold" }),
      ui.column({ gap = 6 }, grpRows),
      ui.row({ key = "sw", gap = 2 }, swatchBoxes),
    }),
    ui.column(card("mode"), {
      ui.row({ gap = 8, align = "center" }, {
        ui.label({ text = "Look", fontWeight = "bold" }),
        ui.label({ text = pvName or "", color = "outline_variant", fontSize = 11, maxLines = 1, flexGrow = 1 }),
        pvDir and ui.button({ key = "shuffle", glyph = "arrows-shuffle", text = "Another", variant = "outline", controlSize = "sm", tooltip = "Preview another image from the folder", onClick = function() loadPreviews(true) end }) or ui.box({ height = 0 }),
      }),
      ui.row({ gap = 8 }, lookCols),
      ui.label({ text = mode == "clut" and "Brightness mapped over the palette; keeps gradients and detail."
        or mode == "remap" and "Every pixel becomes the nearest palette color; flat areas."
        or "Flat areas of palette colors with clean edges.", color = "on_surface_variant", fontSize = 11 }),
    }),
    ui.row({ gap = 8, align = "center" }, {
      ui.button({ key = "run", glyph = running and "player-stop" or "wand", text = running and "Stop" or "Recolor", variant = running and "destructive" or "primary", onClick = run }),
      done and not running and ui.button({ key = "open", glyph = "folder-open", text = "Open folder", variant = "outline", onClick = function()
        if outDir then noctalia.runAsync({ "xdg-open", outDir }) end
      end }) or ui.box({ height = 0 }),
    }),
    err and ui.label({ text = err, color = "error" }) or done and ui.label({ text = done .. " in " .. (outDir or ""), color = "primary", maxLines = 2 }) or ui.box({ height = 0 }),
  }))
end

function onOpen()
  err = nil
  done = nil
  for name, set in pairs({ src = function(v) src = v end, out = function(v) out = v end }) do
    local picked = noctalia.readFile(pickFile(name))
    if picked and picked ~= "" then
      set(noctalia.string.trim(picked))
      gen = gen + 1
      noctalia.writeFile(pickFile(name), "")
    end
  end
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
  end
end
