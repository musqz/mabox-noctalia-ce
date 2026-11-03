--!nonstrict
-- Reset: front end for mb-reset-wl. Reset keeps a .bak-DATE backup of the old file.

local items = {}
local armed = nil
local diff = nil
local note = nil
local render

local function refresh(after)
  armed = nil
  noctalia.runAsync({ "mb-reset-wl" }, function(result)
    items = {}
    local state = {}
    for l in string.gmatch(result.stdout or "", "[^\n]+") do
      local name, st = string.match(l, "^(%S+)%s+(%S+)")
      if name then
        table.insert(items, { name = name, state = st })
        state[name] = st
      end
    end
    if after then
      after(state)
    end
    render()
  end)
end

local function compare(name)
  -- setsid: meld would die with the panel when it loses focus; the diff fallback needs stdout.
  local cmd = 'if command -v meld >/dev/null; then setsid -f mb-reset-wl -c "$1"; else mb-reset-wl -c "$1"; fi'
  noctalia.runAsync({ "sh", "-c", cmd, "sh", name }, function(result)
    local out = result.stdout or ""
    if out ~= "" then
      diff = { name = name, text = out }
      render()
    end
  end)
end

local function reset(name)
  armed = nil
  noctalia.runAsync({ "mb-reset-wl", name }, function()
    local reload = name == "rc" or name == "menu" or name == "themerc"
    refresh(function(state)
      if state[name] ~= "same" then
        note = name .. ": reset failed"
        return
      end
      note = reload and "Reset. Reloading labwc." or "Reset. Applies after the next login."
      if reload then
        noctalia.runAsync({ "labwc", "--reconfigure" })
      end
    end)
  end)
end

local function itemRow(it)
  local actions = {}
  if it.state == "differs" then
    table.insert(actions, ui.button({ glyph = "git-compare", variant = "ghost", controlSize = "sm", tooltip = "Compare", onClick = function() compare(it.name) end }))
    local sure = armed == it.name
    table.insert(actions, ui.button({
      text = sure and "Confirm" or nil,
      glyph = sure and nil or "restore",
      variant = sure and "primary" or "ghost",
      controlSize = "sm",
      tooltip = "Reset to default",
      onClick = function()
        if sure then
          reset(it.name)
        else
          armed = it.name
          render()
        end
      end,
    }))
  end
  return ui.row({ gap = 6, align = "center" }, {
    ui.label({ text = it.name, flexGrow = 1 }),
    ui.label({ text = it.state, color = it.state == "differs" and "primary" or "on_surface_variant" }),
    table.unpack(actions),
  })
end

render = function()
  local top = ui.row({ gap = 6, align = "center" }, {
    ui.label({ text = diff and ("Diff: " .. diff.name) or "Reset configs", flexGrow = 1 }),
    ui.button({ glyph = diff and "arrow-left" or "refresh", variant = "ghost", controlSize = "sm", tooltip = diff and "Back" or "Refresh", onClick = function()
      diff = nil
      refresh()
    end }),
    ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "Close", onClick = function() panel.close() end }),
  })
  local body
  if diff then
    body = ui.scroll({ flexGrow = 1, key = "diff" }, { ui.label({ text = diff.text, fontSize = 11 }) })
  else
    local rows = {}
    for _, it in ipairs(items) do
      table.insert(rows, itemRow(it))
    end
    if #rows == 0 then
      table.insert(rows, ui.label({ text = "Reading configs", color = "on_surface_variant" }))
    end
    if note then
      table.insert(rows, ui.label({ text = note, fontSize = 11, color = "on_surface_variant" }))
    end
    body = ui.column({ fill = "surface_variant", radius = 8, padding = 8, gap = 4 }, rows)
  end
  panel.render(ui.column({ gap = 8, padding = 12 }, { top, body }))
end

function onOpen()
  armed, diff, note = nil, nil, nil
  render()
  refresh()
end
