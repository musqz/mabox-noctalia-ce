--!nonstrict
-- Add an Espanso snippet. Snippets are appended to match/mabox.yml, written as JSON (valid YAML)
-- so it can be read back. Other match files are never touched.

local FILE = noctalia.getenv("HOME") .. "/.config/espanso/match/mabox.yml"

local items = {}
local trigger = ""
local replace = ""
local err = nil
local unreadable = false
local nonce = 0

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
  if not noctalia.writeFile(FILE, noctalia.json.encode({ matches = items }, true) .. "\n") then
    err = "Could not write mabox.yml"
    return false
  end
  return true
end

local render

local function commit()
  local t = noctalia.string.trim(trigger)
  err = nil
  if t == "" or noctalia.string.trim(replace) == "" then
    err = "Trigger and text are required"
  elseif string.find(replace, "{{", 1, true) then
    err = "Variables ({{ }}) are not supported here"
  else
    for _, m in ipairs(items) do
      if m.trigger == t then
        err = "Trigger already exists"
        break
      end
    end
  end
  if not err then
    table.insert(items, { trigger = t, replace = replace })
    if save() then
      noctalia.notify("Snippet added", t)
      panel.close()
      return
    end
    table.remove(items)
  end
  render()
end

function render()
  panel.render(ui.column({ gap = 8, padding = 12 }, {
    ui.label({ text = "New snippet", fontSize = 14 }),
    ui.label({ text = "Trigger", color = "on_surface_variant", fontSize = 11 }),
    ui.input({ key = "t" .. nonce, focus = true, value = trigger, placeholder = ":mysnippet", onChange = function(t) trigger = t end }),
    ui.label({ text = "Text to type", color = "on_surface_variant", fontSize = 11 }),
    ui.input({ key = "r" .. nonce, value = replace, multiline = true, height = 140, onChange = function(t) replace = t end }),
    err and ui.label({ text = err, color = "error" }) or ui.box({ height = 0 }),
    ui.row({ gap = 6 }, {
      ui.button({ text = "Save", glyph = "check", variant = "primary", onClick = commit }),
      ui.button({ text = "Cancel", variant = "ghost", onClick = function() panel.close() end }),
    }),
  }))
end

function onOpen()
  nonce += 1
  trigger = ""
  replace = ""
  err = nil
  load()
  render()
end
