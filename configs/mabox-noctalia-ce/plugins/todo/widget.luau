--!nonstrict
-- Todo desktop widget: open tasks that are overdue or due today. Click the header to open the panel.

local today = require("./lib/today.luau")

local COLORS = { overdue = "#e5534b", today = "#f0883e" }

local data = { overdue = {}, today = {}, lists = 0 }

local function row(t, color)
  local cells = {
    ui.box({ width = 10, height = 10, radius = 5, fill = color }),
    ui.label({ text = t.text, fontSize = 12, color = "on_surface", maxLines = 1, flexGrow = 1 }),
  }
  if data.lists > 1 then
    table.insert(cells, ui.label({ text = t.list, fontSize = 10, color = "on_surface_variant" }))
  end
  return ui.row({ gap = 6, align = "center" }, cells)
end

local function render()
  local max = math.max(3, math.min(15, tonumber(noctalia.getConfig("max")) or 8))
  local total = #data.overdue + #data.today
  local body = {
    ui.button({
      text = "Todo today (" .. total .. ")",
      variant = "ghost",
      controlSize = "sm",
      onClick = function()
        noctalia.runAsync({ "noctalia", "msg", "panel-toggle", "mabox/todo:main" })
      end,
    }),
  }
  if total == 0 then
    table.insert(body, ui.label({ text = "Nothing due today", fontSize = 12, color = "on_surface_variant" }))
  end
  local shown = 0
  for _, sec in ipairs({ { "overdue", "Overdue" }, { "today", "Today" } }) do
    local items = data[sec[1]]
    if #items > 0 and shown < max then
      table.insert(body, ui.label({ text = sec[2], fontSize = 11, color = COLORS[sec[1]] }))
      for _, t in ipairs(items) do
        if shown >= max then
          break
        end
        table.insert(body, row(t, COLORS[sec[1]]))
        shown = shown + 1
      end
    end
  end
  if total > shown then
    table.insert(body, ui.label({ text = "+" .. (total - shown) .. " more", fontSize = 11, color = "on_surface_variant" }))
  end
  desktopWidget.render(ui.column({
    gap = 6,
    padding = 12,
    width = 320,
    fill = "surface/0.85",
    radius = 8,
    border = "outline",
    borderWidth = 1,
  }, body))
end

function update()
  data = today.load()
  render()
end

function onConfigChanged()
  render()
end

noctalia.setUpdateInterval(10000)
desktopWidget.setWantsSecondTicks(false)
data = today.load()
render()
