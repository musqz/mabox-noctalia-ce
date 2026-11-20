--!nonstrict
-- Post-its (mb-postits) switched on in postits.conf: the Todo and Notes panels write their own entries; the agenda line is ours.
local M = {}

local CONF = (noctalia.getenv("HOME") or "") .. "/.config/mabox-noctalia-ce"

local function lines()
  local out = {}
  for l in string.gmatch(noctalia.readFile(CONF .. "/postits.conf") or "", "[^\n]+") do
    if string.match(l, "%S") then
      table.insert(out, l)
    end
  end
  return out
end

local function agendaOn()
  for _, l in ipairs(lines()) do
    if l == "agenda" then
      return true
    end
  end
  return false
end

local function setAgenda(on)
  local out = {}
  for _, l in ipairs(lines()) do
    if l ~= "agenda" then
      table.insert(out, l)
    end
  end
  if on then
    table.insert(out, "agenda")
  end
  noctalia.mkdirAll(CONF)
  noctalia.writeFile(CONF .. "/postits.conf", table.concat(out, "\n") .. (#out > 0 and "\n" or ""))
end

function M.rows(render)
  local on = agendaOn()
  return {
    ui.row({ gap = 8, align = "center" }, {
      ui.label({ text = "Agenda", flexGrow = 1, tooltip = "Show the next events from ~/caldir as a post-it (W-A-y)" }),
      ui.toggle({ key = "pi-agenda" .. (on and "1" or "0"), checked = on, onChange = function(v)
        setAgenda(v == true or v == "true")
        render()
      end }),
    }),
    ui.label({ text = "Notes: On screen in Notes. Todo: click a filter twice.", color = "on_surface_variant", fontSize = 12 }),
  }
end

return M
