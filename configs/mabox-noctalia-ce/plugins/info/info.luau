--!nonstrict
-- Info desktop widget: logo, About line and the basic hotkeys from mb-keys (same rows as the keys plugin).

local logo = require("./lib/logo.luau").logo

local TICK_MS = 5000
local RELOAD_TICKS = 36
local ticks = 0
local GROUP_ORDER = { "Panels", "Apps", "Windows", "Workspaces", "Desktop", "Capture", "Media", "Jump", "labwc defaults", "Helpers", "Other" }

local groups, order = {}, {}
local version = ""

local function parse(text)
  local g, o = {}, {}
  for line in string.gmatch(text or "", "[^\n]+") do
    local f = {}
    for part in string.gmatch(line .. "\t", "(.-)\t") do
      table.insert(f, part)
    end
    if #f >= 8 and f[5] == "1" then
      if not g[f[4]] then
        g[f[4]] = {}
        table.insert(o, f[4])
      end
      table.insert(g[f[4]], { spec = f[1], desc = f[6] })
    end
  end
  local rank = {}
  for i, name in ipairs(GROUP_ORDER) do
    rank[name] = i
  end
  table.sort(o, function(a, b)
    return (rank[a] or 99) < (rank[b] or 99)
  end)
  groups, order = g, o
end

local render

local function load()
  noctalia.runAsync({ "mb-keys", "list", "--tsv" }, function(r)
    if r.exitCode == 0 then
      parse(r.stdout)
      render()
    end
  end)
end

local function loadVersion()
  noctalia.runAsync("pacman -Q mabox-noctalia-ce 2>/dev/null | cut -d' ' -f2", function(r)
    version = string.gsub(r.stdout or "", "%s+$", "")
    render()
  end)
end

render = function()
  local body = {
    ui.row({ align = "center", gap = 8 }, {
      ui.image({ path = logo(), width = 40, height = 40, fit = "contain" }),
      ui.label({ text = "Mabox CE", fontSize = 18, color = "primary", flexGrow = 1 }),
    }),
    ui.label({
      text = "An experiment on Noctalia and labwc, based on the work of napcok." .. (version ~= "" and ("  v" .. version) or ""),
      fontSize = 10,
      color = "on_surface_variant",
    }),
    ui.separator({ color = "outline_variant" }),
  }
  for _, name in ipairs(order) do
    table.insert(body, ui.label({ text = name, fontSize = 11, color = "primary" }))
    for _, b in ipairs(groups[name]) do
      table.insert(body, ui.row({ gap = 6 }, {
        ui.column({ width = 80 }, { ui.label({ text = b.spec, fontSize = 11, color = "primary", maxLines = 1 }) }),
        ui.label({ text = b.desc, fontSize = 11, color = "on_surface", flexGrow = 1, maxLines = 1 }),
      }))
    end
  end
  table.insert(body, ui.separator({ color = "outline_variant" }))
  table.insert(body, ui.label({ text = "W-k: all hotkeys", fontSize = 11, color = "on_surface_variant" }))

  desktopWidget.render(ui.column({
    gap = 3,
    padding = 10,
    minWidth = 260,
    fill = "surface/0.85",
    radius = 8,
    border = "outline",
    borderWidth = 1,
  }, body))
end

-- render every tick so the logo follows theme changes; keys reload every RELOAD_TICKS
function update()
  ticks += 1
  if ticks % RELOAD_TICKS == 0 then
    load()
  else
    render()
  end
end

noctalia.setUpdateInterval(TICK_MS)
desktopWidget.setWantsSecondTicks(false)
render()
load()
loadVersion()
