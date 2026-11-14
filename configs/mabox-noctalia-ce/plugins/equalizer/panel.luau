--!nonstrict
-- Equalizer: preamp and 10 bands on the PipeWire filter-chain sink; mb-eq does the work.
local eq = require("./lib/eq.luau")
local logo = require("./lib/celogo.luau")
local hotkey = require("./lib/hotkey.luau")

local function card(key)
  return { key = key, fill = "surface_variant", radius = 10, padding = 12, gap = 8, border = "primary", borderWidth = 1 }
end

local state = eq.load()
local loaded = false
local checked = false
local startupSaved = false
local nameText = ""
local nameKey = 0
local previous = nil
local filePresets = {}
local running = false
local dirty = false
local render

local function status()
  noctalia.runAsync({ "mb-eq", "status" }, function(result)
    local out = result.stdout or ""
    checked = true
    loaded = string.find(out, "loaded", 1, true) ~= nil
    state.on = string.find(out, "default", 1, true) ~= nil
    render()
  end)
end

-- One mb-eq at a time while a slider is dragged; the last value is sent when the previous call is done.
local function apply()
  if running then
    dirty = true
    return
  end
  running = true
  local argv = { "mb-eq", "gains", table.unpack(eq.gainArgs(state.gains)) }
  noctalia.runAsync(argv, function()
    running = false
    if dirty then
      dirty = false
      apply()
    end
  end)
end

-- Pre (the first value) is the user's own level: a preset never changes it.
local function setGains(gains)
  for i = 2, 11 do
    if gains[i] ~= state.gains[i] then
      previous = { table.unpack(state.gains) }
      break
    end
  end
  local pre = state.gains[1]
  state.gains = { table.unpack(gains) }
  state.gains[1] = pre
  startupSaved = false
  eq.save(state)
  apply()
  render()
end

local function sliderRow(i)
  local g = state.gains[i]
  return ui.row({ key = "band-" .. i, gap = 8, align = "center" }, {
    ui.label({ text = eq.LABELS[i], width = 28, fontSize = 12, color = "on_surface_variant" }),
    ui.slider({ key = "sl-" .. i, min = -20, max = 20, step = 0.5, value = g, controlSize = "sm", flexGrow = 1,
      onChange = function(v)
        state.gains[i] = tonumber(v) or 0
        apply()
        render()
      end,
      onDragEnd = function()
        startupSaved = false
        eq.save(state)
        render()
      end }),
    ui.label({ text = string.format("%+.1f", g), width = 40, fontSize = 12 }),
  })
end

