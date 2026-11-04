--!nonstrict
-- Snippets: add, edit and delete your Espanso matches. They live in match/mabox.yml, which is
-- written as JSON (valid YAML) so it can be read back. Other match files are never touched.

local kbd = require("./lib/kbd.luau")

local FILE = noctalia.getenv("HOME") .. "/.config/espanso/match/mabox.yml"

local items = {}
local query = ""
local editing = nil
local armed = nil
local err = nil
local nonce = 0
local field = "trigger"
local unreadable = false

local function load()
  items = {}
  local raw = noctalia.readFile(FILE)
  local data = raw and noctalia.json.decode(raw)
  unreadable = raw ~= nil and noctalia.string.trim(raw) ~= "" and data == nil
  for _, m in ipairs(data and data.matches or {}) do
    if type(m.trigger) == "string" and type(m.replace) == "string" then
      table.insert(items, { trigger = m.trigger, replace = m.replace })
    end
  end
end

-- Returns false with err set when the file must not be overwritten or the write fails.
local function save()
  if unreadable then
    err = "mabox.yml is not in the format this panel writes; edit it by hand"
    return false
  end
  noctalia.mkdirAll(noctalia.getenv("HOME") .. "/.config/espanso/match")
  local old = noctalia.readFile(FILE)
  if old then
    noctalia.writeFile(FILE .. ".bak", old)
  end
  local ok = noctalia.writeFile(FILE, noctalia.json.encode({ matches = items }, true) .. "\n")
  if not ok then
    err = "Could not write mabox.yml"
  end
  return ok
end

local render

local function startEdit(i)
  nonce += 1
  field = "trigger"
  err = nil
  armed = nil
  kbd.clear()
  local m = items[i]
  editing = { index = i, trigger = m and m.trigger or "", replace = m and m.replace or "" }
  render()
end

local function commit()
  local trigger = noctalia.string.trim(editing.trigger)
  if trigger == "" or noctalia.string.trim(editing.replace) == "" then
    err = "Trigger and text are required"
  elseif string.find(editing.replace, "{{", 1, true) then
    err = "Variables ({{ }}) are not supported here"
  else
    for i, m in ipairs(items) do
      if m.trigger == trigger and i ~= editing.index then
        err = "Trigger already exists"
        render()
        return
      end
    end
    local m = { trigger = trigger, replace = editing.replace }
    local before = { table.unpack(items) }
    if editing.index then
      items[editing.index] = m
    else
      table.insert(items, m)
    end
    if save() then
      editing = nil
      err = nil
    else
      items = before
    end
  end
  render()
end

local function delete(i)
  if armed == i then
    local m = table.remove(items, i)
    armed = nil
    kbd.clear()
    if not save() then
      table.insert(items, i, m)
    end
  else
    armed = i
  end
  render()
end

local function firstLine(s)
  return noctalia.string.trim(string.match(s, "[^\n]*"))
end

local function editor()
  return ui.column({ gap = 8, padding = 12 }, {
    ui.label({ text = editing.index and "Edit snippet" or "New snippet", fontSize = 14 }),
    ui.label({ text = "Trigger", color = "on_surface_variant", fontSize = 11 }),
    ui.input({ key = "t" .. nonce, focus = field == "trigger", value = editing.trigger, placeholder = ":mysnippet", onChange = function(t) editing.trigger = t end }),
    ui.label({ text = "Text to type", color = "on_surface_variant", fontSize = 11 }),
    ui.input({ key = "r" .. nonce, focus = field == "replace", value = editing.replace, multiline = true, height = 140, onChange = function(t) editing.replace = t end }),
    err and ui.label({ text = err, color = "error" }) or ui.box({ height = 0 }),
    ui.row({ gap = 6 }, {
      ui.button({ text = "Save", glyph = "check", variant = "primary", onClick = commit }),
      ui.button({ text = "Cancel", variant = "ghost", onClick = function()
        editing = nil
        err = nil
        kbd.clear()
        render()
      end }),
    }),
  })
end

local function rows()
  local out = {}
  local row = 0
  for i, m in ipairs(items) do
    local hay = m.trigger .. " " .. m.replace
    if query == "" or noctalia.fuzzyScore(query, hay) ~= nil then
      row += 1
      kbd.stop("e" .. i, row, 1, function() startEdit(i) end)
      kbd.stop("d" .. i, row, 2, function() delete(i) end)
      table.insert(out, ui.row({ key = "s" .. i, gap = 6, align = "center", padding = 4 }, {
        ui.column({ gap = 1, flexGrow = 1 }, {
          ui.label({ text = m.trigger, maxLines = 1 }),
          ui.label({ text = firstLine(m.replace), fontSize = 11, color = "on_surface_variant", maxLines = 1 }),
        }),
        ui.button({ key = "e" .. i, glyph = "pencil", variant = "ghost", controlSize = "sm", selected = kbd.sel("e" .. i), tooltip = "Edit", onClick = function() startEdit(i) end }),
        ui.button({ key = "d" .. i, glyph = "trash", selected = kbd.sel("d" .. i), text = armed == i and "Click again" or nil, variant = armed == i and "destructive" or "ghost", controlSize = "sm", tooltip = "Delete", onClick = function() delete(i) end }),
      }))
    end
  end
  if #out == 0 then
    table.insert(out, ui.label({ text = #items == 0 and "No snippets yet" or "Nothing matches", color = "on_surface_variant" }))
  end
  return out
end

function render()
  kbd.begin()
  if editing then
    panel.render(editor())
    return
  end
  kbd.stop("new", 0, 1, function() startEdit(nil) end)
  local list = rows() -- registers the stops that reveal() and the search focus check
  panel.render(ui.column({ gap = 8, padding = 12 }, {
    ui.row({ gap = 6, align = "center" }, {
      ui.input({ key = "q", focus = kbd.reveal() == nil, value = query, placeholder = "Search snippets", flexGrow = 1, onChange = function(t)
        query = t
        armed = nil
        kbd.clear()
        render()
      end }),
      ui.button({ key = "new", glyph = "plus", text = "New", variant = "ghost", selected = kbd.sel("new"), onClick = function() startEdit(nil) end }),
    }),
    err and ui.label({ text = err, color = "error" }) or ui.box({ height = 0 }),
    ui.scroll({ key = "list", gap = 0, height = 340, revealKey = kbd.reveal() }, list),
  }))
end

function onKey(chord, pressed)
  if not pressed then
    return
  end
  if editing then
    if chord == "alt+enter" then
      commit()
    elseif chord == "alt+q" then
      panel.close()
    elseif chord == "alt+s" then
      field = field == "trigger" and "replace" or "trigger"
      nonce += 1
      render()
    end
  elseif chord == "alt+s" then
    kbd.clear()
    armed = nil
    render()
  else
    local r = kbd.key(chord)
    if r == "moved" then
      armed = nil
      render()
    end
  end
end

function onOpen()
  kbd.clear()
  query = ""
  editing = nil
  armed = nil
  err = nil
  load()
  render()
end
