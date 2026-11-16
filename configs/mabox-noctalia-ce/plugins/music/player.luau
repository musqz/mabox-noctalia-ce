--!nonstrict
-- Music panel: PyRadio stations and the mb-music list in cards, search over both, transport through MPRIS.

local csv = require("./lib/csv.luau")
local player = require("./lib/play.luau")
local logo = require("./lib/celogo.luau")
local hotkey = require("./lib/hotkey.luau")

local MAX_SEARCH_ROWS = 60

local radio, music = {}, {}
local musicAll = {}
local sel = nil -- { src = "radio" | "music", name = "..." }, nil = overview
local query = ""
local open = {}
local searchNonce = 0
local finder = false
local fName, fTag, fResults, fBusy, fFailed = "", "", nil, false, false
local fGroup = 1
local fNewGroup = ""
local fFocus = false
local added = {}
local folded = { Tools = true }
local nowPlaying = ""
local render

local function sh(cmd)
  noctalia.runAsync({ "setsid", "-f", "sh", "-c", cmd })
end

local function refreshTitle(delay)
  player.title(delay, function(t)
    -- An empty answer keeps the label start() set; only stop clears it.
    if t ~= "" then
      nowPlaying = t
      render()
    end
  end)
end

local function start(urls, shuffle, label)
  if #urls == 0 then
    return
  end
  player.play(urls, shuffle, label, true)
  nowPlaying = label
  render()
  refreshTitle(3)
end

local function transport(action)
  noctalia.runAsync({ "noctalia", "msg", "media", action })
  if action == "stop" then
    nowPlaying = ""
    render()
  else
    refreshTitle(1)
  end
end

local function card(c, key, forceOpen, filter)
  local isOpen = forceOpen or open[key]
  local head = {
    ui.button({
      text = c.name .. "  (" .. #c.tracks .. ")",
      glyph = isOpen and "chevron-down" or "chevron-right",
      variant = "ghost",
      controlSize = "sm",
      flexGrow = 1,
      onClick = function()
        if not forceOpen then
          open[key] = not open[key]
          render()
        end
      end,
    }),
    ui.button({ glyph = "arrows-shuffle", variant = "ghost", controlSize = "sm", tooltip = "Shuffle " .. c.name, onClick = function() start(c.playlist, true, "Shuffling " .. c.name) end }),
    ui.button({ glyph = "player-play", variant = "ghost", controlSize = "sm", tooltip = "Play " .. c.name, onClick = function() start(c.playlist, false, "Playing " .. c.name) end }),
  }
  local rows = { ui.row({ gap = 4, align = "center" }, head) }
  local shown = 0
  if isOpen then
    for i, t in ipairs(c.tracks) do
      if not filter or filter(t) then
        shown += 1
        table.insert(rows, ui.row({ key = key .. ":" .. i, gap = 4, align = "center" }, {
          ui.button({ text = t.title, variant = "ghost", controlSize = "sm", flexGrow = 1, tooltip = t.url, onClick = function() start({ t.url }, false, t.title) end }),
        }))
      end
    end
  end
  return ui.column({ fill = "surface_variant", radius = 8, padding = 8, gap = 2 }, rows), shown
end

local function runSearch()
  if fBusy then
    return
  end
  if noctalia.string.trim(fName) == "" and noctalia.string.trim(fTag) == "" then
    return
  end
  fBusy, fFailed = true, false
  render()
  csv.search(noctalia.string.trim(fName), noctalia.string.trim(fTag), function(list)
    fBusy = false
    fFailed = list == nil
    fResults = list or {}
    render()
  end)
end

local function groupNames()
  local names = {}
  for _, c in ipairs(radio) do
    table.insert(names, c.name)
  end
  table.insert(names, "New group...")
  return names
end

local function addFound(st, group)
  csv.addStation(group, st.name, st.url, function(ok)
    if ok then
      added[st.url] = true
      noctalia.notify("Music", "Added " .. st.name .. " to " .. group)
      csv.radio(function(cats)
        radio = cats or radio
        render()
      end)
    else
      noctalia.notify("Music", "Could not write " .. csv.radioPath)
    end
  end)
end

