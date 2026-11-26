--!nonstrict
return function()
-- Bar profiles: the [bar] tables of the state file saved by name (mb-bars does the file work).

local logo = require("./celogo.luau")
local lapse = require("./lapse.luau")

local function card(key, active)
  return { key = key, fill = "surface_variant", radius = 10, padding = 12, gap = 10, border = "primary", borderWidth = active and 2 or 1 }
end

local data = { profiles = {}, current = {}, running = "", undo = false }
local looks = {}
local err, note = nil, nil
local busy = false
local newName = ""
local formGen = 0
local armed = nil
local confirm = {}

local render

local function load(then_)
  noctalia.runAsync({ "mb-bars", "looks" }, function(r)
    if r.exitCode == 0 then
      local ok, d = pcall(noctalia.json.decode, r.stdout or "")
      if ok and type(d) == "table" then
        looks = d
        render()
      end
    end
  end)
  noctalia.runAsync({ "mb-bars", "list" }, function(r)
    if r.exitCode == 0 then
      local ok, d = pcall(noctalia.json.decode, r.stdout or "")
      if ok and type(d) == "table" then
        data = d
      end
    else
      err = "mb-bars not found or failed"
    end
    if then_ then then_() end
    render()
  end)
end

-- Runs mb-bars with args, then reads the list again.
local function run(args, done, after)
  if busy then return end
  busy = true
  err, note = nil, nil
  render()
  local cmd = { "mb-bars" }
  for _, a in ipairs(args) do table.insert(cmd, a) end
  noctalia.runAsync(cmd, function(r)
    busy = false
    if r.exitCode ~= 0 then
      local msg = noctalia.string.trim(r.stderr or "")
      err = msg ~= "" and msg or "mb-bars failed"
    else
      note = done
      if after then after() end
    end
    load()
  end)
end

local function save()
  local name = noctalia.string.trim(newName)
  if name == "" then
    err = "Enter a name"
    render()
    return
  end
  run({ "save", name }, "Saved " .. name, function()
    newName = ""
    formGen += 1
  end)
end

local function remove(name)
  if not lapse.armed(confirm, "rm") or armed ~= name then
    armed = name
    lapse.arm(confirm, "rm", 5, render)
    render()
    return
  end
  lapse.disarm(confirm, "rm")
  armed = nil
  run({ "delete", name }, "Deleted " .. name)
end

local function cancel()
  lapse.disarm(confirm, "rm")
  armed = nil
  render()
end

local function positionOf(p, bar)
  for _, b in ipairs(p.bars) do
    if b.name == bar then return b.position end
  end
  return "top"
end

local function pictures(p)
  local rows = {}
  for _, s in ipairs(p.shots or {}) do
    local vertical = positionOf(p, s.bar) == "left" or positionOf(p, s.bar) == "right"
    local imgs = {}
    for i, f in ipairs(s.files) do
      table.insert(imgs, ui.image({ key = "im" .. p.name .. s.bar .. i, path = f, width = vertical and 60 or 330, height = vertical and 200 or 52, fit = "contain" }))
    end
    table.insert(rows, ui.row({ key = "pr" .. p.name .. s.bar, gap = 8, align = "center" }, imgs))
  end
  return ui.column({ gap = 6 }, rows)
end

-- A small screen outline with a strip per bar at its edge; a bar that is off is only outlined.
local function boxMap(key, bars)
  local sides = { top = {}, bottom = {}, left = {}, right = {} }
  for i, b in ipairs(bars) do
    local side = sides[b.position] or sides.top
    local horiz = b.position ~= "left" and b.position ~= "right"
    table.insert(side, ui.box({
      key = key .. "b" .. i,
      width = horiz and 104 or 6,
      height = horiz and 6 or 38,
      radius = 2,
      fill = b.enabled and "primary" or nil,
      border = "primary",
      borderWidth = 1,
    }))
  end
  return ui.column({ key = key, width = 116, height = 66, padding = 4, gap = 2, radius = 4, fill = "surface", border = "outline", borderWidth = 1 }, {
    ui.column({ gap = 2 }, sides.top),
    ui.row({ gap = 2, flexGrow = 1 }, {
      ui.column({ gap = 2 }, sides.left),
      ui.box({ flexGrow = 1 }),
      ui.column({ gap = 2 }, sides.right),
    }),
    ui.column({ gap = 2 }, sides.bottom),
  })
end

local function toggleBar(b)
  if busy then return end
  local on = 0
  for _, x in ipairs(data.current) do
    if x.enabled then on += 1 end
  end
  if b.enabled and on <= 1 then
    err = "Keep one bar on"
    render()
    return
  end
  err, note = nil, nil
  noctalia.runAsync({ "noctalia", "msg", "config-set", "bar." .. b.name .. ".enabled", b.enabled and "false" or "true" }, function(r)
    if r.exitCode ~= 0 then
      err = "Could not switch " .. b.name
    end
    load()
  end)
end

local function describe(p)
  local parts = {}
  for _, b in ipairs(p.bars) do
    table.insert(parts, b.name .. " (" .. b.position .. (b.enabled and "" or ", off") .. ")")
  end
  return table.concat(parts, ", ")
end

