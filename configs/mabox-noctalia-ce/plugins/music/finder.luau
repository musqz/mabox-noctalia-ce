--!nonstrict
-- /music: browse categories and tracks from the mb-music CSV, play or shuffle through mpv.
-- Transport (pause/next/prev/stop) goes through MPRIS: `noctalia msg media <action>`.

local csv = require("./lib/csv.luau")
local play = require("./lib/play.luau").play

local function trackRow(t, score)
  return { id = "play:" .. t.url, title = t.title, subtitle = "Enter to play", glyph = "player-play", score = score }
end

local function respond(text, q, cats)
  do
    local rows = {}

    if #cats == 0 then
      launcher.setResults(text, { { id = "", title = "No tracks in " .. csv.path, glyph = "music-off" } })
      return
    end

    for _, c in cats do
      if string.lower(c.name) == string.lower(q) then
        table.insert(rows, { id = "shuffle:" .. c.name, title = "Shuffle " .. c.name, glyph = "arrows-shuffle", score = 1000 })
        table.insert(rows, { id = "playcat:" .. c.name, title = "Play " .. c.name, glyph = "player-play", score = 999 })
        for i, t in c.tracks do
          table.insert(rows, trackRow(t, 900 - i))
        end
        launcher.setResults(text, rows)
        return
      end
    end

    if q == "" then
      table.insert(rows, { id = "shuffle:", title = "Shuffle all", glyph = "arrows-shuffle", score = 1000 })
      for i, c in cats do
        table.insert(rows, { id = "cat:" .. c.name, title = c.name, subtitle = #c.tracks .. " tracks", glyph = "folder", score = 900 - i })
      end
      launcher.setResults(text, rows)
      return
    end

    for _, c in cats do
      local s = noctalia.fuzzyScore(q, c.name)
      if s ~= nil then
        table.insert(rows, { id = "cat:" .. c.name, title = c.name, subtitle = #c.tracks .. " tracks", glyph = "folder", score = 500 + s })
      end
      for _, t in c.tracks do
        local ts = noctalia.fuzzyScore(q, t.title)
        if ts ~= nil then
          table.insert(rows, trackRow(t, ts))
        end
      end
    end
    if #rows == 0 then
      rows[1] = { id = "", title = "Nothing matches '" .. q .. "'", glyph = "mood-empty" }
    end
    launcher.setResults(text, rows)
  end
end

-- Typing narrows the list that the empty query loaded, so only that one starts python.
local cache

function onQuery(text)
  local q = noctalia.string.trim(text or "")
  if q ~= "" and cache then
    respond(text, q, cache)
    return
  end
  csv.list(function(cats)
    cache = cats
    respond(text, q, cats or {})
  end)
end

function onActivate(id)
  if id == nil or id == "" then
    return
  end
  local kind, arg = string.match(id, "^(%a+):(.*)$")
  if kind == "play" then
    play({ arg }, false, "Playing track")
    return
  end
  if kind == "cat" then
    launcher.setQuery(arg)
    return
  end
  if kind ~= "shuffle" and kind ~= "playcat" then
    return
  end
  csv.list(function(cats, all)
    if cats then
      local urls = all
      if arg ~= "" then
        urls = {}
        for _, c in cats do
          if c.name == arg then
            urls = c.playlist
          end
        end
      end
      if #urls > 0 then
        local shuffle = kind == "shuffle"
        play(urls, shuffle, (shuffle and "Shuffling " or "Playing ") .. (arg == "" and "all" or arg))
      end
    end
  end)
end
