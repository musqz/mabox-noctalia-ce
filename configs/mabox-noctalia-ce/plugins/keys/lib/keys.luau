--!nonstrict
-- Keys: binds from `mb-keys list --tsv`, grouped in cards; Basics, All or a search over everything.
local GROUP_ORDER = { "Panels", "Apps", "Windows", "Workspaces", "Desktop", "Capture", "Media", "Jump", "labwc defaults", "Helpers", "Other" }

local kbd = require("./kbd.luau")

return function(wide)
  local columns = wide and 3 or 2
  local keyWidth = wide and 190 or 150
  local binds = {}
  local mode = "basics"
  local query = ""
  local failed = false
  local searchNonce = 0
  local render

  local function statePath()
    local dir = noctalia.pluginDataDir()
    return dir and dir .. "/mode" or nil
  end

  -- W-k targets the compact panel; it hands over to the full-width one (toggle, so W-k closes it again) when that was the last size.
  local function sizePath()
    local dir = noctalia.pluginDataDir()
    return dir and dir .. "/size" or nil
  end

  local function lastWide()
    local path = sizePath()
    return path ~= nil and string.match(noctalia.readFile(path) or "", "^wide") ~= nil
  end

  local function saveSize(isWide)
    local path = sizePath()
    if path then
      noctalia.mkdirAll(noctalia.pluginDataDir())
      noctalia.writeFile(path, (isWide and "wide" or "compact") .. "\n")
    end
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

  local function parse(text)
    binds = {}
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
        table.insert(binds, { spec = f[1], mods = mods, key = f[3], group = f[4], basic = f[5] == "1", desc = f[6], command = f[7], run = f[8] == "1" })
      end
    end
  end

  local function matches(b, q)
    local hay = string.lower(table.concat(b.mods, " ") .. " " .. b.key .. " " .. b.spec .. " " .. b.desc .. " " .. b.command .. " " .. b.group)
    return string.find(hay, q, 1, true) ~= nil
  end

  local function visible()
    local q = string.lower(noctalia.string.trim(query))
    local groups, order = {}, {}
    for _, b in ipairs(binds) do
      local show
      if q ~= "" then
        show = matches(b, q)
      else
        show = mode == "all" or b.basic
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
    return (mode == "all" or noctalia.string.trim(query) ~= "") and b.command ~= b.desc
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
    return ui.row({ key = id, gap = 8, align = "center", radius = 4, border = kbd.sel(id) and "primary" or "outline", borderWidth = kbd.sel(id) and 2 or 0 }, {
      chips(b),
      line[1],
      b.run and ui.button({ glyph = "player-play", variant = "ghost", controlSize = "sm", tooltip = b.command, onClick = function() run(b) end }) or ui.spacer({ width = 0 }),
    })
  end

  local function body()
    local groups, order = visible()
    if #binds == 0 then
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
      for _, b in ipairs(groups[g]) do
        table.insert(rows, bindRow(b, "b" .. g .. b.spec .. b.command, y, at))
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

  local function swap()
    saveSize(not wide)
    panel.close()
    noctalia.runAsync({ "noctalia", "msg", "panel-open", "mabox/keys:" .. (wide and "keys" or "keys-wide") })
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
        ui.button({ glyph = wide and "arrows-minimize" or "arrows-maximize", variant = "ghost", controlSize = "sm", tooltip = wide and "Compact" or "Full width", onClick = swap }),
        ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "Close", onClick = function() panel.close() end }),
      }),
      ui.scroll({ flexGrow = 1, key = "list", revealKey = kbd.reveal() }, content),
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
    if not wide and lastWide() then
      panel.close()
      noctalia.runAsync({ "noctalia", "msg", "panel-toggle", "mabox/keys:keys-wide" })
      return
    end
    loadMode()
    kbd.clear()
    query = ""
    failed = false
    binds = {}
    render()
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
