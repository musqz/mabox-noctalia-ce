--!nonstrict
return function()
-- The bars of the state file as one list: each bar switches on and off by itself (mb-bars does the file work).
-- The shipped bars (mb-*) cannot be renamed or deleted and are tuned in Noctalia's bar settings.

local logo = require("./celogo.luau")
local lapse = require("./lapse.luau")

local function card(key, active)
  return { key = key, fill = "surface_variant", radius = 10, padding = 12, gap = 10, border = "primary", borderWidth = active and 2 or 1 }
end

local bars = {}
local err, note = nil, nil
local busy = false
local armedBar = nil
local confirm = {}
local renaming, renameText = nil, ""
local addName, addPos, addGen = "", "bottom", 0
local lengthDraft = {}
local rev = 0

local render

local function load()
  noctalia.runAsync({ "mb-bars", "list" }, function(r)
    if r.exitCode == 0 then
      local ok, d = pcall(noctalia.json.decode, r.stdout or "")
      if ok and type(d) == "table" then
        bars = d.bars
      end
    else
      err = "mb-bars not found or failed"
    end
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

-- Switching never waits for another action.
local function toggleBar(b)
  err, note = nil, nil
  noctalia.runAsync({ "noctalia", "msg", "config-set", "bar." .. b.name .. ".enabled", b.enabled and "false" or "true" }, function(r)
    if r.exitCode ~= 0 then
      err = "Could not switch " .. b.name
    end
    load()
  end)
end

local function uniqueName(base)
  local taken = {}
  for _, x in ipairs(bars) do taken[x.name] = true end
  base = string.gsub(base, "^mb%-", "")
  local n = 2
  while taken[base .. "-" .. n] do n += 1 end
  return base .. "-" .. n
end

local function copyBar(b)
  run({ "bar-add", uniqueName(b.name), b.position, b.name }, "Copied " .. b.name)
end

-- Length is a share of the screen edge: 100 = the whole edge, 90 = a gap of 5% at both ends.
local function setLength(b)
  local text = lengthDraft[b.name]
  local n = text and tonumber(string.match(text, "^%s*(%d+%.?%d*)%s*%%?%s*$"))
  if not n or n < 10 or n > 100 then
    err = "Length is a number from 10 to 100"
    render()
    return
  end
  lengthDraft[b.name] = nil
  rev += 1
  run({ "bar-length", b.name, tostring(n) }, b.title .. ": length " .. n .. "%")
end

local function renameBar(b)
  local name = noctalia.string.trim(renameText)
  if name == "" or name == b.name then
    renaming = nil
    render()
    return
  end
  run({ "bar-rename", b.name, name }, "Renamed to " .. name, function() renaming = nil end)
end

local function removeBar(b)
  if not lapse.armed(confirm, "rmbar") or armedBar ~= b.name then
    armedBar = b.name
    lapse.arm(confirm, "rmbar", 5, render)
    render()
    return
  end
  lapse.disarm(confirm, "rmbar")
  armedBar = nil
  run({ "bar-delete", b.name }, "Deleted " .. b.name)
end

local function addBar()
  local name = noctalia.string.trim(addName)
  if name == "" then
    err = "Enter a name for the new bar"
    render()
    return
  end
  run({ "bar-add", name, addPos }, "Added " .. name, function()
    addName = ""
    addGen += 1
  end)
end

-- A small screen outline with a strip per bar that is on, at its edge.
local function boxMap(key)
  local sides = { top = {}, bottom = {}, left = {}, right = {} }
  for i, b in ipairs(bars) do
    local side = sides[b.position] or sides.top
    local horiz = b.position ~= "left" and b.position ~= "right"
    if b.enabled then
      table.insert(side, ui.box({
        key = key .. "b" .. i,
        width = horiz and 104 or 6,
        height = horiz and 6 or 38,
        radius = 2,
        fill = "primary",
      }))
    end
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

local function pictures(b)
  local vertical = b.position == "left" or b.position == "right"
  local imgs = {}
  if #(b.shots or {}) == 0 and b.picture ~= "" then
    return ui.image({ key = "pi" .. b.name, path = b.picture, width = 420, height = 62, fit = "contain" })
  end
  for i, f in ipairs(b.shots or {}) do
    table.insert(imgs, ui.image({ key = "im" .. b.name .. i, path = f, width = vertical and 60 or 330, height = vertical and 200 or 52, fit = "contain" }))
  end
  if #imgs == 0 then
    return ui.label({ text = b.enabled and "No picture yet. Press the refresh button" or "No picture yet. Switch the bar on, then press the refresh button", color = "on_surface_variant", fontSize = 12 })
  end
  return ui.row({ gap = 8, align = "center" }, imgs)
end

local function barCard(b)
  local isArmed = armedBar == b.name and lapse.armed(confirm, "rmbar")
  local isRenaming = renaming == b.name
  return ui.column(card("bc" .. b.name, b.enabled), {
    ui.row({ gap = 8, align = "center" }, {
      ui.toggle({ key = "ct" .. b.name .. (b.enabled and "1" or "0"), checked = b.enabled, onChange = function() toggleBar(b) end }),
      isRenaming and ui.input({ key = "rn" .. b.name, value = renameText, width = 180, controlSize = "sm", frameVisible = true, onChange = function(t) renameText = t end, onSubmit = function() renameBar(b) end })
        or ui.label({ text = b.title, fontSize = 15, color = b.enabled and "on_surface" or "on_surface_variant" }),
      b.enabled and ui.row({ key = "run" .. b.name, fill = "primary", radius = 8, padding = 4 }, { ui.label({ text = " RUNNING ", color = "on_primary", fontSize = 11 }) }) or ui.box({ width = 0 }),
      ui.label({ text = b.position, flexGrow = 1, color = "on_surface_variant", fontSize = 12 }),
      ui.label({ text = "Length", color = "on_surface_variant", fontSize = 12 }),
      ui.input({ key = "ln" .. b.name .. "_" .. rev .. "_" .. b.length, value = lengthDraft[b.name] or tostring(b.length), width = 56, controlSize = "sm", frameVisible = true, tooltip = "Share of the screen edge, 10 to 100. Enter applies",
        onChange = function(t) lengthDraft[b.name] = t end, onSubmit = function() setLength(b) end }),
      ui.label({ text = "%", color = "on_surface_variant" }),
      isRenaming and ui.button({ key = "rs" .. b.name, glyph = "check", text = "Save", variant = "primary", controlSize = "sm", onClick = function() renameBar(b) end }) or ui.box({ width = 0 }),
      isRenaming and ui.button({ key = "rc" .. b.name, text = "Cancel", variant = "ghost", controlSize = "sm", onClick = function() renaming = nil render() end })
        or (b.shipped and ui.box({ width = 0 }) or ui.button({ key = "re" .. b.name, glyph = "pencil", variant = "ghost", controlSize = "sm", tooltip = "Rename", onClick = function() renaming, renameText = b.name, b.name render() end })),
      b.enabled and ui.button({ key = "rf" .. b.name, glyph = "refresh", variant = "ghost", controlSize = "sm", tooltip = "New picture of this bar", onClick = function() run({ "shots", b.name }, "Picture of " .. b.title .. " taken") end }) or ui.box({ width = 0 }),
      ui.button({ key = "st" .. b.name, glyph = "settings", variant = "ghost", controlSize = "sm", tooltip = "Noctalia's bar settings", onClick = function() noctalia.runAsync({ "noctalia", "msg", "settings-open", "bar" }) panel.close() end }),
      ui.button({ key = "cp" .. b.name, glyph = "copy", variant = "ghost", controlSize = "sm", tooltip = "Copy this bar", onClick = function() copyBar(b) end }),
      isArmed and ui.button({ key = "dc" .. b.name, text = "Cancel", variant = "ghost", controlSize = "sm", onClick = function() lapse.disarm(confirm, "rmbar") armedBar = nil render() end }) or ui.box({ width = 0 }),
      b.shipped and ui.box({ width = 0 }) or ui.button({ key = "dl" .. b.name .. (isArmed and "a" or ""), glyph = "trash", text = isArmed and "Click again" or nil, variant = isArmed and "destructive" or "ghost", controlSize = "sm", tooltip = "Delete this bar", onClick = function() removeBar(b) end }),
    }),
    pictures(b),
  })
end

function render()
  local posButtons = {}
  for _, pos in ipairs({ "top", "bottom", "left", "right" }) do
    table.insert(posButtons, ui.button({ key = "ap" .. pos, text = pos, variant = addPos == pos and "primary" or "ghost", controlSize = "sm", onClick = function() addPos = pos render() end }))
  end

  local cards = {}
  for _, b in ipairs(bars) do
    table.insert(cards, barCard(b))
  end

  panel.render(ui.column({ gap = 10, padding = 12, height = 620 }, {
    ui.row({ gap = 8, align = "center" }, {
      logo(),
      ui.label({ text = "Bars", flexGrow = 1 }),
      ui.button({ key = "set", glyph = "settings", text = "Bar settings", variant = "ghost", controlSize = "sm", tooltip = "Noctalia's own bar settings", onClick = function() noctalia.runAsync({ "noctalia", "msg", "settings-open", "bar" }) panel.close() end }),
    }),
    err and ui.label({ text = err, color = "error" }) or ui.label({ text = busy and "Working..." or note or "Switch bars on and off, as many as you like", color = note and "primary" or "on_surface_variant", fontSize = 12 }),
    ui.scroll({ key = "body", gap = 10, flexGrow = 1 }, {
      ui.column(card("add"), {
        ui.row({ gap = 12, align = "center" }, {
          boxMap("map"),
          ui.column({ gap = 6, flexGrow = 1 }, {
            ui.label({ text = "New bar: a copy of the first bar on that edge", color = "on_surface_variant", fontSize = 12 }),
            ui.row({ gap = 8, align = "center" }, {
              ui.input({ key = "addn" .. addGen, value = addName, placeholder = "Name", width = 200, controlSize = "sm", frameVisible = true, onChange = function(t) addName = t end, onSubmit = addBar }),
              ui.row({ gap = 4 }, posButtons),
              ui.button({ key = "addb", glyph = "plus", text = "Add bar", variant = "ghost", controlSize = "sm", onClick = addBar }),
            }),
          }),
        }),
      }),
      ui.column({ gap = 10 }, cards),
      ui.box({ height = 4 }),
    }),
  }))
end

local function onOpen()
  err, note, armedBar, renaming = nil, nil, nil, nil
  render()
  noctalia.runAsync({ "mb-bars", "seed" }, function()
    load()
  end)
end

return { onOpen = onOpen }
end
