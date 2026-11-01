--!nonstrict
-- Color picker panel. History and palettes reuse colormenu's plain .clr files (one "#hex" per line).

return function(pinned)
local HOME = noctalia.getenv("HOME")
local RECENT = HOME .. "/.config/colormenu/recent.clr"
local MY = HOME .. "/.config/colormenu/palettes/my"
local DIRS = {
  Recent = nil,
  ["My palettes"] = MY,
  ["Built-in"] = "/usr/share/colormenu/palettes",
  Wallpaper = HOME .. "/.config/colormenu/palettes/wallp",
}
local PROFILES = { "Recent", "My palettes", "Built-in", "Wallpaper" }
local FORMATS = { "hex", "rgb", "rgba" }
local COLUMNS = pinned and 3 or 6
local MAX_RECENT = 50

local profile = "Recent"
local files = {}
local fileIndex = 1
local formatIndex = 1
local ACTIONS = { "copy", "paste" }
local actionIndex = 1
local newName = ""
local nameNonce = 0
local editMode = false
local targetIndex = 1

local function dataPath(name)
  local dir = noctalia.pluginDataDir()
  return dir and (dir .. "/" .. name) or nil
end

local function loadChoice(name, list, current)
  local path = dataPath(name)
  local raw = path and noctalia.readFile(path)
  if raw then
    raw = noctalia.string.trim(raw)
    for i, v in ipairs(list) do
      if v == raw then
        return i
      end
    end
  end
  return current
end

local function saveChoice(name, value)
  local path = dataPath(name)
  if path then
    noctalia.writeFile(path, value)
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

-- Persistent panels cannot host ui.select, so the pinned window cycles with < > buttons.
local function chooser(key, options, index, width, onPick)
  if not pinned then
    return ui.select({ key = key, options = options, selectedIndex = index - 1, width = width, placeholder = "Add to palette", onChange = function(idx) onPick(tonumber(idx) + 1) end })
  end
  local n = #options
  local function step(d)
    if n > 0 then
      onPick((index - 1 + d) % n + 1)
    end
  end
  return ui.row({ key = key, gap = 4, align = "center", width = width }, {
    ui.button({ glyph = "chevron-left", variant = "ghost", controlSize = "sm", onClick = function() step(-1) end }),
    ui.label({ text = options[index] or "-", maxLines = 1, flexGrow = 1, textAlign = "center" }),
    ui.button({ glyph = "chevron-right", variant = "ghost", controlSize = "sm", onClick = function() step(1) end }),
  })
end

local function pasting()
  return ACTIONS[actionIndex] == "paste"
end

-- Types the color into the previously focused window once the panel has released focus.
local function copy(hex)
  local text = format(hex)
  noctalia.copyToClipboard(text, "text/plain")
  if pasting() then
    if not pinned then
      panel.close()
    end
    noctalia.runAsync({ "sh", "-c", 'sleep 0.3; exec wtype -- "$1"', "sh", text })
  else
    noctalia.notify("Color copied", text)
  end
end

local function setProfile(name, select)
  profile = name
  fileIndex = 1
  files = DIRS[name] and listFiles(DIRS[name]) or {}
  for i, f in ipairs(files) do
    if f == select then
      fileIndex = i
    end
  end
  render()
end

