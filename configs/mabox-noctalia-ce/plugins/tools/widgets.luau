--!nonstrict
-- Dropdown with one switch per desktop widget; mb-widget does the work.

local rows = {}

local logo = require("./lib/celogo.luau")

local function label(name)
  return name == "today" and "Todo today" or (string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2))
end

local render

local function load()
  noctalia.runAsync({ "mb-widget", "list" }, function(r)
    rows = {}
    local at = {}
    for line in string.gmatch(r.stdout or "", "[^\n]+") do
      local name, state = string.match(line, "^%S-:?([^:%s]+) %((%a+)%)$")
      if name then
        if not at[name] then
          at[name] = #rows + 1
          table.insert(rows, { name = name, on = false })
        end
        rows[at[name]].on = rows[at[name]].on or state == "on"
      end
    end
    render()
  end)
end

render = function()
  local body = {
    ui.row({ gap = 8, align = "center" }, {
      logo(),
      ui.label({ text = "Mabox widgets", flexGrow = 1 }),
      ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "Close", onClick = function() panel.close() end }),
    }),
  }
  for _, w in ipairs(rows) do
    table.insert(body, ui.row({ gap = 8, align = "center" }, {
      ui.label({ text = label(w.name), flexGrow = 1, color = "on_surface" }),
      ui.toggle({ checked = w.on, onChange = function(v)
        local want = v == true or v == "true"
        w.on = want
        noctalia.runAsync({ "mb-widget", want and "on" or "off", w.name }, function() load() end)
      end }),
    }))
  end
  body[#body + 1] = ui.button({
    text = "Edit layout",
    variant = "ghost",
    controlSize = "sm",
    onClick = function()
      panel.close()
      noctalia.runAsync({ "noctalia", "msg", "desktop-widgets-toggle-edit" })
    end,
  })
  panel.render(ui.column({ gap = 8, padding = 12 }, body))
end

function onOpen()
  render()
  load()
end