local function finderBody()
  local names = groupNames()
  if fGroup > #names then
    fGroup = 1
  end
  local nameFocus = fFocus
  fFocus = false
  local have = {}
  for _, c in ipairs(radio) do
    for _, t in ipairs(c.tracks) do
      have[t.url] = true
    end
  end
  local creating = fGroup == #names
  local target = creating and noctalia.string.trim(fNewGroup) or names[fGroup]
  local out = {
    ui.row({ gap = 6, align = "center" }, {
      ui.input({ key = "fname", value = fName, placeholder = "station name", controlSize = "sm", flexGrow = 1, focus = nameFocus, submitOnEnter = true,
        onChange = function(t) fName = t end, onSubmit = function(t) fName = t runSearch() end }),
      ui.input({ key = "ftag", value = fTag, placeholder = "genre tag", controlSize = "sm", width = 180, submitOnEnter = true,
        onChange = function(t) fTag = t end, onSubmit = function(t) fTag = t runSearch() end }),
      ui.button({ text = "Search", glyph = "search", variant = "primary", controlSize = "sm", enabled = not fBusy, onClick = runSearch }),
    }),
    ui.row({ gap = 6, align = "center" }, {
      ui.label({ text = "Add to group", fontSize = 12, color = "on_surface_variant" }),
      ui.select({ key = "fgroup", options = names, selectedIndex = fGroup - 1, onChange = function(idx) fGroup = tonumber(idx) + 1 render() end }),
      creating and ui.input({ key = "fnew", value = fNewGroup, placeholder = "new group name", controlSize = "sm", flexGrow = 1, onChange = function(t) fNewGroup = t render() end }) or ui.spacer({ flexGrow = 1 }),
    }),
  }
  if fBusy then
    table.insert(out, ui.label({ text = "Searching radio-browser.info", color = "on_surface_variant" }))
  elseif fFailed then
    table.insert(out, ui.label({ text = "No answer from radio-browser.info", color = "on_surface_variant" }))
  elseif fResults and #fResults == 0 then
    table.insert(out, ui.label({ text = "No stations found", color = "on_surface_variant" }))
  elseif fResults then
    local rows = {}
    for i, st in ipairs(fResults) do
      local info = st.country .. (st.codec ~= "" and ("  " .. st.codec) or "") .. (st.bitrate > 0 and (" " .. st.bitrate .. "k") or "")
      table.insert(rows, ui.row({ key = "f" .. i, gap = 4, align = "center" }, {
        ui.button({ glyph = "player-play", variant = "ghost", controlSize = "sm", tooltip = st.url, onClick = function() start({ st.url }, false, st.name) end }),
        ui.label({ text = st.name, flexGrow = 1, fontSize = 12 }),
        ui.label({ text = info, fontSize = 11, color = "on_surface_variant" }),
        ui.button({ text = (added[st.url] or have[st.url]) and "Added" or "Add", glyph = (added[st.url] or have[st.url]) and "check" or "plus", variant = "outline", controlSize = "sm", enabled = not (added[st.url] or have[st.url]) and target ~= "", tooltip = target ~= "" and ("Add to " .. target) or "Type a group name first", onClick = function() addFound(st, target) end }),
      }))
    end
    table.insert(out, ui.column({ fill = "surface_variant", radius = 8, padding = 8, gap = 2 }, rows))
  end
  return out
end

local function body()
  if finder then
    return finderBody()
  end
  local q = string.lower(noctalia.string.trim(query))
  if #radio == 0 and #music == 0 then
    return { ui.label({ text = "No stations or tracks found", color = "on_surface_variant" }) }
  end
  local sources = { { "radio", radio }, { "music", music } }
  local cards, budget = {}, MAX_SEARCH_ROWS
  for _, s in ipairs(sources) do
    local src, list = s[1], s[2]
    for _, c in ipairs(list) do
      local key = src .. ":" .. c.name
      if q ~= "" then
        local nameHit = string.find(string.lower(c.name), q, 1, true) ~= nil
        local hits = 0
        for _, t in ipairs(c.tracks) do
          if string.find(string.lower(t.title), q, 1, true) then
            hits += 1
          end
        end
        if (nameHit or hits > 0) and budget > 0 then
          local filter = function(t)
            if budget > 0 and (nameHit or string.find(string.lower(t.title), q, 1, true)) then
              budget -= 1
              return true
            end
            return false
          end
          local node = card(c, key, true, filter)
          table.insert(cards, node)
        end
      elseif sel == nil or (sel.src == src and sel.name == c.name) then
        table.insert(cards, (card(c, key, sel ~= nil, nil)))
      end
    end
  end
  if #cards == 0 then
    return { ui.label({ text = "Nothing matches", color = "on_surface_variant" }) }
  end
  local columns = (sel ~= nil and q == "") and 1 or 2
  local cols = {}
  for i = 1, columns do
    cols[i] = {}
  end
  for n, node in ipairs(cards) do
    table.insert(cols[(n - 1) % columns + 1], node)
  end
  local out = {}
  for i = 1, columns do
    table.insert(out, ui.column({ gap = 8, flexGrow = 1, flexBasis = 0 }, cols[i]))
  end
  return { ui.row({ gap = 8, align = "start" }, out) }
end

