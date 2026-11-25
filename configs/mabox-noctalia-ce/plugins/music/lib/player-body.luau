--!nonstrict
return function()
-- Music panel: PyRadio stations and the mb-music list in cards, search over both, transport through MPRIS.

local csv = require("./csv.luau")
local player = require("./play.luau")
local logo = require("./celogo.luau")
local hotkey = require("./hotkey.luau")
local mine = require("./mine.luau")
local lapse = require("./lapse.luau")
local playlists = require("./playlists.luau")

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
local fAdding = false
local added = {}
local folded = { Tools = true }
local nowPlaying = ""
local revealRow, revealSide = nil, nil -- keys of the playing row and its sidebar entry, so both lists scroll to them
local playingUrl = "" -- url mpv has loaded, so its row can be coloured
local dead, checking, confirmRemove = {}, {}, {}
local fetching = {}
local triedMeta = {} -- urls yt-dlp was asked about this session, so a failing one is not asked again at every press
local lists = {}
local tIdx = 1 -- index in the "Add to playlist" options; the last one is "New playlist..."
local newName = ""
local tName = "" -- name of the target playlist, so a changed list order keeps the choice
local plFocus = false
local render

local sleepLeft = 0
local sleepShut = false -- the shutdown switch; not remembered, so an old choice never powers the computer off later
local sleepOff = false -- the running timer also shuts the computer down
local sleepOpen = false -- the timer row under the now-playing row
local sleepDraft = "" -- minutes typed by hand
local sleepNonce = 0
local STEPS = { 10, 30, 60, 300 }

local function stepSecs()
  return mine.opt("step", 30)
end