function render()
  local cards = {}
  for _, p in ipairs(data.profiles) do
    local isArmed = armed == p.name and lapse.armed(confirm, "rm")
    table.insert(cards, ui.column(card("p" .. p.name, p.active), {
      ui.row({ gap = 8, align = "center" }, {
        ui.label({ text = p.name, fontSize = 15 }),
        p.active and ui.row({ key = "run" .. p.name, fill = "primary", radius = 8, padding = 4 }, { ui.label({ text = " RUNNING ", color = "on_primary", fontSize = 11 }) }) or ui.box({ width = 0 }),
        ui.label({ text = describe(p), flexGrow = 1, color = "on_surface_variant", fontSize = 12, maxLines = 1 }),
        p.active and ui.button({ key = "rf" .. p.name, glyph = "refresh", text = "Refresh picture", variant = "ghost", controlSize = "sm", onClick = function() run({ "shots", p.name }, "Picture taken") end }) or ui.box({ width = 0 }),
        p.active and ui.box({ width = 0 }) or ui.button({ key = "ap" .. p.name, glyph = "check", text = "Apply", variant = "primary", controlSize = "sm", onClick = function() run({ "apply", p.name }, "Applied " .. p.name) end }),
        isArmed and ui.button({ key = "c" .. p.name, text = "Cancel", variant = "ghost", controlSize = "sm", onClick = cancel }) or ui.box({ width = 0 }),
        ui.button({ key = "d" .. p.name .. (isArmed and "a" or ""), glyph = "trash", text = isArmed and "Click again" or nil, variant = isArmed and "destructive" or "ghost", controlSize = "sm", tooltip = "Delete the profile", onClick = function() remove(p.name) end }),
      }),
      ui.row({ gap = 12 }, { boxMap("m" .. p.name, p.bars), pictures(p) }),
    }))
  end
  if #cards == 0 then
    table.insert(cards, ui.label({ text = "No profiles yet. Set the bars up, then save them under a name", color = "on_surface_variant" }))
  end

  local lookCols = {}
  for _, l in ipairs(looks) do
    table.insert(lookCols, ui.column({ key = "lk" .. l.name, gap = 6, width = 200, align = "center" }, {
      l.picture ~= "" and ui.image({ key = "li" .. l.name, path = l.picture, width = 200, height = 28, fit = "contain" }) or ui.box({ height = 28 }),
      ui.button({ key = "lb" .. l.name, text = l.title, variant = "ghost", controlSize = "sm", tooltip = l.desc, onClick = function() run({ "look", l.name }, "Look applied: " .. l.title) end }),
    }))
  end

  local barRows = {}
  for _, b in ipairs(data.current) do
    table.insert(barRows, ui.row({ key = "cb" .. b.name, gap = 8, align = "center", padding = 4 }, {
      ui.toggle({ key = "ct" .. b.name .. (b.enabled and "1" or "0"), checked = b.enabled, onChange = function() toggleBar(b) end }),
      ui.label({ text = b.name, width = 160, color = b.enabled and "on_surface" or "on_surface_variant" }),
      ui.label({ text = b.position, flexGrow = 1, color = "on_surface_variant" }),
    }))
  end

  panel.render(ui.column({ gap = 10, padding = 12, height = 620 }, {
    ui.row({ gap = 8, align = "center" }, {
      logo(),
      ui.label({ text = "Bars", flexGrow = 1 }),
      data.undo and ui.button({ key = "undo", glyph = "arrow-back-up", text = "Undo last apply", variant = "ghost", controlSize = "sm", onClick = function() run({ "undo" }, "Back to the bars before the last apply") end }) or ui.box({ width = 0 }),
      ui.button({ key = "set", glyph = "settings", text = "Bar settings", variant = "ghost", controlSize = "sm", tooltip = "Noctalia's own bar settings", onClick = function() noctalia.runAsync({ "noctalia", "msg", "settings-open", "bar" }) panel.close() end }),
    }),
    err and ui.label({ text = err, color = "error" }) or ui.label({ text = busy and "Working..." or note or "A profile is the setup of all bars, per-monitor overrides included", color = note and "primary" or "on_surface_variant", fontSize = 12 }),
    ui.row({ gap = 8, align = "center" }, {
      ui.input({ key = "name" .. formGen, value = newName, placeholder = "Name for the current bars", flexGrow = 1, controlSize = "sm", frameVisible = true, onChange = function(t) newName = t end, onSubmit = save }),
      ui.button({ key = "save", glyph = "device-floppy", text = "Save current", variant = "ghost", controlSize = "sm", onClick = save }),
    }),
    ui.scroll({ key = "body", gap = 10, flexGrow = 1 }, {
      ui.column(card("looks"), {
        ui.label({ text = "Looks: change the shape of the bar, your widgets and colours stay", color = "on_surface_variant", fontSize = 12 }),
        ui.row({ gap = 8 }, lookCols),
      }),
      ui.column(card("now"), {
        ui.label({ text = data.running ~= "" and ("Bars now: profile " .. data.running) or "Bars now: not a saved profile", color = "on_surface_variant", fontSize = 12 }),
        ui.row({ gap = 12 }, { boxMap("mnow", data.current), ui.column({ gap = 0, flexGrow = 1 }, barRows) }),
      }),
      ui.column({ gap = 10 }, cards),
      ui.box({ height = 4 }),
    }),
  }))
end

local function onOpen()
  err, note, armed = nil, nil, nil
  load()
  render()
end

return { onOpen = onOpen }
end
