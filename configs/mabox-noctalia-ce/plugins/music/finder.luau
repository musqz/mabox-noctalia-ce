--!nonstrict
-- /music: browse categories and tracks from the mb-music CSV, play or shuffle through mpv.
-- Transport (pause/next/prev/stop) goes through MPRIS: `noctalia msg media <action>`.

local CSV = noctalia.getenv("HOME") .. "/.config/mabox/mb-music/yt_music_list.csv"
local RUNTIME = noctalia.getenv("XDG_RUNTIME_DIR")
if not RUNTIME or RUNTIME == "" then
  RUNTIME = "/tmp"
end
local SOCK = RUNTIME .. "/mpvsocket"
local LIST = RUNTIME .. "/mb-music-playlist.txt"

local function sq(s)
  return "'" .. string.gsub(s, "'", "'\\''") .. "'"
end

-- Returns { {name=, tracks={ {title=, url=} }} } in file order.
local function loadCategories()
  local raw = noctalia.readFile(CSV)
  local cats, cur = {}, nil
  if not raw then
    return cats
  end
  for line in string.gmatch(raw, "[^\r\n]+") do
    local title, url = string.match(line, "^(.*),([^,]*)$")
    if title then
      url = noctalia.string.trim(url)
      if url == "-" then
        local name = noctalia.string.trim((string.gsub(title, "^[^%w]+", "")))
        if string.upper(name) == "END" then
          cur = nil
        else
          cur = { name = name, tracks = {} }
          table.insert(cats, cur)
        end
      elseif cur and string.match(url, "^https?://") then
        table.insert(cur.tracks, { title = noctalia.string.trim(title), url = url })
      end
    end
  end
  return cats
end

local function play(urls, shuffle, label)
  noctalia.writeFile(LIST, table.concat(urls, "\n") .. "\n")
  local cmd = "(echo '{\"command\":[\"quit\"]}' | socat - " .. sq(SOCK) .. " >/dev/null 2>&1 || true); "
    .. "for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [ -S " .. sq(SOCK) .. " ] || break; sleep 0.1; done; rm -f " .. sq(SOCK) .. "; "
    .. "nohup mpv --no-video --force-window=no --input-ipc-server=" .. sq(SOCK)
    .. (shuffle and " --shuffle" or "") .. " --playlist=" .. sq(LIST) .. " >/dev/null 2>&1 &"
  noctalia.runAsync(cmd)
  noctalia.notify("Music", label)
end

local function allUrls(cats)
  local urls = {}
  for _, c in cats do
    for _, t in c.tracks do
      table.insert(urls, t.url)
    end
  end
  return urls
end

local function trackRow(t, score)
  return { id = "play:" .. t.url, title = t.title, subtitle = "Enter to play", glyph = "player-play", score = score }
end

function onQuery(text)
  local q = noctalia.string.trim(text or "")
  local cats = loadCategories()
  local rows = {}

  if #cats == 0 then
    launcher.setResults(text, { { id = "", title = "No tracks in " .. CSV, glyph = "music-off" } })
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

function onActivate(id)
  if id == nil or id == "" then
    return
  end
  local kind, arg = string.match(id, "^(%a+):(.*)$")
  local cats = loadCategories()
  if kind == "cat" then
    launcher.setQuery(arg)
  elseif kind == "play" then
    play({ arg }, false, "Playing track")
  elseif kind == "shuffle" or kind == "playcat" then
    local urls = {}
    if arg == "" then
      urls = allUrls(cats)
    else
      for _, c in cats do
        if c.name == arg then
          for _, t in c.tracks do
            table.insert(urls, t.url)
          end
        end
      end
    end
    if #urls > 0 then
      local shuffle = kind == "shuffle"
      play(urls, shuffle, (shuffle and "Shuffling " or "Playing ") .. (arg == "" and "all" or arg))
    end
  end
end