local function sidebar()
  local items = {}
  local function pick(src, name)
    finder = false
    sel = name and { src = src, name = name } or nil
    query = ""
    render()
  end
  -- A card with an outlined head that folds; rows are bullet entries like the Configs plugin list.
  local function group(name, rows)
    local isOpen = not folded[name]
    local card = {
      ui.button({
        text = name,
        glyph = isOpen and "chevron-down" or "chevron-right",
        variant = "outline",
        controlSize = "sm",
        contentAlign = "start",
        onClick = function()
          folded[name] = isOpen
          render()
        end,
      }),
    }
    if isOpen then
      for _, r in ipairs(rows) do
        table.insert(card, r)
      end
    end
    table.insert(items, ui.column({ fill = "surface_variant", radius = 10, padding = 8, gap = 4, border = "primary", borderWidth = 1 }, card))
  end
  local function entry(label, active, action)
    return ui.button({ text = label, glyph = active and "point-filled" or "point", variant = active and "outline" or "ghost", controlSize = "sm", contentAlign = "start", onClick = action })
  end
  table.insert(items, ui.button({ text = "All", variant = (sel == nil and query == "" and not finder) and "primary" or "ghost", controlSize = "sm", contentAlign = "start", onClick = function() pick(nil, nil) end }))
  table.insert(items, ui.button({ text = "Find stations", glyph = "search", variant = finder and "primary" or "ghost", controlSize = "sm", contentAlign = "start", onClick = function() finder, sel, query, fFocus = true, nil, "", true render() end }))
  for _, g in ipairs({ { "Radio", "radio", radio }, { "Music", "music", music } }) do
    if #g[3] > 0 then
      local rows = {}
      for _, c in ipairs(g[3]) do
        table.insert(rows, entry(c.name, sel ~= nil and sel.src == g[2] and sel.name == c.name, function() pick(g[2], c.name) end))
      end
      group(g[1], rows)
    end
  end
  local tools = {}
  local function tool(label, glyph, cmd)
    table.insert(tools, ui.button({ text = label, glyph = glyph, variant = "ghost", controlSize = "sm", contentAlign = "start", onClick = function() sh(cmd) panel.close() end }))
  end
  tool("Visualiser", "chart-bar", "jumpapp -m -c cava-transparent mb-cava")
  tool("PyRadio", "radio", "jumpapp -m -c pyradio kitty --class pyradio -e pyradio")
  tool("Volume", "volume", "pavucontrol")
  tool("Edit radio list", "edit", "xdg-open '" .. csv.radioPath .. "'")
  tool("Edit mpv list", "edit", "xdg-open '" .. csv.path .. "'")
  tool("Radio browser", "world", "xdg-open https://www.radio-browser.info")
  group("Tools", tools)
  return ui.column({ width = 250, height = 502, gap = 2 }, { ui.scroll({ flexGrow = 1, key = "side" }, { ui.column({ gap = 6 }, items) }) })
end

render = function()
  local content = body()
  panel.render(ui.column({ gap = 8, padding = 12, height = 592 }, {
    ui.row({ gap = 8, align = "center" }, {
      logo(),
      ui.label({ text = "Music" }),
      ui.label({ text = hotkey("mabox/music:player"), color = "outline_variant", flexGrow = 1 }),
    }),
    ui.row({ gap = 6, align = "center" }, {
      ui.input({
        key = "search" .. searchNonce,
        value = query,
        focus = not finder,
        placeholder = "search tracks and stations",
        controlSize = "sm",
        flexGrow = 1,
        onChange = function(text)
          query = text
          if text ~= "" then
            finder = false
          end
          render()
        end,
      }),
      ui.button({ key = "clear", glyph = "backspace", variant = "ghost", controlSize = "sm", enabled = query ~= "", tooltip = "Clear the search", onClick = function()
        query = ""
        searchNonce += 1
        render()
      end }),
      ui.button({ text = "Shuffle music", glyph = "arrows-shuffle", variant = "ghost", controlSize = "sm", onClick = function() start(musicAll, true, "Shuffling music") end }),
      ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "Close", onClick = function() panel.close() end }),
    }),
    ui.row({ gap = 6, align = "center", fill = "surface_variant", radius = 8, padding = 6 }, {
      ui.label({ text = nowPlaying ~= "" and nowPlaying or "Nothing playing", flexGrow = 1, fontSize = 12 }),
      ui.button({ glyph = "player-skip-back", variant = "ghost", controlSize = "sm", tooltip = "Previous", onClick = function() transport("previous") end }),
      ui.button({ glyph = "player-play", variant = "ghost", controlSize = "sm", tooltip = "Pause / play", onClick = function() transport("toggle") end }),
      ui.button({ glyph = "player-skip-forward", variant = "ghost", controlSize = "sm", tooltip = "Next", onClick = function() transport("next") end }),
      ui.button({ glyph = "player-stop", variant = "ghost", controlSize = "sm", tooltip = "Stop", onClick = function() transport("stop") end }),
    }),
    ui.row({ gap = 8, flexGrow = 1 }, {
      sidebar(),
      ui.scroll({ flexGrow = 1, key = "list" }, content),
    }),
  }))
end

function onOpen()
  query = ""
  finder = false
  render()
  csv.radio(function(cats)
    radio = cats or {}
    render()
  end)
  csv.list(function(cats, all)
    music = cats or {}
    musicAll = all or {}
    render()
  end)
  refreshTitle(0)
end
