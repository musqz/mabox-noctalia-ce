--!nonstrict
-- Color picker panel. History and palettes reuse colormenu's plain .clr files (one "#hex" per line).

local HOME = noctalia.getenv("HOME")
local RECENT = HOME .. "/.config/colormenu/recent.clr"
local DIRS = {
  Recent = nil,
  ["Built-in"] = "/usr/share/colormenu/palettes",
  Wallpaper = HOME .. "/.config/colormenu/palettes/wallp",
}
local PROFILES = { "Recent", "Built-in", "Wallpaper" }
local FORMATS = { "hex", "rgb", "rgba" }
local COLUMNS = 6
local MAX_RECENT = 50

local profile = "Recent"
local files = {}
local fileIndex = 1
local formatIndex = 1

local function formatPath()
  local dir = noctalia.pluginDataDir()
  return dir and (dir .. "/format") or nil
end

local function loadFormat()
  local path = formatPath()
  local raw = path and noctalia.readFile(path)
  if raw then
    raw = noctalia.string.trim(raw)
    for i, f in ipairs(FORMATS) do
      if f == raw then
        formatIndex = i
      end
    end
  end
end

local function parseClr(path)
  local out = {}
  local raw = noctalia.readFile(path)
  if not raw then
    return out
  end
  for line in string.gmatch(raw, "[^\r\n]+") do
    local hex = string.match(line, "^%s*(#%x%x%x%x%x%x)")
    if hex then
      table.insert(out, string.upper(hex))
    end
  end
  return out
end

local function listFiles(dir)
  local names = {}
  local entries = noctalia.listDir(dir)
  if entries then
    for _, name in entries do
      if string.match(name, "%.clr$") then
        table.insert(names, name)
      end
    end
    table.sort(names)
  end
  return names
end

local function cleanName(name)
  local base = string.gsub(name, "%.clr$", "")
  return (string.gsub(base, "%.%w+$", ""))
end

local function currentColors()
  if profile == "Recent" then
    return parseClr(RECENT)
  end
  local name = files[fileIndex]
  return name and parseClr(DIRS[profile] .. "/" .. name) or {}
end

local function format(hex)
  local f = FORMATS[formatIndex]
  if f == "hex" then
    return hex
  end
  local r = tonumber(string.sub(hex, 2, 3), 16)
  local g = tonumber(string.sub(hex, 4, 5), 16)
  local b = tonumber(string.sub(hex, 6, 7), 16)
  if f == "rgb" then
    return `rgb({r}, {g}, {b})`
  end
  return `rgba({r}, {g}, {b}, 1)`
end

local function textOn(hex)
  local r = tonumber(string.sub(hex, 2, 3), 16)
  local g = tonumber(string.sub(hex, 4, 5), 16)
  local b = tonumber(string.sub(hex, 6, 7), 16)
  return (r * 299 + g * 587 + b * 114) / 1000 > 140 and "#000000" or "#FFFFFF"
end

local function addRecent(hex)
  local list = { hex }
  for _, c in ipairs(parseClr(RECENT)) do
    if c ~= hex and #list < MAX_RECENT then
      table.insert(list, c)
    end
  end
  local lines = {}
  for _, c in ipairs(list) do
    table.insert(lines, c .. " ")
  end
  noctalia.mkdirAll(HOME .. "/.config/colormenu")
  noctalia.writeFile(RECENT, table.concat(lines, "\n") .. "\n")
end

local render

local function copy(hex)
  local text = format(hex)
  noctalia.copyToClipboard(text, "text/plain")
  noctalia.notify("Color copied", text)
end

local function setProfile(name)
  profile = name
  fileIndex = 1
  files = DIRS[name] and listFiles(DIRS[name]) or {}
  render()
end

local function pickFromScreen()
  panel.close()
  noctalia.runAsync({ "mb-colorpick" }, function(result)
    if result.exitCode == 0 then
      local hex = string.match(result.stdout, "#%x%x%x%x%x%x")
      if hex then
        addRecent(hex)
        copy(hex)
      end
    end
    noctalia.runAsync({ "noctalia", "msg", "panel-toggle", "musqz/colors:picker" })
  end)
end

local function addFromSelector()
  noctalia.openColorPicker("#FFFFFF", function(color)
    if color ~= nil then
      addRecent(string.upper(color))
      profile = "Recent"
      files = {}
      copy(string.upper(color))
      render()
    end
  end)
end

local function clearRecent()
  noctalia.writeFile(RECENT, "")
  render()
end

local function grid(colors)
  local rows = {}
  local i = 1
  while i <= #colors do
    local cells = {}
    for c = 0, COLUMNS - 1 do
      local hex = colors[i + c]
      if hex then
        table.insert(cells, ui.column({ gap = 2, flexGrow = 1, key = `c{i + c}` }, {
          ui.box({ fill = hex, radius = 6, height = 44, tooltip = format(hex), onClick = function() copy(hex) end }),
          ui.label({ text = hex, fontSize = 11, color = "on_surface_variant", textAlign = "center" }),
        }))
      else
        table.insert(cells, ui.spacer({ flexGrow = 1 }))
      end
    end
    table.insert(rows, ui.row({ gap = 8, key = `r{i}` }, cells))
    i += COLUMNS
  end
  if #rows == 0 then
    table.insert(rows, ui.label({ text = "No colors", color = "on_surface_variant" }))
  end
  return rows
end

render = function()
  local profileButtons = {}
  for _, name in ipairs(PROFILES) do
    table.insert(profileButtons, ui.button({
      key = "p" .. name,
      text = name,
      variant = name == profile and "primary" or "ghost",
      contentAlign = "start",
      onClick = function() setProfile(name) end,
    }))
  end
  if profile == "Recent" then
    table.insert(profileButtons, ui.separator({ spacing = 4 }))
    table.insert(profileButtons, ui.button({ text = "Clear recent", glyph = "trash", variant = "ghost", contentAlign = "start", onClick = clearRecent }))
  end

  local right = {}
  if profile ~= "Recent" then
    local names = {}
    for _, f in ipairs(files) do
      table.insert(names, cleanName(f))
    end
    table.insert(right, ui.select({
      key = "files" .. profile,
      options = names,
      selectedIndex = fileIndex - 1,
      onChange = function(idx)
        fileIndex = tonumber(idx) + 1
        render()
      end,
    }))
  end
  table.insert(right, ui.scroll({ gap = 8, flexGrow = 1, key = "grid" .. profile .. fileIndex }, grid(currentColors())))

  panel.render(ui.column({ gap = 10, padding = 12, height = 520 }, {
    ui.row({ gap = 8, align = "center" }, {
      ui.button({ text = "Pick from screen", glyph = "color-picker", variant = "primary", onClick = pickFromScreen }),
      ui.button({ text = "Add from selector", glyph = "palette", onClick = addFromSelector }),
      ui.spacer({ flexGrow = 1 }),
      ui.label({ text = "Copy as", color = "on_surface_variant" }),
      ui.select({
        key = "format",
        options = FORMATS,
        selectedIndex = formatIndex - 1,
        width = 100,
        onChange = function(idx)
          formatIndex = tonumber(idx) + 1
          local path = formatPath()
          if path then
            noctalia.writeFile(path, FORMATS[formatIndex])
          end
          render()
        end,
      }),
    }),
    ui.row({ gap = 12, flexGrow = 1 }, {
      ui.column({ gap = 4, width = 160 }, profileButtons),
      ui.column({ gap = 8, flexGrow = 1 }, right),
    }),
  }))
end

function onOpen()
  loadFormat()
  setProfile(profile)
end