local function presetButtons(list, user, tag)
  local btns = {}
  for n, p in ipairs(list) do
    local same = true
    for i = 2, 11 do
      if math.abs((tonumber(p.gains[i]) or 0) - state.gains[i]) > 0.01 then
        same = false
        break
      end
    end
    local b = ui.button({ key = (tag or (user and "up" or "bp")) .. "-" .. n, text = p.name, controlSize = "sm", variant = same and "primary" or "outline",
      onClick = function() setGains(p.gains) end })
    if user then
      b = ui.row({ key = "upr-" .. n, gap = 0, align = "center" }, {
        b,
        ui.button({ key = "ud-" .. n, glyph = "x", glyphSize = 12, variant = "ghost", controlSize = "sm", tooltip = "Delete preset",
          onClick = function()
            table.remove(state.presets, n)
            eq.save(state)
            render()
          end }),
      })
    end
    table.insert(btns, b)
  end
  local rows = {}
  local per = user and 2 or 3
  for i = 1, #btns, per do
    table.insert(rows, ui.row({ key = (tag and (tag .. "r") or (user and "ur" or "br")) .. "-" .. i, gap = 6, align = "center" }, { table.unpack(btns, i, math.min(i + per - 1, #btns)) }))
  end
  return rows
end

-- A name that exists is replaced.
local function savePreset()
  local name = string.match(nameText, "^%s*(.-)%s*$")
  if name == "" then
    return
  end
  local copy = { table.unpack(state.gains) }
  local found = false
  for _, p in ipairs(state.presets) do
    if p.name == name then
      p.gains = copy
      found = true
    end
  end
  if not found then
    table.insert(state.presets, { name = name, gains = copy })
  end
  nameText = ""
  nameKey += 1
  eq.save(state)
  render()
end

local function bandsCard()
  local rows = {}
  for i = 1, 11 do
    table.insert(rows, sliderRow(i))
  end
  return ui.column(card("bands"), rows)
end

local function presetsCard()
  local rows = presetButtons(eq.PRESETS, false)
  for _, r in ipairs(presetButtons(filePresets, false, "fp")) do
    table.insert(rows, r)
  end
  for _, r in ipairs(presetButtons(state.presets, true)) do
    table.insert(rows, r)
  end
  local list = ui.scroll({ key = "plist", height = 372 }, { ui.column({ gap = 8 }, rows) })
  return ui.column(card("presets"), { list, ui.row({ key = "name-row", gap = 6, align = "center" }, {
    ui.input({ key = "name-" .. nameKey, placeholder = "Preset name", controlSize = "sm", flexGrow = 1, frameVisible = true,
      onChange = function(v) nameText = v end, onSubmit = function(v) nameText = v; savePreset() end }),
    ui.button({ text = "Save", variant = "outline", controlSize = "sm", onClick = savePreset }),
    ui.button({ text = "Revert", variant = "outline", controlSize = "sm", enabled = previous ~= nil, tooltip = "Back to the gains before the last preset",
      onClick = function() setGains(previous) end }),
  }) })
end

render = function()
  local body
  if not checked then
    body = ui.label({ text = "Reading state...", color = "on_surface_variant" })
  elseif not loaded then
    body = ui.column(card("missing"), {
      ui.label({ text = "The equalizer sink is not loaded.", color = "primary" }),
      ui.label({ text = "Restart PipeWire to load ~/.config/pipewire/pipewire.conf.d/eq.conf.", fontSize = 12, color = "on_surface_variant" }),
      ui.button({ text = "Restart PipeWire", variant = "outline", controlSize = "sm", onClick = function()
        noctalia.runAsync({ "systemctl", "--user", "restart", "pipewire", "pipewire-pulse", "wireplumber" }, function()
          status()
        end)
      end }),
    })
  else
    body = ui.column({ gap = 10 }, {
      ui.row({ gap = 10, align = "start" }, {
        ui.column({ key = "col-bands", flexGrow = 1, minWidth = 400 }, { bandsCard() }),
        ui.column({ key = "col-presets", width = 310 }, { presetsCard() }),
      }),
      ui.row({ key = "startup", gap = 6, align = "center" }, {
        ui.button({ text = startupSaved and "✓ Saved as startup values" or "Save as startup values", variant = "outline", controlSize = "sm",
          tooltip = "Write the gains into eq.conf (eq.conf.bak keeps the old file); used at the next PipeWire start",
          onClick = function()
            noctalia.runAsync({ "mb-eq", "save", table.unpack(eq.gainArgs(state.gains)) }, function(result)
              startupSaved = result.exitCode == 0
              render()
            end)
          end }),
      }),
    })
  end
  panel.render(ui.column({ gap = 10, padding = 12 }, {
    ui.row({ gap = 8, align = "center" }, {
      logo(),
      ui.label({ text = "Equalizer" }),
      ui.label({ text = hotkey("mabox/equalizer:main"), color = "outline_variant", flexGrow = 1 }),
      ui.toggle({ checked = state.on, enabled = loaded, onChange = function(v)
        local want = v == true or v == "true"
        state.on = want
        render()
        noctalia.runAsync({ "mb-eq", want and "on" or "off" }, function()
          status()
          eq.save(state)
        end)
      end }),
      ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "Close", onClick = function() panel.close() end }),
    }),
    body,
  }))
end

-- Presets from the shipped and the user folder: one JSON file each, {"name": ..., "gains": [11 numbers]}.
local function loadFilePresets()
  local cmd = [[jq -c 'select((.gains | length) == 11 and (.name | type) == "string") | {name, gains}' /usr/share/mabox-noctalia-ce/eq-presets/*.json "${XDG_CONFIG_HOME:-$HOME/.config}"/mabox-noctalia-ce/eq-presets/*.json 2>/dev/null]]
  noctalia.runAsync({ "sh", "-c", cmd }, function(result)
    filePresets = {}
    for line in string.gmatch(result.stdout or "", "[^\n]+") do
      local p = noctalia.json.decode(line)
      if type(p) == "table" then
        table.insert(filePresets, p)
      end
    end
    render()
  end)
end

function onOpen()
  loadFilePresets()
  state = eq.load()
  startupSaved = false
  checked = false
  render()
  status()
  apply()
end
