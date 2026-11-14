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
local busy = false
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
end

-- Runs detached (setsid) so the dialog survives the panel closing; the pick goes to a file and the panel reopens.
local BROWSE = [[if [ "$3" != file ]; then
  p=$(yad --file --directory --center --width=1000 --height=650 --title="Recolor: folder" --filename="$1/") || p=
else
  p=$(yad --file --center --width=1000 --height=650 --title="Recolor: image" --filename="$1/" --file-filter="Images|*.png *.jpg *.jpeg *.webp *.bmp" --file-filter="All|*") || p=
fi
[ -n "$p" ] && readlink -f "$p" > "$2"
noctalia msg panel-close; noctalia msg panel-open mabox/recolor:main]]

-- kind: file or dir (source), out (output folder).
local function browse(kind)
  noctalia.mkdirAll(noctalia.pluginDataDir())
  local start = noctalia.getenv("HOME") .. "/Pictures"
  noctalia.runAsync({ "setsid", "-f", "sh", "-c", BROWSE, "sh", start, pickFile(kind == "out" and "out" or "src"), kind })
end

local function expand(t)
  t = noctalia.string.trim(t)
  return (string.gsub(t, "^~/", noctalia.getenv("HOME") .. "/"))
end

local function run()
  local path = expand(src)
  if busy or path == "" then
    err = path == "" and "Pick an image or a folder first" or err
    render()
    return
  end
  busy = true
  err = nil
  done = nil
  render()
  local argv = { "mb-recolor", "-m", mode, "-g", group }
  local dest = expand(out)
  if dest ~= "" then
    table.insert(argv, "-o")
    table.insert(argv, dest)
  end
  table.insert(argv, palette)
  table.insert(argv, path)
  noctalia.runAsync(argv, function(r)
    busy = false
    local n = 0
    local last = nil
    for line in string.gmatch((r.stdout or "") .. "\n", "([^\n]*)\n") do
      if line ~= "" then
        n = n + 1
        last = line
      end
    end
    outDir = last and string.match(last, "^(.*)/[^/]+$") or nil
    if n > 0 then
      done = n == 1 and "1 image written" or (n .. " images written")
      err = r.exitCode ~= 0 and "Some images failed" or nil
    else
      local msg = string.match(r.stderr or "", "([^\n]+)%s*$")
      err = msg or "Nothing written: check the path"
    end
    render()
  end)
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
    table.insert(grp, chip("g" .. g, g, g == group, function() group = g; done = nil; render() end))
  end
  local palRows = {}
  for i = 1, #pal, 2 do
    table.insert(palRows, ui.row({ key = "pr" .. i, gap = 6 }, { pal[i], pal[i + 1] or ui.box({ height = 0 }) }))
  end
  local grpRows = {}
  for i = 1, #grp, 3 do
    table.insert(grpRows, ui.row({ key = "gr" .. i, gap = 6 }, { grp[i], grp[i + 1] or ui.box({ height = 0 }), grp[i + 2] or ui.box({ height = 0 }) }))
  end

  panel.render(ui.column({ gap = 10, padding = 12 }, {
    ui.row({ gap = 8, align = "center" }, {
      logo(),
      ui.label({ text = "Recolor" }),
      ui.label({ text = hotkey("mabox/recolor:main"), color = "outline_variant", flexGrow = 1 }),
    }),
    ui.column(card("src"), {
      ui.label({ text = "Image or folder", fontWeight = "bold" }),
      ui.input({ key = "src", value = src, placeholder = "/path/to/image or folder", frameVisible = true, onChange = function(t) src = t end, onSubmit = run }),
      ui.row({ gap = 6 }, {
        ui.button({ key = "file", glyph = "photo", text = "Image", variant = "outline", controlSize = "sm", onClick = function() browse("file") end }),
        ui.button({ key = "dir", glyph = "folder-open", text = "Folder", variant = "outline", controlSize = "sm", onClick = function() browse("dir") end }),
      }),
    }),
    ui.column(card("out"), {
      ui.label({ text = "Output folder", fontWeight = "bold" }),
      ui.input({ key = "out", value = out, placeholder = "~/Pictures/" .. palette .. "/" .. group, frameVisible = true, onChange = function(t) out = t end, onSubmit = run }),
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
    }),
    ui.column(card("mode"), {
      ui.label({ text = "Look", fontWeight = "bold" }),
      ui.row({ gap = 6 }, {
        chip("clut", "Soft", mode == "clut", function() mode = "clut"; done = nil; render() end),
        chip("remap", "Hard", mode == "remap", function() mode = "remap"; done = nil; render() end),
        chip("smooth", "Smooth", mode == "smooth", function() mode = "smooth"; done = nil; render() end),
      }),
      ui.label({ text = mode == "clut" and "Brightness mapped over the palette; keeps gradients and detail."
        or mode == "remap" and "Every pixel becomes the nearest palette color; flat areas."
        or "Flat areas of palette colors with clean edges.", color = "on_surface_variant", fontSize = 11 }),
    }),
    ui.row({ gap = 8, align = "center" }, {
      ui.button({ key = "run", glyph = "wand", text = busy and "Working..." or "Recolor", variant = "primary", onClick = run }),
      done and ui.button({ key = "open", glyph = "folder-open", text = "Open folder", variant = "outline", onClick = function()
        if outDir then noctalia.runAsync({ "xdg-open", outDir }) end
      end }) or ui.box({ height = 0 }),
    }),
    err and ui.label({ text = err, color = "error" }) or done and ui.label({ text = done .. " in " .. (outDir or ""), color = "primary", maxLines = 2 }) or ui.box({ height = 0 }),
  }))
end

function onOpen()
  busy = false
  err = nil
  done = nil
  for name, set in pairs({ src = function(v) src = v end, out = function(v) out = v end }) do
    local picked = noctalia.readFile(pickFile(name))
    if picked and picked ~= "" then
      set(noctalia.string.trim(picked))
      noctalia.writeFile(pickFile(name), "")
    end
  end
  render()
  loadPalettes()
end