local function stepLabel(n)
  return n >= 60 and (n // 60 .. "m") or (n .. "s")
end

local function nextStep()
  local cur = stepSecs()
  local nxt = STEPS[1]
  for i, v in ipairs(STEPS) do
    if v == cur then
      nxt = STEPS[i % #STEPS + 1]
    end
  end
  mine.setOpt("step", nxt)
  render()
end
local cavaOn = false
local eqOn = false

-- `mb-eq status` prints "loaded" while the filter exists and "default" when it is the active sink, which is what on means.
local function refreshEq()
  noctalia.runAsync({ "mb-eq", "status" }, function(r)
    local on = r.exitCode == 0 and string.find(r.stdout or "", "default", 1, true) ~= nil
    if on ~= eqOn then
      eqOn = on
      render()
    end
  end)
end

local function sh(cmd)
  noctalia.runAsync({ "setsid", "-f", "sh", "-c", cmd })
end

local function refreshCava(delay)
  noctalia.runAsync({ "sh", "-c", (delay > 0 and ("sleep " .. delay .. "; ") or "") .. "wlrctl toplevel find app_id:cava-transparent" }, function(r)
    cavaOn = r.exitCode == 0
    render()
  end)
end

local function toggleCava()
  sh("mb-cava toggle")
  refreshCava(1)
end

-- The player the transport buttons talk to: "" follows Noctalia's active player, a name pins one (playerctl base name, e.g. mpv).
local players, pinned = {}, ""

local function pinPath()
  local dir = noctalia.pluginDataDir()
  return dir and (dir .. "/player")
end

local pinLoaded = false

local function loadPin()
  local path = pinPath()
  if pinLoaded or not path then
    return
  end
  pinLoaded = true
  pinned = noctalia.string.trim(noctalia.readFile(path) or "")
end

local function savePin()
  local path = pinPath()
  if path then
    noctalia.writeFile(path, pinned .. "\n")
  end
end

-- Noctalia has no query for its active player: a playing one stands in, else the first paused one.
local activeName = ""
local missed = 0 -- polls in a row that did not list the pinned player

local function refreshPlayers()
  loadPin()
  noctalia.runAsync({ "sh", "-c", "playerctl -a metadata --format '{{playerName}}|{{status}}' 2>/dev/null" }, function(r)
    local names, seen, playing, paused = {}, {}, "", ""
    for line in string.gmatch(r.stdout or "", "[^\n]+") do
      local name, status = string.match(line, "^([^|]+)|(%a+)")
      if name and not seen[name] then
        seen[name] = true
        table.insert(names, name)
      end
      if name and status == "Playing" and playing == "" then
        playing = name
      elseif name and status == "Paused" and paused == "" then
        paused = name
      end
    end
    table.sort(names)
    local active = playing ~= "" and playing or paused
    local gone = false
    if pinned ~= "" and (r.exitCode == 0 or r.exitCode == 1) and not seen[pinned] then
      missed += 1
      if missed >= 2 then -- the pinned player quit (two polls, so a restart between tracks keeps it): back to the active one
        pinned = ""
        savePin()
        gone = true
      end
    else
      missed = 0
    end
    if gone or active ~= activeName or table.concat(names, "\n") ~= table.concat(players, "\n") then
      players, activeName = names, active
      render()
    end
  end)
end

local function refreshSleep()
  sleepLeft, _, sleepOff = mine.sleepLeft()
  render()
end

local function sleepLabel()
  return sleepLeft > 0 and ("Sleep " .. sleepLeft .. "m") or "Sleep"
end

local function startSleep(minutes)
  mine.startSleep(minutes, sleepShut, refreshSleep)
end

local function sleepRow()
  local _, setMins = mine.sleepLeft()
  local chips = {}
  for _, m in ipairs(mine.SLEEP_PRESETS) do
    local on = sleepLeft > 0 and setMins == m
    table.insert(chips, ui.button({ key = "sl" .. m .. (on and "-on" or ""), text = tostring(m), variant = on and "primary" or "outline", controlSize = "sm", onClick = function() startSleep(m) end }))
  end
  local function manual()
    local m = tonumber(sleepDraft)
    if m and m >= 1 and m <= 1440 then
      startSleep(math.floor(m))
      sleepDraft = ""
      sleepNonce += 1
    end
  end
  local shut = sleepShut
  return ui.row({ key = "sleeprow", gap = 6, align = "center", fill = "surface_variant", radius = 8, padding = 6 }, {
    ui.label({ text = "Stop after", color = "on_surface_variant", fontSize = 11 }),
    ui.row({ gap = 4 }, chips),
    ui.input({ key = "sleepmin" .. sleepNonce, value = sleepDraft, placeholder = "min", width = 60, controlSize = "sm", frameVisible = true,
      onChange = function(t) sleepDraft = t end, onSubmit = manual }),
    ui.button({ key = "sleepset", text = "Set", variant = "outline", controlSize = "sm", tooltip = "Start the timer with the minutes typed (1 to 1440)", onClick = manual }),
    ui.spacer({ flexGrow = 1 }),
    ui.toggle({ key = "sleepoff" .. (shut and "1" or "0"), checked = shut, onChange = function(v)
      local on = v == true or v == "true"
      sleepShut = on
      if sleepLeft > 0 then
        mine.setSleepPoweroff(on, refreshSleep)
      else
        render()
      end
    end }),
    ui.label({ text = "Shut down the computer", fontSize = 11, color = shut and "primary" or "on_surface_variant" }),
    sleepLeft > 0 and ui.button({ key = "sleepcancel", glyph = "x", text = "Cancel", variant = "ghost", controlSize = "sm", onClick = function() mine.cancelSleep(refreshSleep) end }) or ui.box({ height = 0 }),
  })
end


-- Looks the playing url up in the radio and music lists so Recent only holds what really played.
-- Radio stations change their song title all the time, so only list tracks keep their stream title.
local function isRadio(path)
  for _, c in ipairs(radio) do
    for _, t in ipairs(c.tracks) do
      if t.url == path then
        return true
      end
    end
  end
  return false
end

local function storeMeta(path, rawTitle, artist)
  if path ~= "" and not isRadio(path) then
    mine.setMetas({ [path] = { t = rawTitle, a = artist } })
  end
end

-- The radio group or category the playing url belongs to, shown next to the title.
local function playingCategory()
  if playingUrl == "" then
    return ""
  end
  for _, list in ipairs({ radio, music }) do
    for _, c in ipairs(list) do
      for _, t in ipairs(c.tracks) do
        if t.url == playingUrl then
          return c.name
        end
      end
    end
  end
  return ""
end

local listsLoaded = { radio = false, music = false } -- the log is only read once both lists can name its urls

-- Jumps the panel to the list the playing track is in: the open list first, then radio, music and playlists.
local function showPlaying()
  if playingUrl == "" then
    return
  end
  local groups = {
    { "radio", radio, "Radio" },
    { "music", music, "Music" },
    { "list", lists, "Playlists" },
  }
  local function at(g, c)
    for i, t in ipairs(c.tracks) do
      if t.url == playingUrl then
        return i
      end
    end
  end
  local function go(g, c, i)
    finder, query = false, ""
    sel = { src = g[1], name = c.name }
    folded[g[3]] = false
    revealRow = g[1] .. ":" .. c.name .. ":" .. i
    revealSide = "side:" .. g[1] .. ":" .. c.name
    render()
  end
  if sel ~= nil and sel.src == "mine" then
    for i, tr in ipairs(mine.recent().tracks) do
      if tr.url == playingUrl then
        revealRow = "mine:Recent:" .. i
        render()
        return
      end
    end
  end
  if sel ~= nil then
    for _, g in ipairs(groups) do
      if g[1] == sel.src then
        for _, c in ipairs(g[2]) do
          local i = c.name == sel.name and at(g, c)
          if i then
            go(g, c, i)
            return
          end
        end
      end
    end
  end
  for _, g in ipairs(groups) do
    for _, c in ipairs(g[2]) do
      local i = at(g, c)
      if i then
        go(g, c, i)
        return
      end
    end
  end
  -- A station played from Find stations without adding it: the search result is the only place it is listed.
  if not (listsLoaded.radio and listsLoaded.music) or fBusy then
    return
  end
  for i, st in ipairs(fResults or {}) do
    if st.url == playingUrl then
      finder, sel, query = true, nil, ""
      revealRow = "f" .. i
      render()
      return
    end
  end
  noctalia.notify("Music", "This one is not in your lists")
end

local lastRemembered = nil -- url last put in Recent, so the poll does not write it again

local function rememberPlaying(path)
  lastRemembered = path
  for _, list in ipairs({ radio, music }) do
    for _, c in ipairs(list) do
      for _, t in ipairs(c.tracks) do
        if t.url == path then
          mine.addRecent(t.title, t.url)
          return
        end
      end
    end
  end
end

-- Tracks mpv started while the panel was closed (or between two polls) come from its own log.

local function mergeRecent()
  if not (listsLoaded.radio and listsLoaded.music) then
    return
  end
  player.drainRecent(function(urls)
    if #urls == 0 then
      return
    end
    local want = {}
    for _, u in ipairs(urls) do
      want[u] = true
    end
    local title = {}
    for _, list in ipairs({ radio, music }) do
      for _, c in ipairs(list) do
        for _, t in ipairs(c.tracks) do
          if want[t.url] and not title[t.url] then
            title[t.url] = t.title
          end
        end
      end
    end
    local items = {}
    for _, u in ipairs(urls) do
      if title[u] then
        table.insert(items, { title = title[u], url = u })
      end
    end
    if #items > 0 then
      mine.addRecentMany(items)
      render()
    end
  end)
end

-- While the panel is open the title is read every few seconds so it matches the bar when the track changes by itself.
local pollGen = 0
local deadPolls = 0

local function pollTitle(gen, delay)
  player.verify(delay, function(alive, title, path, playing, rawTitle, artist)
    if gen ~= pollGen then
      return
    end
    local changed = false
    -- Two polls without mpv in a row: it ended, so the label goes too.
    deadPolls = alive and 0 or deadPolls + 1
    if deadPolls >= 2 and nowPlaying ~= "" then
      nowPlaying = ""
      changed = true
    end
    -- mpv answers with no path for a moment while it switches entries; keep the last url until it is gone for two polls.
    local url = playingUrl
    if alive and path ~= "" then
      url = path
    elseif deadPolls >= 2 then
      url = ""
    end
    if url ~= playingUrl then
      playingUrl = url
      changed = true
    end

    if alive and title ~= "" and title ~= nowPlaying and playing then
      nowPlaying = title
      changed = true
    end
    storeMeta(path, rawTitle, artist)
    -- The list moved on to the next track by itself: that one belongs in Recent too. The first answer after opening only sets the baseline.
    if alive and playing and path ~= "" then
      if lastRemembered == nil then
        lastRemembered = path
      elseif path ~= lastRemembered then
        rememberPlaying(path)
      end
    end
    if changed then
      render()
    end
    refreshEq()
    refreshPlayers()
    if alive then
      mergeRecent()
    end
    pollTitle(gen, 8)
  end)
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

local playSeq = 0

-- from: 1-based start in the list.
local function start(urls, shuffle, label, from)
  if #urls == 0 then
    return
  end
  player.play(urls, shuffle, label, true, from)
  nowPlaying = label
  render()
  playSeq += 1
  local seq = playSeq
  -- mpv skips an entry that fails and goes on, so the playing state is polled a few times at the start;
  -- the entry that really plays goes into Recent, and when mpv is gone nothing could be played.
  -- The old mpv is replaced at the start, so one check can land in the gap with no mpv; two in a row mean it really failed.
  local gone = 0
  local function check(delays, n)
    player.verify(delays[n], function(alive, title, path, playing, rawTitle, artist)
      if seq ~= playSeq then
        return
      end
      if alive and path ~= "" then
        playingUrl = path
      end
      if not alive then
        gone += 1
        if gone >= 2 or not delays[n + 1] then
          nowPlaying = "Could not play: " .. label
          render()
        else
          check(delays, n + 1)
        end
        return
      end
      gone = 0
      if playing then
        if title ~= "" then
          nowPlaying = title
        end
        storeMeta(path, rawTitle, artist)
        rememberPlaying(path)
        render()
      elseif delays[n + 1] then
        check(delays, n + 1)
      end
    end)
  end
  check({ 2, 2, 3, 4, 6, 8 }, 1)
end

-- Refresh: show what plays now and remember it when it is a known track.
local function syncNow()
  refreshEq()
  refreshPlayers()
  player.verify(0, function(alive, title, path, playing, rawTitle, artist)
    if alive and path ~= "" then
      playingUrl = path
    elseif not alive then
      playingUrl = ""
    end
    if alive and title ~= "" then
      nowPlaying = title
    end
    if alive and playing then
      if path ~= "" then
        storeMeta(path, rawTitle, artist)
      end
      rememberPlaying(path)
    end
    render()
  end)
end

local PLAYERCTL = { toggle = "play-pause", play = "play", pause = "pause", stop = "stop", next = "next", previous = "previous" }

local function transport(action)
  loadPin()
  if pinned ~= "" and PLAYERCTL[action] then
    noctalia.runAsync({ "playerctl", "-p", pinned, PLAYERCTL[action] }, function(r)
      if r.exitCode ~= 0 then -- the pinned player is gone: follow the active one
        noctalia.runAsync({ "noctalia", "msg", "media", action })
      end
    end)
  else
    noctalia.runAsync({ "noctalia", "msg", "media", action })
  end
  if action == "stop" then
    player.resetRepeat()
  end
  if action == "stop" and (pinned == "mpv" or (pinned == "" and (activeName == "" or activeName == "mpv"))) then -- the list plays through mpv: another player's stop leaves it alone
    playSeq += 1
    playingUrl = ""
    nowPlaying = ""
    render()
  elseif action ~= "stop" then
    refreshTitle(1)
  end
end

local function checkGroup(c, key)
  if checking[key] then
    return
  end
  checking[key] = true
  render()
  csv.check(c.playlist, function(list, why)
    checking[key] = nil
    for _, u in ipairs(list or {}) do
      dead[u] = true
    end
    if list == nil then
      noctalia.notify("Music", "Stream check failed: " .. tostring(why))
    end
    render()
  end)
end

local function removeDead(c, key, urls)
  if not lapse.armed(confirmRemove, key) then
    lapse.arm(confirmRemove, key, 5, render)
    render()
    return
  end
  lapse.disarm(confirmRemove, key)
  csv.removeStations(urls, function(ok)
    if ok then
      for _, u in ipairs(urls) do
        dead[u] = nil
      end
      noctalia.notify("Music", "Removed " .. #urls .. " streams, the old list is stations.csv.bak")
      csv.radio(function(cats)
        radio = cats or radio
        render()
      end)
    else
      noctalia.notify("Music", "Could not write " .. csv.radioPath)
    end
  end)
end

local function loadLists(after)
  playlists.load(function(l)
    lists = l or lists
    if tName == "" and lists[tIdx] and tIdx <= #lists then
      tName = lists[tIdx].name
    end
    for i, pl in ipairs(lists) do
      if pl.name == tName then
        tIdx = i
      end
    end
    if after then
      after()
    end
    render()
  end)
end

local function findList(name)
  for _, l in ipairs(lists) do
    if l.name == name then
      return l
    end
  end
  return nil
end

local function inList(name, url)
  local l = findList(name)
  for _, t in ipairs(l and l.tracks or {}) do
    if t.url == url then
      return true
    end
  end
  return false
end

local function playlistOptions()
  local names = {}
  for _, l in ipairs(lists) do
    table.insert(names, l.name)
  end
  table.insert(names, "New playlist...")
  if tIdx > #names then
    tIdx = 1
  end
  return names
end

local function toggleFav(t)
  if inList("Favourites", t.url) then
    playlists.remove("Favourites", t.url, function() loadLists() end)
  else
    playlists.add("Favourites", { t }, function() loadLists() end)
  end
end

local function addToTarget(t, moveFrom)
  local names = playlistOptions()
  local creating = tIdx == #names
  local name = creating and noctalia.string.trim(newName) or names[tIdx]
  if name == "" then
    return
  end
  playlists.add(name, { t }, function(ok, used)
    if not ok then
      noctalia.notify("Music", "Could not write " .. playlists.dir)
      return
    end
    local function afterLoad()
      if creating then
        newName = ""
        tName = used
      end
    end
    if moveFrom then
      -- Moving: the track leaves the source only after it is safe in the target.
      playlists.remove(moveFrom, t.url, function() loadLists(afterLoad) end)
    else
      loadLists(afterLoad)
    end
  end)
end

-- Enter in the name field creates an empty playlist and makes it the target.
local function createList()
  local name = noctalia.string.trim(newName)
  if name == "" then
    return
  end
  playlists.add(name, {}, function(ok, used)
    if not ok then
      noctalia.notify("Music", "Could not write " .. playlists.dir)
      return
    end
    loadLists(function()
      newName = ""
      tName = used
    end)
  end)
end

local function removeFrom(name, url)
  playlists.remove(name, url, function() loadLists() end)
end

local function deleteList(name, key)
  if not lapse.armed(confirmRemove, key) then
    lapse.arm(confirmRemove, key, 5, render)
    render()
    return
  end
  lapse.disarm(confirmRemove, key)
  playlists.delete(name, function()
    if sel ~= nil and sel.src == "list" and sel.name == name then
      sel = nil
    end
    loadLists()
  end)
end

local function total(c)
  local sum = 0
  for _, t in ipairs(c.tracks) do
    local secs = mine.length(t.url)
    if secs == nil or secs < 0 then
      return ""
    end
    sum += secs
  end
  return #c.tracks > 0 and (", " .. mine.format(sum)) or ""
end

local CHUNK = 6

-- yt-dlp reads the lengths a few urls at a time so one slow video does not stall the rest.
local function fetchLengths(c, key)
  if fetching[key] then
    return
  end
  local todo = {}
  for _, t in ipairs(c.tracks) do
    if (mine.length(t.url) == nil or mine.meta(t.url) == nil) and not triedMeta[t.url] then
      triedMeta[t.url] = true
      table.insert(todo, t.url)
    end
  end
  if #todo == 0 then
    return
  end
  fetching[key] = true
  render()
  local function step(from)
    if from > #todo then
      fetching[key] = nil
      render()
      return
    end
    local part = {}
    for i = from, math.min(from + CHUNK - 1, #todo) do
      table.insert(part, todo[i])
    end
    csv.durations(part, function(found)
      if found then
        local secs, metas = {}, {}
        for u, f in pairs(found) do
          secs[u] = f.d
          metas[u] = { t = f.t, a = f.a }
        end
        mine.setLengths(secs)
        mine.setMetas(metas)
      end
      render()
      step(from + CHUNK)
    end)
  end
  step(1)
end

local function card(c, key, forceOpen, filter, src)
  local isOpen = forceOpen or open[key]
  local names = playlistOptions()
  local target = tIdx < #names and names[tIdx] or (noctalia.string.trim(newName) ~= "" and noctalia.string.trim(newName) or nil)
  local head = {
    ui.button({
      text = c.name .. "  (" .. #c.tracks .. (src == "list" and total(c) or "") .. ")",
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
  local deadUrls = {}
  if src == "mine" and c.name == "Recent" then
    table.insert(head, 2, ui.button({ glyph = "trash", variant = "ghost", controlSize = "sm", tooltip = "Clear Recent", onClick = function() mine.clearRecent() render() end }))
  end
  if src ~= "radio" then
    table.insert(head, 2, ui.button({ glyph = "clock", variant = "ghost", controlSize = "sm", enabled = not fetching[key], tooltip = fetching[key] and "Reading lengths" or "Read the track lengths with yt-dlp (about a minute)", onClick = function() fetchLengths(c, key) end }))
  end
  if src == "radio" then
    for _, t in ipairs(c.tracks) do
      if dead[t.url] then
        table.insert(deadUrls, t.url)
      end
    end
    table.insert(head, 2, ui.button({ glyph = "stethoscope", variant = "ghost", controlSize = "sm", enabled = not checking[key], tooltip = checking[key] and "Checking" or "Check which streams still answer", onClick = function() checkGroup(c, key) end }))
  end
  if src == "list" then
    table.insert(head, 2, ui.button({ glyph = "trash", variant = "ghost", controlSize = "sm", tooltip = "Delete this playlist", onClick = function() deleteList(c.name, key) end }))
  end
  local rows = { ui.row({ gap = 4, align = "center" }, head) }
  if src == "list" and lapse.armed(confirmRemove, key) then
    table.insert(rows, ui.row({ gap = 4, align = "center" }, {
      ui.button({ text = "Really delete " .. c.name .. "?", glyph = "trash", variant = "destructive", controlSize = "sm", flexGrow = 1, tooltip = "Deletes " .. c.name .. ".m3u", onClick = function() deleteList(c.name, key) end }),
      ui.button({ text = "Cancel", glyph = "x", variant = "outline", controlSize = "sm", onClick = function() lapse.disarm(confirmRemove, key) render() end }),
    }))
  end
  if #deadUrls > 0 then
    table.insert(rows, ui.row({ gap = 4, align = "center" }, {
      ui.button({ text = lapse.armed(confirmRemove, key) and ("Really remove " .. #deadUrls .. "?") or ("Remove " .. #deadUrls .. " dead"), glyph = "trash", variant = "destructive", controlSize = "sm", flexGrow = 1, tooltip = "Deletes them from stations.csv, a .bak copy stays", onClick = function() removeDead(c, key, deadUrls) end }),
      ui.button({ text = lapse.armed(confirmRemove, key) and "Cancel" or "Keep all", glyph = "x", variant = "outline", controlSize = "sm", tooltip = "Cancel: nothing is removed. Keep all: clear the red marks", onClick = function()
        if not lapse.armed(confirmRemove, key) then
          for _, u in ipairs(deadUrls) do
            dead[u] = nil
          end
        end
        lapse.disarm(confirmRemove, key)
        render()
      end }),
    }))
  end
  local shown = 0
  if isOpen then
    for i, t in ipairs(c.tracks) do
      if not filter or filter(t) then
        shown += 1
        -- No spacers: a spacer would share the free width with the title button and push the buttons off the edge.
        local cells = {
          ui.button({ text = t.title, glyph = t.url == playingUrl and "volume" or nil, variant = dead[t.url] and "destructive" or (t.url == playingUrl and "primary" or "ghost"), controlSize = "sm", contentAlign = "start", flexGrow = 1, tooltip = dead[t.url] and "No answer. Right click: keep this stream" or t.url, onClick = function() if filter or src == "mine" or not mine.opt("onward", true) then start({ t.url }, false, t.title) else start(c.playlist, false, t.title, i) end end, onRightClick = function() if dead[t.url] then dead[t.url] = nil lapse.disarm(confirmRemove, key) render() end end }),
        }
        if src ~= "radio" then
          table.insert(cells, ui.label({ text = mine.format(mine.length(t.url)), width = 56, fontSize = 11, color = "on_surface_variant" }))
        end
        if src == "list" then
          table.insert(cells, ui.button({ glyph = "arrows-exchange", variant = "ghost", controlSize = "sm", enabled = target ~= nil and target ~= c.name, tooltip = target ~= nil and target ~= c.name and ("Move to " .. target) or "Pick another playlist above to move it", onClick = function() addToTarget(t, c.name) end }))
          table.insert(cells, ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "Remove from " .. c.name, onClick = function() removeFrom(c.name, t.url) end }))
        else
          table.insert(cells, ui.button({ glyph = "playlist-add", variant = "ghost", controlSize = "sm", enabled = target ~= nil and not inList(target, t.url), tooltip = target ~= nil and ("Add to " .. target) or "Type a playlist name above", onClick = function() addToTarget(t) end }))
          table.insert(cells, ui.button({ glyph = inList("Favourites", t.url) and "star-filled" or "star", variant = "ghost", controlSize = "sm", tooltip = inList("Favourites", t.url) and "Remove from Favourites" or "Add to Favourites", onClick = function() toggleFav(t) end }))
        end
        table.insert(rows, ui.row({ key = key .. ":" .. i, gap = 4, align = "center" }, cells))
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
  if fAdding then
    return
  end
  fAdding = true
  csv.addStation(group, st.name, st.url, function(ok)
    fAdding = false
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
  if fResults and #fResults > 0 then
    for _, c in ipairs(radio) do
      for _, t in ipairs(c.tracks) do
        have[t.url] = true
      end
    end
  end
  local creating = fGroup == #names
  local target = creating and noctalia.string.trim(fNewGroup) or names[fGroup]
  local out = {
    ui.label({ text = "Find new radio stations online", fontSize = 14 }),
    ui.label({ text = "Searches radio-browser.info. Press play to try a stream, Add puts it in your PyRadio list.", fontSize = 11, color = "on_surface_variant" }),
    ui.row({ gap = 6, align = "center" }, {
      ui.input({ key = "fname", value = fName, placeholder = "search online: station name", controlSize = "sm", flexGrow = 1, focus = nameFocus, submitOnEnter = true,
        onChange = function(t) fName = t end, onSubmit = function(t) fName = t runSearch() end }),
      ui.input({ key = "ftag", value = fTag, placeholder = "genre (optional)", controlSize = "sm", width = 180, submitOnEnter = true,
        onChange = function(t) fTag = t end, onSubmit = function(t) fTag = t runSearch() end }),
      ui.button({ text = "Search", glyph = "search", variant = "primary", controlSize = "sm", enabled = not fBusy, onClick = runSearch }),
    }),
    ui.row({ gap = 6, align = "center" }, {
      ui.label({ text = "Add to PyRadio group", fontSize = 12, color = "on_surface_variant" }),
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

-- Every word of the search must occur in the list title, the stream's own title or artist, or the category name.
local function words(q)
  local list = {}
  for w in string.gmatch(string.lower(q), "%S+") do
    table.insert(list, w)
  end
  return list
end

local lowTitle = {} -- lowercased list titles, built once per url

local function trackMatches(t, toks, cname)
  local title = lowTitle[t.url]
  if not title then
    title = string.lower(t.title)
    lowTitle[t.url] = title
  end
  local mt = mine.meta(t.url)
  local stream = mt and string.lower(mt.t .. " " .. mt.a) or ""
  local name = string.lower(cname)
  for _, w in ipairs(toks) do
    if not (string.find(title, w, 1, true) or string.find(stream, w, 1, true) or string.find(name, w, 1, true)) then
      return false
    end
  end
  return true
end

local function body()
  if finder then
    return finderBody()
  end
  local q = string.lower(noctalia.string.trim(query))
  if sel ~= nil and sel.src == "mine" and q == "" then
    local c = mine.recent()
    if #c.tracks == 0 then
      return { ui.label({ text = "Nothing played yet", color = "on_surface_variant" }) }
    end
    return { (card(c, "mine:" .. c.name, true, nil, "mine")) }
  end
  if sel ~= nil and sel.src == "list" and q == "" then
    local c = findList(sel.name)
    if not c then
      return { ui.label({ text = "Playlist not found", color = "on_surface_variant" }) }
    end
    return { (card(c, "list:" .. c.name, true, nil, "list")) }
  end
  if #radio == 0 and #music == 0 then
    return { ui.label({ text = "No stations or tracks found", color = "on_surface_variant" }) }
  end
  local sources = { { "radio", radio }, { "music", music } }
  local cards, budget, totalHits = {}, MAX_SEARCH_ROWS, 0
  local toks = words(q)
  local found = {}
  for _, src_list in ipairs(sources) do
    local src, list = src_list[1], src_list[2]
    for _, c in ipairs(list) do
      local key = src .. ":" .. c.name
      if q ~= "" then
        local hits, hasPlaying = 0, false
        for _, t in ipairs(c.tracks) do
          if trackMatches(t, toks, c.name) then
            hits += 1
            hasPlaying = hasPlaying or t.url == playingUrl
          end
        end
        totalHits += hits
        if hits > 0 then
          table.insert(found, { c = c, key = key, src = src, first = hasPlaying })
        end
      elseif sel == nil or (sel.src == src and sel.name == c.name) then
        table.insert(cards, (card(c, key, sel ~= nil, nil, src)))
      end
    end
  end
  -- The card with the playing track is built first, so it gets rows even when the budget runs out.
  local order = {}
  for _, f in ipairs(found) do
    if f.first then
      table.insert(order, f)
    end
  end
  for _, f in ipairs(found) do
    if not f.first then
      table.insert(order, f)
    end
  end
  for _, f in ipairs(order) do
    if budget > 0 then
      local filter = function(t)
        if budget > 0 and trackMatches(t, toks, f.c.name) then
          budget -= 1
          return true
        end
        return false
      end
      table.insert(cards, (card(f.c, f.key, true, filter, f.src)))
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
  local result = { ui.row({ gap = 8, align = "start" }, out) }
  if q ~= "" then
    table.insert(result, 1, ui.label({ text = totalHits > MAX_SEARCH_ROWS and ("Showing " .. MAX_SEARCH_ROWS .. " of " .. totalHits .. " matches, add a word to narrow it") or (totalHits .. " matches"), fontSize = 11, color = "on_surface_variant" }))
  end
  return result
end

-- "src:name" of the first list holding the playing url (radio, music, playlists), cached until the url or the lists change.
local homeFor, homeCount, homeKey = "", -1, nil
local function playingHome()
  local n = #radio + #music + #lists
  if homeKey ~= playingUrl or homeCount ~= n then
    homeKey, homeCount, homeFor = playingUrl, n, ""
    if playingUrl ~= "" then
      for _, g in ipairs({ { "radio", radio }, { "music", music }, { "list", lists } }) do
        for _, c in ipairs(g[2]) do
          for _, tr in ipairs(c.tracks) do
            if tr.url == playingUrl then
              homeFor = g[1] .. ":" .. c.name
              return homeFor
            end
          end
        end
      end
    end
  end
  return homeFor
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
  -- A folded group still shows the rows in keep (the selected list and the one with the playing track).
  local function group(name, rows, keep)
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
    for i, r in ipairs(rows) do
      if isOpen or (keep and keep[i]) then
        table.insert(card, r)
      end
    end
    table.insert(items, ui.column({ fill = "surface_variant", radius = 10, padding = 8, gap = 4, border = "primary", borderWidth = 1 }, card))
  end
  local function entry(label, active, action, key)
    return ui.button({ key = key, text = label, glyph = active and "point-filled" or "point", variant = active and "outline" or "ghost", controlSize = "sm", contentAlign = "start", onClick = action })
  end
  table.insert(items, ui.button({ text = "All", variant = (sel == nil and query == "" and not finder) and "primary" or "ghost", controlSize = "sm", contentAlign = "start", onClick = function() pick(nil, nil) end }))
  table.insert(items, ui.button({ text = "Find stations", glyph = "search", variant = finder and "primary" or "ghost", controlSize = "sm", contentAlign = "start", onClick = function() finder, sel, query, fFocus = true, nil, "", true render() end }))
  local recentActive = sel ~= nil and sel.src == "mine"
  table.insert(items, ui.button({ text = "Recent", glyph = "history", variant = recentActive and "primary" or "ghost", controlSize = "sm", contentAlign = "start", onClick = function() pick("mine", "Recent") end }))
  for _, g in ipairs({ { "Playlists", "list", lists }, { "Radio", "radio", radio }, { "Music", "music", music } }) do
    if #g[3] > 0 then
      local rows, keep = {}, {}
      for _, c in ipairs(g[3]) do
        keep[#rows + 1] = playingHome() == g[2] .. ":" .. c.name or (sel ~= nil and sel.src == g[2] and sel.name == c.name)
        table.insert(rows, entry(c.name, sel ~= nil and sel.src == g[2] and sel.name == c.name, function() pick(g[2], c.name) end, "side:" .. g[2] .. ":" .. c.name))
      end
      group(g[1], rows, keep)
    end
  end
  local tools = {}
  local function tool(label, glyph, cmd)
    table.insert(tools, ui.button({ text = label, glyph = glyph, variant = "ghost", controlSize = "sm", contentAlign = "start", onClick = function() sh(cmd) panel.close() end }))
  end
  tool("Playlists folder", "folder", "xdg-open '" .. playlists.dir .. "'")
  tool("Edit radio list", "edit", "xdg-open '" .. csv.radioPath .. "'")
  tool("Edit mpv list", "edit", "xdg-open '" .. csv.path .. "'")
  tool("Radio browser", "world", "xdg-open https://www.radio-browser.info")
  group("Tools", tools)
  return ui.column({ width = 250, height = 446, gap = 2 }, { ui.scroll({ flexGrow = 1, key = "side", revealKey = revealSide }, { ui.column({ gap = 6 }, items) }) })
end

-- Source of the transport buttons, like the player list in the Noctalia Media panel.
local function sourceSelect()
  loadPin()
  -- The current source is on top; picking another one moves it there. A pinned source gets "Active player" at the end to follow Noctalia again.
  local top = pinned ~= "" and pinned or (activeName ~= "" and activeName or "No player")
  local entries, options = { { value = pinned } }, { top }
  for _, name in ipairs(players) do
    if name ~= top then
      table.insert(entries, { value = name })
      table.insert(options, name)
    end
  end
  if pinned ~= "" then
    table.insert(entries, { value = "" })
    table.insert(options, "Active player")
  end
  return ui.column({ gap = 0 }, {
    ui.label({ text = pinned == "" and "Active player" or "Pinned player", fontSize = 10, color = "on_surface_variant" }),
    ui.select({ key = "source" .. table.concat(options, "|"), width = 120, options = options, selectedIndex = 0, onChange = function(idx)
      local e = entries[tonumber(idx) + 1]
      if e and e.value ~= pinned then
        pinned = e.value
        savePin()
        render()
      end
    end }),
  })
end

-- "Add to playlist" chooser above the cards; the + on a row adds to the choice.
local function takeFocus()
  local f = plFocus
  plFocus = false
  return f
end

local function addRow()
  local names = playlistOptions()
  return ui.row({ gap = 6, align = "center" }, {
    ui.label({ text = "Add to playlist", fontSize = 12, color = "on_surface_variant" }),
    ui.select({ key = "plsel", width = 300, options = names, selectedIndex = tIdx - 1, onChange = function(idx)
      tIdx = tonumber(idx) + 1
      tName = tIdx < #names and names[tIdx] or ""
      plFocus = tIdx == #names
      render()
    end }),
    tIdx == #names and ui.input({ key = "plnew", value = newName, placeholder = "new playlist name, Enter creates it", controlSize = "sm", flexGrow = 1, focus = takeFocus(), submitOnEnter = true,
      onChange = function(t) newName = t render() end, onSubmit = function(t) newName = t createList() end }) or ui.spacer({ flexGrow = 1 }),
    tIdx == #names and ui.button({ glyph = "check", variant = "outline", controlSize = "sm", enabled = noctalia.string.trim(newName) ~= "", tooltip = "Create the playlist", onClick = createList }) or ui.spacer({ width = 0 }),
    sourceSelect(),
  })
end

render = function()
  local content = body()
  panel.render(ui.column({ gap = 8, padding = 12, height = 592 }, {
    ui.row({ gap = 8, align = "center" }, {
      logo(),
      ui.label({ text = "Music" }),
      ui.label({ text = hotkey("mabox/music:player"), color = "outline_variant" }),
      ui.spacer({ flexGrow = 1 }),
      ui.row({ gap = 2, padding = 4, radius = 20, fill = "surface_container", align = "center" }, {
        ui.button({ glyph = "player-skip-back", variant = "ghost", tooltip = "Previous", onClick = function() transport("previous") end }),
        ui.button({ glyph = "player-play", variant = "ghost", tooltip = "Pause / play", onClick = function() transport("toggle") end }),
        ui.button({ glyph = "player-skip-forward", variant = "ghost", tooltip = "Next", onClick = function() transport("next") end }),
        ui.button({ glyph = "player-stop", variant = "ghost", tooltip = "Stop", onClick = function() transport("stop") end }),
        (pinned == "" or pinned == "mpv") and ui.button({ glyph = "repeat-once", variant = player.isRepeating() and "primary" or "ghost", tooltip = player.isRepeating() and "Repeat this song (on)" or "Repeat this song (off)", onClick = function()
          player.setRepeat(not player.isRepeating())
          render()
        end }) or ui.spacer({ width = 0 }),
      }),
      ui.spacer({ flexGrow = 1 }),
      ui.button({ glyph = "refresh", variant = "ghost", controlSize = "sm", tooltip = "Refresh: show what plays now and add it to Recent", onClick = function() syncNow() end }),
      ui.button({ glyph = "radio", variant = "ghost", controlSize = "sm", tooltip = "PyRadio", onClick = function() sh("jumpapp -m -c pyradio kitty --class pyradio -e pyradio") panel.close() end }),
      ui.button({ glyph = "volume", variant = "ghost", controlSize = "sm", tooltip = "Volume control", onClick = function() sh("pavucontrol") panel.close() end }),
      ui.button({ glyph = "adjustments-horizontal", variant = eqOn and "primary" or "ghost", controlSize = "sm", tooltip = eqOn and "Equalizer (on)" or "Equalizer (off)", onClick = function() noctalia.runAsync({ "noctalia", "msg", "panel-toggle", "mabox/equalizer:main" }) panel.close() end }),
      ui.button({ glyph = "chart-bar", variant = cavaOn and "primary" or "ghost", controlSize = "sm", tooltip = "Click: visualiser on or off, right click: Cava settings", onClick = toggleCava, onRightClick = function() noctalia.runAsync({ "noctalia", "msg", "panel-toggle", "mabox/cava:main" }) end }),
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
      ui.button({ text = nowPlaying ~= "" and nowPlaying or "Nothing playing", variant = "ghost", controlSize = "sm", contentAlign = "start", flexGrow = 1, enabled = playingUrl ~= "", tooltip = "Show where it is in the lists", onClick = showPlaying }),
      ui.label({ text = playingCategory(), fontSize = 11, color = "primary" }),
      ui.button({ glyph = "playlist", variant = mine.opt("onward", true) and "outline" or "ghost", controlSize = "sm", tooltip = mine.opt("onward", true) and "Play on: a click starts the list from that track and skips streams that fail (on). Click to play only the track." or "Play only the clicked track (off). Click to play on and skip failing streams.", onClick = function() mine.setOpt("onward", not mine.opt("onward", true)) render() end }),
      ui.button({ text = sleepLabel(), glyph = sleepLeft > 0 and sleepOff and "power" or "moon", variant = sleepLeft > 0 and "outline" or "ghost", controlSize = "sm", tooltip = "Sleep timer: choose the minutes, optionally shut down the computer", onClick = function() sleepOpen = not sleepOpen; render() end }),
      ui.button({ text = "-" .. stepLabel(stepSecs()), glyph = "rewind-backward-10", variant = "ghost", controlSize = "sm", tooltip = "Jump back " .. stepLabel(stepSecs()) .. ". Right click: change the step", onClick = function() player.seek(-stepSecs()) end, onRightClick = nextStep }),
      ui.button({ text = "+" .. stepLabel(stepSecs()), glyph = "rewind-forward-10", variant = "ghost", controlSize = "sm", tooltip = "Jump forward " .. stepLabel(stepSecs()) .. ". Right click: change the step", onClick = function() player.seek(stepSecs()) end, onRightClick = nextStep }),
    }),
    sleepOpen and sleepRow() or ui.box({ height = 0 }),
    ui.row({ gap = 8, flexGrow = 1 }, {
      sidebar(),
      -- No spacer for the finder: it would share the free height with the list and push it down.
      finder and ui.scroll({ flexGrow = 1, key = "list", revealKey = revealRow }, content) or ui.column({ gap = 6, flexGrow = 1 }, {
        addRow(),
        ui.scroll({ flexGrow = 1, key = "list", revealKey = revealRow }, content),
      }),
    }),
  }))
  revealRow, revealSide = nil, nil
end

local function onClose()
  pollGen += 1
end

local function onOpen()
  pollGen += 1
  lastRemembered = nil
  listsLoaded.radio, listsLoaded.music = false, false
  revealRow, revealSide = nil, nil
  pollTitle(pollGen, 0)
  query = ""
  finder = false
  render()
  csv.radio(function(cats)
    radio = cats or {}
    listsLoaded.radio = true
    mergeRecent()
    render()
  end)
  csv.list(function(cats, all)
    music = cats or {}
    musicAll = all or {}
    listsLoaded.music = true
    mergeRecent()
    render()
  end)
  sleepLeft, _, sleepOff = mine.sleepLeft()
  sleepShut = sleepLeft > 0 and sleepOff
  refreshCava(0)
  loadLists(function()
    -- Favourites from before playlists existed move into Favourites.m3u once.
    local old = mine.oldFavs()
    if #old > 0 then
      playlists.add("Favourites", old, function(ok)
        if ok then
          mine.clearFavs()
          loadLists()
        end
      end)
    end
  end)
end

return { onClose = onClose, onOpen = onOpen }
end
