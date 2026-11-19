--!nonstrict
-- Favourites and recently played, kept in the plugin data dir, and the sleep timer (a user systemd timer that stops playback).

local MAX_RECENT = 15
local favs, recent, opts, loaded = {}, {}, {}, false

local function dir()
  return noctalia.pluginDataDir()
end

local function load()
  if loaded then
    return
  end
  loaded = true
  local d = dir()
  local data = d and noctalia.readFile(d .. "/mine.json")
  local ok, t = pcall(noctalia.json.decode, data or "")
  if ok and type(t) == "table" then
    favs, recent, opts = t.favs or {}, t.recent or {}, t.opts or {}
  end
end

local function save()
  local d = dir()
  if d then
    noctalia.mkdirAll(d)
    noctalia.writeFile(d .. "/mine.json", noctalia.json.encode({ favs = favs, recent = recent, opts = opts }))
  end
end

local function catalog(name, list)
  local urls = {}
  for _, t in ipairs(list) do
    table.insert(urls, t.url)
  end
  return { name = name, tracks = list, playlist = urls }
end

local M = {}

local lengths, lengthsLoaded = {}, false

local function loadLengths()
  if lengthsLoaded then
    return
  end
  lengthsLoaded = true
  local d = dir()
  local ok, t = pcall(noctalia.json.decode, d and noctalia.readFile(d .. "/lengths.json") or "")
  if ok and type(t) == "table" then
    lengths = t
  end
end

-- Seconds of a track, -1 for a live stream, nil when unknown.
function M.length(url)
  loadLengths()
  return lengths[url]
end

function M.setLengths(found)
  loadLengths()
  for u, secs in pairs(found) do
    lengths[u] = secs
  end
  local d = dir()
  if d then
    noctalia.mkdirAll(d)
    noctalia.writeFile(d .. "/lengths.json", noctalia.json.encode(lengths))
  end
end

-- What the stream itself calls the track: { t = title, a = artist }, filled from yt-dlp and from what played, so a search finds "1985".
local metas, metasLoaded = {}, false

local function loadMetas()
  if metasLoaded then
    return
  end
  metasLoaded = true
  local d = dir()
  local ok, t = pcall(noctalia.json.decode, d and noctalia.readFile(d .. "/meta.json") or "")
  if ok and type(t) == "table" then
    metas = t
  end
end

function M.meta(url)
  loadMetas()
  return metas[url]
end

function M.setMetas(found)
  loadMetas()
  local changed = false
  for u, mt in pairs(found) do
    local old = metas[u]
    if mt.t ~= "" and (not old or old.t ~= mt.t or old.a ~= mt.a) then
      metas[u] = { t = mt.t, a = mt.a }
      changed = true
    end
  end
  local d = dir()
  if changed and d then
    noctalia.mkdirAll(d)
    noctalia.writeFile(d .. "/meta.json", noctalia.json.encode(metas))
  end
end

function M.format(secs)
  if secs == nil then
    return ""
  end
  if secs < 0 then
    return "live"
  end
  local h, mn, sc = secs // 3600, (secs % 3600) // 60, secs % 60
  if h > 0 then
    return string.format("%d:%02d:%02d", h, mn, sc)
  end
  return string.format("%d:%02d", mn, sc)
end

function M.opt(name, default)
  load()
  if opts[name] == nil then
    return default
  end
  return opts[name]
end

function M.setOpt(name, value)
  load()
  opts[name] = value
  save()
end

function M.recent()
  load()
  return catalog("Recent", recent)
end

-- Favourites from before playlists existed; clearFavs once they are safe in Favourites.m3u.
function M.oldFavs()
  load()
  return favs
end

function M.clearFavs()
  load()
  favs = {}
  save()
end

function M.clearRecent()
  load()
  recent = {}
  save()
end

-- items: { title, url } pairs, oldest first; one save for all.
function M.addRecentMany(items)
  load()
  for _, it in ipairs(items) do
    for i, t in ipairs(recent) do
      if t.url == it.url then
        table.remove(recent, i)
        break
      end
    end
    table.insert(recent, 1, { title = it.title, url = it.url })
  end
  while #recent > MAX_RECENT do
    table.remove(recent)
  end
  save()
