--!nonstrict
-- Keys: binds from `mb-keys list --tsv`, grouped in cards; Basics, All or a search over everything.
local GROUP_ORDER = { "Panels", "Apps", "Windows", "Workspaces", "Desktop", "Capture", "Media", "Jump", "labwc defaults", "Helpers", "Other" }

local kbd = require("./kbd.luau")

return function(wide)
  local columns = 3
  local keyWidth = 190
  local binds = {}
  local mode = "basics"
  local profiles = {}
  local profile = ""
  local appBinds = {}
  local focused = ""
  local query = ""
  local failed = false
  local searchNonce = 0
  local render, loadApp, parseLines

  local function statePath()
    local dir = noctalia.pluginDataDir()
    return dir and dir .. "/mode" or nil
  end

  local function loadMode()
    local path = statePath()
    mode = path and string.match(noctalia.readFile(path) or "", "^all") and "all" or "basics"
  end

  local function setMode(m)
    mode = m
    local path = statePath()
    if path then
      noctalia.mkdirAll(noctalia.pluginDataDir())
      noctalia.writeFile(path, m .. "\n")
    end
    render()
  end

  local function profilePath()
    local dir = noctalia.pluginDataDir()
    return dir and dir .. "/profile" or nil
  end

  local function loadProfile()
    local path = profilePath()
    profile = path and noctalia.string.trim(noctalia.readFile(path) or "") or ""
  end

  local function setProfile(name)
    profile = name
    query = ""
    local path = profilePath()
    if path then
      noctalia.mkdirAll(noctalia.pluginDataDir())
      noctalia.writeFile(path, name .. "\n")
    end
    render()
    loadApp()
  end

  local function parseProfiles(text)
    profiles = {}
    for line in string.gmatch(text, "[^\n]+") do
      local name, kind, source = string.match(line, "^(.-)\t(.-)\t(.*)$")
      if name and kind == "groups" then
        local set = {}
        for g in string.gmatch(source, "[^+]+") do
          set[g] = true
        end
        table.insert(profiles, { name = name, groups = set })
      elseif name and kind == "app" then
        table.insert(profiles, { name = name, app = source })
      end
    end
  end

  local function activeProfile()
    for _, p in ipairs(profiles) do
      if p.name == profile then
        return p
      end
    end
    return nil
  end

  local function activeGroups()
    local p = activeProfile()
    return p and p.groups
  end

  -- App lists are read once per open; render() runs again when they arrive.
  loadApp = function()
    local p = activeProfile()
    if not p or not p.app or appBinds[p.app] then
      return
    end
    local app = p.app
    noctalia.runAsync({ "mb-keys", "app", app, "--tsv" }, function(result)
      appBinds[app] = result.exitCode == 0 and parseLines(result.stdout or "") or {}
      render()
    end)
  end

  parseLines = function(text)
    local list = {}
    for line in string.gmatch(text, "[^\n]+") do
      local f = {}
      for part in string.gmatch(line .. "\t", "(.-)\t") do
        table.insert(f, part)
      end
      if #f >= 8 then
        local mods = {}
        for m in string.gmatch(f[2], "[^+]+") do
          table.insert(mods, m)
        end
        table.insert(list, { spec = f[1], mods = mods, key = f[3], group = f[4], basic = f[5] == "1", desc = f[6], command = f[7], run = f[8] == "1" })
      end
    end
    return list
  end

  local function parse(text)
    binds = parseLines(text)
  end

  local function matches(b, q)
    local hay = string.lower(table.concat(b.mods, " ") .. " " .. b.key .. " " .. b.spec .. " " .. b.desc .. " " .. b.command .. " " .. b.group)
    return string.find(hay, q, 1, true) ~= nil
  end

  local function visible()
    local q = string.lower(noctalia.string.trim(query))
    local groups, order = {}, {}
    local only = activeGroups()
    local source = binds
    local p = activeProfile()
    if p and p.app then
      source = appBinds[p.app] or {}
    end
    for _, b in ipairs(source) do
      local show
      if q ~= "" then
        show = matches(b, q)
      elseif p and p.app then
        show = true
      else
        show = (mode == "all" or b.basic) and (only == nil or only[b.group] == true)
      end
      if show then
        if not groups[b.group] then
          groups[b.group] = {}
          table.insert(order, b.group)
        end
        table.insert(groups[b.group], b)
      end
    end
    local rank = {}
    for i, g in ipairs(GROUP_ORDER) do
      rank[g] = i
    end
    table.sort(order, function(a, b)
      return (rank[a] or 99) < (rank[b] or 99)
    end)
    return groups, order
  end

  local function run(b)
    if not b.run then
      return
    end
    panel.close()
    noctalia.runAsync({ "setsid", "-f", "sh", "-c", b.command })
  end

  local function chips(b)
    local items = {}
    local parts = {}
    for _, m in ipairs(b.mods) do
      table.insert(parts, m)
    end
    table.insert(parts, b.key)
    for _, p in ipairs(parts) do
      table.insert(items, ui.row({ fill = "surface_variant", radius = 4, padding = 3 }, { ui.label({ text = p, fontSize = 11 }) }))
    end
    return ui.row({ gap = 3, align = "center", width = keyWidth }, items)
  end

  local function twoLines(b)
    return (mode == "all" or noctalia.string.trim(query) ~= "") and b.command ~= "" and b.command ~= b.desc
  end

  local function bindRow(b, id, y, x)
    kbd.stop(id, y, x, b.run and function() run(b) end or nil)
    local line = { ui.label({ text = b.desc, flexGrow = 1, fontSize = 12 }) }
    if twoLines(b) then
      line = { ui.column({ gap = 0, flexGrow = 1 }, {
        ui.label({ text = b.desc, fontSize = 12 }),
        ui.label({ text = b.command, fontSize = 10, color = "on_surface_variant" }),
      }) }
    end
    return ui.row({ key = id, gap = 8, align = "center", padding = 3, radius = 8, border = "primary", borderWidth = kbd.sel(id) and 3 or 0 }, {
      chips(b),
      line[1],
      b.run and ui.button({ glyph = "player-play", variant = "ghost", controlSize = "sm", tooltip = b.command, onClick = function() run(b) end }) or ui.spacer({ width = 0 }),
    })
  end

  local function body()
    local groups, order = visible()
    local p = activeProfile()
    local appView = p ~= nil and p.app ~= nil
    if appView and not appBinds[p.app] then
      return { ui.label({ text = "Loading", color = "on_surface_variant" }) }
    end
    if #binds == 0 and not appView then
      return { ui.label({ text = failed and "Could not read rc.xml" or "No keybinds found", color = "on_surface_variant" }) }
    end
    if #order == 0 then
      return { ui.label({ text = "Nothing matches", color = "on_surface_variant" }) }
    end
    -- Shortest column gets the next card.
    local cols, heights = {}, {}
    for i = 1, columns do
      cols[i], heights[i] = {}, 0
    end
    for _, g in ipairs(order) do
      local at = 1
      for i = 2, columns do
        if heights[i] < heights[at] then
          at = i
        end
      end
      local rows = { ui.label({ text = g, fontSize = 13 }) }
      local y = heights[at] + 1
      for n, b in ipairs(groups[g]) do
        table.insert(rows, bindRow(b, "b" .. g .. n .. b.spec, y, at))
        y = y + (twoLines(b) and 1.7 or 1)
      end
      table.insert(cols[at], ui.column({ fill = "surface_variant", radius = 8, padding = 8, gap = 4 }, rows))
      heights[at] = y + 1
    end
    local out = {}
    for i = 1, columns do
      table.insert(out, ui.column({ gap = 8, flexGrow = 1, flexBasis = 0 }, cols[i]))
    end
    return { ui.row({ gap = 8, align = "start" }, out) }
  end

  local function sidebar(searching)
    local current = activeProfile()
    local items, y = {}, 0
    local function entry(id, label, active, action)
      y += 1
      local sid = "s" .. id
      kbd.stop(sid, y, -1, action)
      table.insert(items, ui.row({ key = sid, padding = 3, radius = 8, border = "primary", borderWidth = kbd.sel(sid) and 3 or 0 }, {
        ui.button({ text = label, variant = (not searching and active) and "primary" or "ghost", controlSize = "sm", flexGrow = 1, onClick = action }),
      }))
    end
    entry("all", "All binds", current == nil, function() setProfile("") end)
    if focused ~= "" then
      entry("focused", "Focused: " .. focused, false, function() setProfile(focused) end)
    end
    for _, p in ipairs(profiles) do
      if not p.app then
        entry("g" .. p.name, p.name, current == p, function() setProfile(p.name) end)
      end
    end
    local apps = {}
    for _, p in ipairs(profiles) do
      if p.app then
        table.insert(apps, p)
      end
    end
    table.sort(apps, function(a, b)
      return string.lower(a.name) < string.lower(b.name)
    end)
    if #apps > 0 then
      table.insert(items, ui.label({ text = "Applications", fontSize = 11, color = "on_surface_variant" }))
    end
    for _, p in ipairs(apps) do
      entry("a" .. p.name, p.name, current == p, function() setProfile(p.name) end)
    end
    return ui.column({ width = 170, height = 470, gap = 2 }, { ui.scroll({ flexGrow = 1, key = "side", revealKey = kbd.reveal() }, { ui.column({ gap = 2 }, items) }) })
  end

  render = function()
    kbd.begin()
    local searching = noctalia.string.trim(query) ~= ""
    local content = body() -- registers the stops that reveal() and the input focus check
    panel.render(ui.column({ gap = 8, padding = 12, height = 560 }, {
      ui.row({ gap = 6, align = "center" }, {
        ui.input({
          key = "search" .. searchNonce,
          value = query,
          focus = kbd.reveal() == nil,
          placeholder = "search key, action or command",
          controlSize = "sm",
          flexGrow = 1,
          onChange = function(text)
            query = text
            render()
          end,
        }),
        ui.button({ text = "Basics", variant = (not searching and mode == "basics") and "primary" or "ghost", controlSize = "sm", onClick = function() query = "" setMode("basics") end }),
        ui.button({ text = "All", variant = (not searching and mode == "all") and "primary" or "ghost", controlSize = "sm", onClick = function() query = "" setMode("all") end }),
        ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "Close", onClick = function() panel.close() end }),
      }),
      ui.row({ gap = 8, flexGrow = 1 }, {
        #profiles > 0 and sidebar(searching) or ui.spacer({ width = 0 }),
        ui.scroll({ flexGrow = 1, key = "list", revealKey = kbd.reveal() }, content),
      }),
    }))
  end

  local function onKey(chord)
    if chord == "alt+s" then
      kbd.clear()
      searchNonce += 1
      render()
    elseif kbd.key(chord) == "moved" then
      render()
    end
  end

  return function()
    -- W-k and /keys still target the compact id; there is only the wide panel.
    if not wide then
      panel.close()
      noctalia.runAsync({ "noctalia", "msg", "panel-toggle", "mabox/keys:keys-wide" })
      return
    end
    loadMode()
    loadProfile()
    kbd.clear()
    query = ""
    failed = false
    binds = {}
    appBinds = {}
    focused = ""
    render()
    noctalia.runAsync({ "mb-keys", "profiles", "--tsv" }, function(result)
      if result.exitCode == 0 then
        parseProfiles(result.stdout or "")
        render()
        loadApp()
      end
    end)
    noctalia.runAsync({ "mb-keys", "focused" }, function(result)
      focused = noctalia.string.trim(result.stdout or "")
      render()
    end)
    noctalia.runAsync({ "mb-keys", "list", "--tsv" }, function(result)
      if result.exitCode ~= 0 then
        failed = true
      else
        parse(result.stdout or "")
      end
      render()
    end)
  end, onKey
end
