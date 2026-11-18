--!nonstrict
-- Corner radius of the Mabox desktop widgets that declare the "radius" setting: all together or one kind at a time.
local M = {}

local TYPES = { ["mabox/info:info"] = "Info", ["mabox/sysinfo:sysinfo"] = "Sysinfo", ["mabox/todo:today"] = "Todo today" }
local ORDER = { "Info", "Sysinfo", "Todo today" }
local STEPS = { 0, 4, 8, 12, 16, 24, 32 }
local DEFAULT = 8

local open = false
local note = nil
local busy = false

-- Placed widgets from the state file, grouped by kind: { kind = { ids = {...}, radius = first value } }.
local function widgets()
  local base = noctalia.getenv("XDG_STATE_HOME")
  if not base or base == "" then
    base = (noctalia.getenv("HOME") or "") .. "/.local/state"
  end
  local byId, order = {}, {}
  local id, inSettings = nil, false
  for line in string.gmatch(noctalia.readFile(base .. "/noctalia/settings.toml") or "", "[^\n]+") do
    local header = string.match(line, "^%s*%[([^%]]+)%]%s*$")
    if string.match(line, "^%s*%[%[") then
      id = nil
    elseif header then
      local wid, tail = string.match(header, "^desktop_widgets%.widget%.([%w%-_]+)(.*)$")
      id, inSettings = wid, tail == ".settings"
      if id and tail == "" and not byId[id] then
        byId[id] = { id = id, radius = DEFAULT }
        table.insert(order, byId[id])
      end
    elseif id and byId[id] then
      local w = byId[id]
      if not inSettings then
        local t = string.match(line, "^%s*type%s*=%s*['\"]([^'\"]+)")
        if t and TYPES[t] then
          w.kind = TYPES[t]
        end
      else
        local r = tonumber(string.match(line, "^%s*radius%s*=%s*([%d%.]+)"))
        if r then
          w.radius = r
        end
      end
    end
  end
  local kinds = {}
  for _, w in ipairs(order) do
    if w.kind then
      local k = kinds[w.kind]
      if not k then
        k = { ids = {}, radius = w.radius, mixed = false }
        kinds[w.kind] = k
      end
      if math.abs(k.radius - w.radius) > 0.01 then
        k.mixed = true
      end
      table.insert(k.ids, w.id)
    end
  end
  return kinds
end

local function set(ids, value, render)
  if busy then
    return
  end
  busy = true
  noctalia.runAsync({ "sh", "-c", 'v=$1; shift; rc=0; for id in "$@"; do noctalia msg config-set "desktop_widgets.widget.$id.settings.radius" "$v" >/dev/null || rc=1; done; exit $rc', "sh", tostring(value), table.unpack(ids) }, function(r)
    busy = false
    note = nil
    if r.exitCode ~= nil and r.exitCode ~= 0 then
      note = "Could not change the radius"
    end
    render()
  end)
end

local function nearest(now)
  local idx = 1
  for i, v in ipairs(STEPS) do
    if math.abs(now - v) < math.abs(STEPS[idx] - now) then
      idx = i
    end
  end
  return idx
end

-- label  <  value  >
local function stepper(key, label, ids, now, mixed, render)
  local idx = nearest(now)
  local function step(d)
    local j = idx + d
    if j >= 1 and j <= #STEPS then
      set(ids, STEPS[j], render)
    end
  end
  return ui.row({ key = "wr-" .. key, gap = 6, align = "center" }, {
    ui.label({ text = label, flexGrow = 1, color = "on_surface" }),
    ui.button({ key = "wr-less-" .. key, glyph = "chevron-left", variant = "ghost", controlSize = "sm", tooltip = "Smaller", onClick = function() step(-1) end }),
    ui.column({ width = 56, align = "center" }, {
      ui.label({ text = mixed and "mixed" or (tostring(math.floor(now + 0.5)) .. " px"), fontWeight = "bold", color = "primary" }),
    }),
    ui.button({ key = "wr-more-" .. key, glyph = "chevron-right", variant = "ghost", controlSize = "sm", tooltip = "Larger", onClick = function() step(1) end }),
  })
end

-- The editor opens over the desktop, so a dropdown panel closes first; a pinned window stays.
local function editButton(pinned)
  return ui.button({ key = "wr-edit", glyph = "layout-dashboard", text = "Edit layout", variant = "ghost", controlSize = "sm", tooltip = "Place, resize and add desktop widgets (toggle)", onClick = function()
    if not pinned then
      panel.close()
    end
    noctalia.runAsync({ "noctalia", "msg", "desktop-widgets-toggle-edit" })
  end })
end

function M.rows(render, pinned)
  local kinds = widgets()
  local rows = { editButton(pinned) }
  local present, allIds = {}, {}
  for _, name in ipairs(ORDER) do
    local k = kinds[name]
    if k then
      table.insert(present, name)
      for _, id in ipairs(k.ids) do
        table.insert(allIds, id)
      end
    end
  end
  if #present == 0 then
    table.insert(rows, ui.label({ text = "No Mabox desktop widget is placed.", color = "on_surface_variant", fontSize = 12 }))
    return rows
  end
  table.insert(rows, ui.button({ key = "wr-fold", text = "Corner radius", glyph = open and "chevron-down" or "chevron-right", variant = "outline", controlSize = "sm", contentAlign = "start", tooltip = "Corner radius of the widget cards", onClick = function()
    open = not open
    render()
  end }))
  if not open then
    return rows
  end
  local first = kinds[present[1]].radius
  local mixed = false
  for _, name in ipairs(present) do
    if kinds[name].mixed or math.abs(kinds[name].radius - first) > 0.01 then
      mixed = true
    end
  end
  table.insert(rows, stepper("all", "All", allIds, first, mixed, render))
  for _, name in ipairs(present) do
    table.insert(rows, stepper(name, name, kinds[name].ids, kinds[name].radius, kinds[name].mixed, render))
  end
  if note then
    table.insert(rows, ui.label({ text = note, color = "error", fontSize = 12 }))
  end
  return rows
end

return M
