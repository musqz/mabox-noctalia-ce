--!nonstrict
-- Color picker panel. History and palettes reuse colormenu's plain .clr files (one "#hex" per line).

local pinSide = require("./side.luau")
local kbd = require("./kbd.luau")

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
local PROFILES = { "Recent", "My palettes", "Built-in", "Wallpaper", "Settings" }
local FORMATS = { "hex", "rgb", "rgba" }
local COLUMNS = pinned and 3 or 6
local MAX_RECENT = 50

-- Sidebar buttons and swatches sit side by side, so each counts its own rows from the top bar.
local sideRow = 1
local function stop(id, row, col, action)
  kbd.stop(id, row, col, action)
end

-- Cursor marker: a thick high-contrast frame around the element; border props are always sent (retained widgets).
local function ring(id, child, props)
  props = props or {}
  props.key = "k-" .. id
  props.padding = 3
  props.radius = 8
  props.border = "on_surface"
  props.borderWidth = kbd.sel(id) and 3 or 0
  return ui.column(props, { child })
end
local rightRow = 2

local profile = "Recent"
local files = {}
local fileIndex = 1
local formatIndex = 1
local ACTIONS = { "copy", "paste" }
local actionIndex = 1
local newName = ""
local nameNonce = 0
local DEFAULT_SAVE_DIR = HOME .. "/.config/mabox-noctalia-ce/color-palettes"
local saveDirText = ""

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
-- Attached: row/col make the dropdown a keyboard stop; alt+enter picks the next option.
local function chooser(key, options, index, width, onPick, row, col)
  local n = #options
  local function step(d)
    if n > 0 then
      onPick((index - 1 + d) % n + 1)
    end
  end
  if not pinned then
    if row then
      stop(key, row, col, function() step(1) end)
    end
    return ring(key, ui.select({ key = key, options = options, selectedIndex = index - 1, width = width, placeholder = "Add to palette", onChange = function(idx) onPick(tonumber(idx) + 1) end }))
  end
  local function prev() step(-1) end
  local function next() step(1) end
  stop(key .. "<", row, col, prev)
  stop(key .. ">", row, col + 1, next)
  return ui.row({ key = key, gap = 4, align = "center", width = width }, {
    ring(key .. "<", ui.button({ glyph = "chevron-left", variant = "ghost", controlSize = "sm", onClick = prev })),
    ui.label({ text = options[index] or "-", maxLines = 1, flexGrow = 1, textAlign = "center" }),
    ring(key .. ">", ui.button({ glyph = "chevron-right", variant = "ghost", controlSize = "sm", onClick = next })),
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
    -- A clicked pinned window holds keyboard focus too: close it for the typing and reopen it.
    pinSide.close("colors", pinned)
    local reopen = pinned and pinSide.reopenCmd("colors") or ""
    noctalia.runAsync({ "sh", "-c", 'sleep 0.3; wtype -- "$1"; [ -z "$2" ] || sleep 0.2; [ -z "$2" ] || sh -c "$2"', "sh", text, reopen })
  else
    noctalia.notify("Color copied", text)
  end
end

local function setProfile(name, select)
  kbd.clear()
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

local function saveDir()
  local dir = noctalia.string.trim(saveDirText)
  if dir == "" then
    return DEFAULT_SAVE_DIR
  end
  return (string.gsub(dir, "^~", HOME))
end

-- Writes the shown palette as NAME.txt, one #hex per line, in the save folder.
local function saveList()
  local colors = currentColors()
  if #colors == 0 then
    noctalia.notify("Colors", "No colors to save")
    return
  end
  local name = profile == "Recent" and "recent" or cleanName(files[fileIndex] or "palette")
  local dir = saveDir()
  noctalia.mkdirAll(dir)
  noctalia.writeFile(dir .. "/" .. name .. ".txt", table.concat(colors, "\n") .. "\n")
  noctalia.notify("Saved " .. #colors .. " colors", dir .. "/" .. name .. ".txt")
end

local function openSaveDir()
  local dir = saveDir()
  noctalia.mkdirAll(dir)
  noctalia.runAsync({ "setsid", "-f", "xdg-open", dir })
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

local function grid(colors)
  local rows = {}
  local i = 1
  while i <= #colors do
    local cells = {}
    for c = 0, COLUMNS - 1 do
      local hex = colors[i + c]
      local position = i + c
      if hex then
        local function pick()
          copy(hex)
        end
        stop(`c{position}`, rightRow + (i - 1) // COLUMNS, 2 + c, pick)
        table.insert(cells, ui.column({ gap = 2, flexGrow = 1, key = `c{position}`, padding = 3, radius = 8, border = "on_surface", borderWidth = kbd.sel(`c{position}`) and 3 or 0 }, {
          ui.box({ fill = hex, radius = 6, height = 44, tooltip = format(hex), onClick = pick }),
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

-- Side button: registers the stop and carries the cursor highlight.
local function sideButton(id, props)
  sideRow += 1
  if not pinned then
    stop(id, sideRow, 1, props.onClick)
  end
  props.key = id
  props.variant = props.variant or "ghost"
  props.contentAlign = "start"
  props.controlSize = "sm"
  return ring(id, ui.button(props))
end

render = function()
  kbd.begin()
  sideRow = 1
  -- Pinned: rows 1-3 are the top bar, action/format and profile; the choosers and grid follow.
  rightRow = pinned and 4 or 2
  stop("pick", 1, 1, pickFromScreen)
  stop("select", 1, 2, addFromSelector)
  if pinned then
    stop("close", 1, 3, function() pinSide.close("colors", pinned) end)
  else
    stop("pin", 1, 5, function()
      panel.close()
      pinSide.toggle("colors")
    end)
  end
  local profileButtons = {}
  for _, name in ipairs(PROFILES) do
    table.insert(profileButtons, sideButton("p" .. name, {
      text = name,
      variant = name == profile and "primary" or "ghost",
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
  if profile ~= "Settings" then
    table.insert(profileButtons, sideButton("list", { text = "Save as text", glyph = "file-text", onClick = saveList }))
  end
  table.insert(profileButtons, sideButton("folder", { text = "Open text folder", glyph = "folder-open", onClick = openSaveDir }))
  if profile == "Recent" then
    table.insert(profileButtons, sideButton("clear", { text = "Clear recent", glyph = "trash", onClick = clearRecent }))
  elseif profile == "My palettes" then
    table.insert(profileButtons, sideButton("new", { text = "New palette", glyph = "plus", onClick = function() createPalette({}) end }))
    table.insert(profileButtons, sideButton("rename", { text = "Rename palette", glyph = "pencil", onClick = renamePalette }))
    table.insert(profileButtons, sideButton("delete", { text = "Delete palette", glyph = "trash", onClick = deletePalette }))
  end

  local right = {}
  if profile == "Settings" then
    table.insert(right, ui.label({ text = "Save text files in", fontSize = 12, color = "on_surface_variant" }))
    if pinned then
      table.insert(right, ui.label({ text = saveDir(), fontSize = 12 }))
      table.insert(right, ui.label({ text = "Change the folder in the panel.", fontSize = 11, color = "on_surface_variant" }))
    else
      table.insert(right, ui.input({ key = "savedir", value = saveDirText, placeholder = DEFAULT_SAVE_DIR, onChange = function(text)
        saveDirText = text
        saveChoice("savedir", text)
      end }))
      table.insert(right, ui.label({ text = "Save as text writes NAME.txt with one color code per line.", fontSize = 11, color = "on_surface_variant" }))
    end
  end
  if profile ~= "Recent" and profile ~= "Settings" then
    local names = {}
    for _, f in ipairs(files) do
      table.insert(names, cleanName(f))
    end
    table.insert(right, chooser("files" .. profile, names, fileIndex, nil, function(i)
      if not kbd.sel("files" .. profile) and not kbd.sel("files" .. profile .. "<") and not kbd.sel("files" .. profile .. ">") then
        kbd.clear()
      end
      fileIndex = i
      render()
    end, rightRow, 2))
    rightRow += 1
  end
  -- Build the grid first: it registers the swatch stops that reveal() looks up.
  if profile ~= "Settings" then
    local swatches = grid(currentColors())
    table.insert(right, ui.scroll({ gap = 8, flexGrow = 1, key = "grid" .. profile .. fileIndex, revealKey = string.match(kbd.reveal() or "", "^c%d+$") }, swatches))
  end

  if pinned then
    local profileIndex = 1
    for i, name in ipairs(PROFILES) do
      if name == profile then
        profileIndex = i
      end
    end
    -- Rows after the grid; the grid has at least one row.
    local toolsRow = rightRow + math.max(1, math.ceil(#currentColors() / COLUMNS))
    local toolCol = 0
    local function tool(id, props)
      toolCol += 1
      stop(id, toolsRow, toolCol, props.onClick)
      return ring(id, ui.button(props))
    end
    local tools = {}
    table.insert(tools, tool("folder", { glyph = "folder-open", text = "Folder", tooltip = "Open the text folder", variant = "ghost", controlSize = "sm", onClick = openSaveDir }))
    if profile ~= "Settings" then
      table.insert(tools, tool("list", { glyph = "file-text", text = "Text", tooltip = "Save the colors as a text file", variant = "ghost", controlSize = "sm", onClick = saveList }))
    end
    if profile == "Recent" then
      table.insert(tools, tool("clear", { glyph = "trash", text = "Clear", tooltip = "Clear recent", variant = "ghost", controlSize = "sm", onClick = clearRecent }))
    elseif profile == "My palettes" then
      table.insert(tools, tool("new", { glyph = "plus", text = "New", tooltip = "New palette", variant = "ghost", controlSize = "sm", onClick = function() createPalette({}) end }))
      table.insert(tools, tool("delete", { glyph = "trash", text = "Delete", tooltip = "Delete palette", variant = "ghost", controlSize = "sm", onClick = deletePalette }))
    end
    local body = {
      ui.row({ gap = 6, align = "center" }, {
        ring("pick", ui.button({ glyph = "color-picker", text = "Pick", variant = "primary", controlSize = "sm", tooltip = "Pick from screen", onClick = pickFromScreen })),
        ring("select", ui.button({ glyph = "palette", text = "Select", variant = "ghost", controlSize = "sm", tooltip = "Add from selector", onClick = addFromSelector })),
        ui.spacer({ flexGrow = 1 }),
        pinSide.dockButton("colors", pinned, render),
        ring("close", ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "Close", onClick = function() pinSide.close("colors", pinned) end })),
      }),
      ui.row({ gap = 6, align = "center" }, {
        chooser("action", ACTIONS, actionIndex, 130, function(i)
          actionIndex = i
          saveChoice("action", ACTIONS[actionIndex])
          render()
        end, 2, 1),
        chooser("format", FORMATS, formatIndex, 130, function(i)
          formatIndex = i
          saveChoice("format", FORMATS[formatIndex])
          render()
        end, 2, 3),
      }),
      chooser("profile", PROFILES, profileIndex, nil, function(i) setProfile(PROFILES[i]) end, 3, 1),
    }
    for _, node in ipairs(right) do
      table.insert(body, node)
    end
    table.insert(body, ui.row({ gap = 4 }, tools))
    pinSide.render(pinned, ui.column({ gap = 8, padding = 10, flexGrow = 1 }, body))
    return
  end

  panel.render(ui.column({ gap = 10, padding = 12, height = 560 }, {
    ui.row({ gap = 8, align = "center" }, {
      ring("pick", ui.button({ text = "Pick from screen", glyph = "color-picker", variant = "primary", onClick = pickFromScreen })),
      ring("select", ui.button({ text = "Add from selector", glyph = "palette", onClick = addFromSelector })),
      ui.spacer({ flexGrow = 1 }),
      chooser("action", ACTIONS, actionIndex, 120, function(i)
        actionIndex = i
        saveChoice("action", ACTIONS[actionIndex])
        render()
      end, 1, 3),
      ui.label({ text = "as", color = "on_surface_variant" }),
      chooser("format", FORMATS, formatIndex, 120, function(i)
        formatIndex = i
        saveChoice("format", FORMATS[formatIndex])
        render()
      end, 1, 4),
      pinned and ui.row({ gap = 2 }, {
        ui.button({ glyph = "arrows-left-right", variant = "ghost", tooltip = "Move to the other side", onClick = function() pinSide.swap("colors", pinned) end }),
        ui.button({ glyph = "x", variant = "ghost", tooltip = "Close", onClick = function() panel.close() end }),
      })
        or ring("pin", ui.button({ glyph = "pin", variant = "ghost", tooltip = "Pin window", onClick = function()
          panel.close()
          pinSide.toggle("colors")
        end })),
    }),
    ui.row({ gap = 12, flexGrow = 1 }, {
      ui.column({ gap = 4, width = 160 }, profileButtons),
      ui.column({ gap = 8, flexGrow = 1 }, right),
    }),
  }))
end

-- alt+s drops the cursor so the name field can be clicked and typed in.
local function handleKey(chord)
  if chord == "alt+s" then
    kbd.clear()
    render()
  elseif kbd.key(chord) == "moved" then
    render()
  end
end

local function start()
  local savedPath = dataPath("savedir")
  saveDirText = savedPath and noctalia.string.trim(noctalia.readFile(savedPath) or "") or ""
  formatIndex = loadChoice("format", FORMATS, formatIndex)
  actionIndex = loadChoice("action", ACTIONS, actionIndex)
  setProfile(profile)
end

return start, handleKey
end