end

function M.addRecent(title, url)
  load()
  for i, t in ipairs(recent) do
    if t.url == url then
      table.remove(recent, i)
      break
    end
  end
  table.insert(recent, 1, { title = title, url = url })
  while #recent > MAX_RECENT do
    table.remove(recent)
  end
  save()
end

-- Sleep timer: the file holds "<end epoch> <minutes> <1 when the computer shuts down>".
M.SLEEP_PRESETS = { 15, 30, 45, 60, 90, 120, 180 }

local function sleepFile()
  local d = dir()
  return d and d .. "/sleep" or nil
end

-- The timer runs in the systemd user manager, which has no WAYLAND_DISPLAY: noctalia msg answers "noctalia is not running" there.
-- So it ends the panel's mpv directly, by its IPC socket (same path as SOCK in play.luau); the [-] keeps pkill from matching its own shell.
local function stopCmd()
  local runtime = noctalia.getenv("XDG_RUNTIME_DIR")
  if not runtime or runtime == "" then
    runtime = "/tmp"
  end
  return "pkill -f '[-]-input-ipc-server=" .. runtime .. "/mpvsocket'; true"
end

-- Returns minutes left, the minutes it was set to, and whether the computer shuts down at the end; 0 when no timer runs.
function M.sleepLeft()
  local f = sleepFile()
  local endAt, mins, off = string.match(f and noctalia.readFile(f) or "", "^(%d+) (%d+) ?(%d?)")
  if not endAt then
    return 0, 0, false
  end
  local left = tonumber(endAt) - os.time()
  if left <= 0 then
    return 0, 0, false
  end
  return math.ceil(left / 60), tonumber(mins), off == "1"
end

local STOP_UNITS = "systemctl --user stop mb-music-sleep.timer mb-music-sleep.service 2>/dev/null; "

-- Schedules the stop (and poweroff) in secs seconds and records it; onDone runs once the state is final.
local function schedule(secs, mins, poweroff, onDone)
  local f = sleepFile()
  if not f or secs < 1 then
    onDone()
    return
  end
  noctalia.mkdirAll(dir())
  local job = stopCmd() .. (poweroff and "; systemctl poweroff" or "")
  noctalia.runAsync({ "systemd-run", "--user", "--quiet", "--unit=mb-music-sleep", "--on-active=" .. secs .. "s", "sh", "-c", job }, function(r)
    if r.exitCode == 0 then
      noctalia.writeFile(f, (os.time() + secs) .. " " .. mins .. " " .. (poweroff and "1" or "0"))
    else
      noctalia.notify("Music", "Could not start the sleep timer")
    end
    onDone()
  end)
end

local function replace(secs, mins, poweroff, onDone)
  noctalia.runAsync({ "sh", "-c", STOP_UNITS .. "true" }, function()
    schedule(secs, mins, poweroff, onDone)
  end)
end

-- Starts (or restarts) the timer; poweroff makes it shut the computer down after the music stops.
function M.startSleep(minutes, poweroff, onDone)
  replace(minutes * 60, minutes, poweroff, onDone)
end

-- Changes the shutdown flag of the running timer; it keeps its end time and its preset.
function M.setSleepPoweroff(poweroff, onDone)
  local f = sleepFile()
  local endAt, mins = string.match(f and noctalia.readFile(f) or "", "^(%d+) (%d+)")
  local secs = endAt and tonumber(endAt) - os.time() or 0
  if secs < 1 then
    onDone()
    return
  end
  replace(secs, tonumber(mins), poweroff, onDone)
end

function M.cancelSleep(onDone)
  local f = sleepFile()
  if not f then
    onDone()
    return
  end
  noctalia.mkdirAll(dir())
  noctalia.writeFile(f, "0 0")
  noctalia.runAsync({ "sh", "-c", STOP_UNITS .. "true" }, function()
    onDone()
  end)
end

return M
