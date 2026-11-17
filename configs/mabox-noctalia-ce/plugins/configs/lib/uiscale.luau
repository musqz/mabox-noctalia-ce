--!nonstrict
-- Text and widget size of the whole shell (Noctalia accessibility.ui_scale).
local toml = require("./tomlsection.luau")
local M = {}

local PRESETS = { 0.8, 0.9, 1.0, 1.1, 1.25, 1.5 }

local note = nil
local busy = false

local function current()
  return tonumber(toml.section("accessibility").ui_scale) or 1.0
end

local function set(v, render)
  if busy then
    return
  end
  busy = true
  noctalia.runAsync({ "noctalia", "msg", "config-set", "accessibility.ui_scale", string.format("%.2f", v) }, function(r)
    busy = false
    note = nil
    if r.exitCode ~= 0 then
      note = "Could not change the size"
    end
    render()
  end)
end

function M.rows(render)
  local now = current()
  local idx = 1
  for i, v in ipairs(PRESETS) do
    if math.abs(now - v) < math.abs(PRESETS[idx] - now) then
      idx = i
    end
  end
  local function step(d)
    local j = idx + d
    if j >= 1 and j <= #PRESETS then
      set(PRESETS[j], render)
    end
  end
  return {
    ui.label({ text = "Text and widgets of the whole shell", color = "on_surface_variant", fontSize = 12 }),
    ui.row({ gap = 8, align = "center" }, {
      ui.button({ key = "uis-less", glyph = "chevron-left", variant = "ghost", controlSize = "sm", tooltip = "Smaller", onClick = function() step(-1) end }),
      ui.label({ text = string.format("%d%%", math.floor(now * 100 + 0.5)), width = 60, fontWeight = "bold", color = "primary" }),
      ui.button({ key = "uis-more", glyph = "chevron-right", variant = "ghost", controlSize = "sm", tooltip = "Larger", onClick = function() step(1) end }),
    }),
    note and ui.label({ text = note, color = "error", fontSize = 12 }) or ui.box({ height = 0 }),
  }
end

return M