local function writeClr(path, colors)
  local lines = {}
  for _, c in ipairs(colors) do
    table.insert(lines, c .. " ")
  end
  noctalia.mkdirAll(MY)
  noctalia.writeFile(path, #lines > 0 and (table.concat(lines, "\n") .. "\n") or "")
end

-- Creates MY/<name>.clr from the given colors, then shows it.
local function createPalette(colors)
  local name = noctalia.string.trim((string.gsub(newName, "[^%w _%-]", "")))
  if name == "" and pinned then
    name = "palette-" .. noctalia.formatTime("%H%M%S")
  end
  if name == "" then
    noctalia.notify("Colors", "Enter a palette name")
    return
  end
  local path = MY .. "/" .. name .. ".clr"
  if noctalia.fileExists(path) then
    noctalia.notify("Colors", name .. " already exists")
    return
  end
  writeClr(path, colors)
  newName = ""
  nameNonce += 1
  setProfile("My palettes", name .. ".clr")
end

local function renamePalette()
  local old = files[fileIndex]
  local name = noctalia.string.trim((string.gsub(newName, "[^%w _%-]", "")))
  if profile ~= "My palettes" or not old then
    return
  end
  if name == "" then
    noctalia.notify("Colors", "Enter the new name first")
    return
  end
  local path = MY .. "/" .. name .. ".clr"
  if noctalia.fileExists(path) then
    noctalia.notify("Colors", name .. " already exists")
    return
  end
  noctalia.renameFile(MY .. "/" .. old, path)
  newName = ""
  nameNonce += 1
  setProfile("My palettes", name .. ".clr")
end

local function deletePalette()
  local name = files[fileIndex]
  if profile == "My palettes" and name then
    noctalia.removeFile(MY .. "/" .. name)
    setProfile("My palettes")
  end
end

-- A pick also lands in the selected custom palette.
local function addColor(hex)
  addRecent(hex)
  local name = profile == "My palettes" and files[fileIndex]
  if name then
    local colors = parseClr(MY .. "/" .. name)
    table.insert(colors, hex)
    writeClr(MY .. "/" .. name, colors)
  end
end

local function pickFromScreen()
  if not pinned then
    panel.close()
  end
  noctalia.runAsync({ "mb-colorpick" }, function(result)
    if result.exitCode == 0 then
      local hex = string.match(result.stdout, "#%x%x%x%x%x%x")
      if hex then
        addColor(hex)
        copy(hex)
      end
    end
    if not pinned and not pasting() then
      noctalia.runAsync({ "noctalia", "msg", "panel-toggle", "mabox/colors:picker" })
    end
  end)
end

local function addFromSelector()
  noctalia.openColorPicker("#FFFFFF", function(color)
    if color ~= nil then
      addColor(string.upper(color))
      copy(string.upper(color))
      render()
    end
  end)
end

local function clearRecent()
  noctalia.writeFile(RECENT, "")
  render()
end

-- Edit mode: a swatch click removes it from the open custom palette, or adds it to the "Add to" palette.
local function editSwatch(hex, position)
  if profile == "My palettes" then
    local name = files[fileIndex]
    if name then
      local colors = parseClr(MY .. "/" .. name)
      table.remove(colors, position)
      writeClr(MY .. "/" .. name, colors)
      render()
    end
    return
  end
  local target = listFiles(MY)[targetIndex]
  if not target then
    noctalia.notify("Colors", "Create a palette first (My palettes)")
    return
  end
  local colors = parseClr(MY .. "/" .. target)
  for _, c in ipairs(colors) do
    if c == hex then
      return
    end
  end
  table.insert(colors, hex)
  writeClr(MY .. "/" .. target, colors)
  noctalia.notify("Added " .. hex, cleanName(target))
end

local function grid(colors)
  local rows = {}
  local i = 1
  while i <= #colors do
    local cells = {}
    for c = 0, COLUMNS - 1 do
      local hex = colors[i + c]
      local position = i + c
      if hex then
        table.insert(cells, ui.column({ gap = 2, flexGrow = 1, key = `c{position}` }, {
          ui.box({ fill = hex, radius = 6, height = 44, tooltip = editMode and (profile == "My palettes" and "Remove" or "Add to palette") or format(hex), onClick = function()
            if editMode then
              editSwatch(hex, position)
            else
              copy(hex)
            end
          end }),
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
  if (profile == "Recent" or profile == "My palettes") and not pinned then
    table.insert(profileButtons, ui.separator({ spacing = 4 }))
    table.insert(profileButtons, ui.input({
      key = "newname" .. nameNonce,
      value = newName,
      placeholder = "palette name",
      controlSize = "sm",
      onChange = function(text) newName = text end,
    }))
  end
  do
    table.insert(profileButtons, ui.separator({ spacing = 4 }))
    table.insert(profileButtons, ui.button({
      text = "Edit palettes",
      glyph = "edit",
      variant = editMode and "primary" or "ghost",
      contentAlign = "start",
      onClick = function()
        editMode = not editMode
        render()
      end,
    }))
  end
  if profile == "Recent" then
    table.insert(profileButtons, ui.button({ text = "Save as palette", glyph = "device-floppy", variant = "ghost", contentAlign = "start", onClick = function() createPalette(parseClr(RECENT)) end }))
    table.insert(profileButtons, ui.button({ text = "Clear recent", glyph = "trash", variant = "ghost", contentAlign = "start", onClick = clearRecent }))
  elseif profile == "My palettes" then
    table.insert(profileButtons, ui.button({ text = "New palette", glyph = "plus", variant = "ghost", contentAlign = "start", onClick = function() createPalette({}) end }))
    table.insert(profileButtons, ui.button({ text = "Rename palette", glyph = "pencil", variant = "ghost", contentAlign = "start", onClick = renamePalette }))
    table.insert(profileButtons, ui.button({ text = "Delete palette", glyph = "trash", variant = "ghost", contentAlign = "start", onClick = deletePalette }))
  end

  local right = {}
  if profile ~= "Recent" then
    local names = {}
    for _, f in ipairs(files) do
      table.insert(names, cleanName(f))
    end
    table.insert(right, chooser("files" .. profile, names, fileIndex, nil, function(i)
      fileIndex = i
      render()
    end))
  end
  if editMode and profile ~= "My palettes" then
    local mine = {}
    for _, f in ipairs(listFiles(MY)) do
      table.insert(mine, cleanName(f))
    end
    table.insert(right, chooser("target", mine, targetIndex, nil, function(i)
      targetIndex = i
      render()
    end))
  end
  table.insert(right, ui.scroll({ gap = 8, flexGrow = 1, key = "grid" .. profile .. fileIndex }, grid(currentColors())))

  if pinned then
    local profileIndex = 1
    for i, name in ipairs(PROFILES) do
      if name == profile then
        profileIndex = i
      end
    end
    local tools = {
      ui.button({
        glyph = "edit",
        text = "Edit",
        variant = editMode and "primary" or "ghost",
        controlSize = "sm",
        onClick = function()
          editMode = not editMode
          render()
        end,
      }),
    }
    if profile == "Recent" then
      table.insert(tools, ui.button({ glyph = "device-floppy", text = "Save", tooltip = "Save recent as palette", variant = "ghost", controlSize = "sm", onClick = function() createPalette(parseClr(RECENT)) end }))
      table.insert(tools, ui.button({ glyph = "trash", text = "Clear", tooltip = "Clear recent", variant = "ghost", controlSize = "sm", onClick = clearRecent }))
    elseif profile == "My palettes" then
      table.insert(tools, ui.button({ glyph = "plus", text = "New", tooltip = "New palette", variant = "ghost", controlSize = "sm", onClick = function() createPalette({}) end }))
      table.insert(tools, ui.button({ glyph = "trash", text = "Delete", tooltip = "Delete palette", variant = "ghost", controlSize = "sm", onClick = deletePalette }))
    end
    local body = {
      ui.row({ gap = 6, align = "center" }, {
        ui.button({ glyph = "color-picker", text = "Pick", variant = "primary", controlSize = "sm", tooltip = "Pick from screen", onClick = pickFromScreen }),
        ui.button({ glyph = "palette", text = "Select", variant = "ghost", controlSize = "sm", tooltip = "Add from selector", onClick = addFromSelector }),
        ui.spacer({ flexGrow = 1 }),
        ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "Close", onClick = function() panel.close() end }),
      }),
      ui.row({ gap = 6, align = "center" }, {
        chooser("action", ACTIONS, actionIndex, 130, function(i)
          actionIndex = i
          saveChoice("action", ACTIONS[actionIndex])
          render()
        end),
        chooser("format", FORMATS, formatIndex, 130, function(i)
          formatIndex = i
          saveChoice("format", FORMATS[formatIndex])
          render()
        end),
      }),
      chooser("profile", PROFILES, profileIndex, nil, function(i) setProfile(PROFILES[i]) end),
    }
    for _, node in ipairs(right) do
      table.insert(body, node)
    end
    table.insert(body, ui.row({ gap = 4 }, tools))
    panel.render(ui.column({ gap = 8, padding = 10 }, body))
    return
  end

  panel.render(ui.column({ gap = 10, padding = 12, height = 520 }, {
    ui.row({ gap = 8, align = "center" }, {
      ui.button({ text = "Pick from screen", glyph = "color-picker", variant = "primary", onClick = pickFromScreen }),
      ui.button({ text = "Add from selector", glyph = "palette", onClick = addFromSelector }),
      ui.spacer({ flexGrow = 1 }),
      chooser("action", ACTIONS, actionIndex, 120, function(i)
        actionIndex = i
        saveChoice("action", ACTIONS[actionIndex])
        render()
      end),
      ui.label({ text = "as", color = "on_surface_variant" }),
      chooser("format", FORMATS, formatIndex, 120, function(i)
        formatIndex = i
        saveChoice("format", FORMATS[formatIndex])
        render()
      end),
      pinned and ui.button({ glyph = "x", variant = "ghost", tooltip = "Close", onClick = function() panel.close() end })
        or ui.button({ glyph = "pin", variant = "ghost", tooltip = "Pin window", onClick = function()
          panel.close()
          noctalia.runAsync({ "noctalia", "msg", "panel-toggle", "mabox/colors:pinned" })
        end }),
    }),
    ui.row({ gap = 12, flexGrow = 1 }, {
      ui.column({ gap = 4, width = 160 }, profileButtons),
      ui.column({ gap = 8, flexGrow = 1 }, right),
    }),
  }))
end

return function()
  editMode = false
  formatIndex = loadChoice("format", FORMATS, formatIndex)
  actionIndex = loadChoice("action", ACTIONS, actionIndex)
  setProfile(profile)
end
end
