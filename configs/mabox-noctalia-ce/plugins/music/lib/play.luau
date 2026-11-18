--!nonstrict
-- One mpv with an IPC socket (for mpv-mpris and the title lookup); a new play replaces the running one.

local RUNTIME = noctalia.getenv("XDG_RUNTIME_DIR")
if not RUNTIME or RUNTIME == "" then
  RUNTIME = "/tmp"
end
local SOCK = RUNTIME .. "/mpvsocket"
local LIST = RUNTIME .. "/mb-music-playlist.txt"
-- mpv runs the script, so it only goes in the private runtime dir, never in /tmp.
local SAFE = RUNTIME ~= "/tmp"
local RECENT_LOG = RUNTIME .. "/mb-music-recent.log"
local RECENT_SCRIPT = RUNTIME .. "/mb-music-recent.lua"

-- mpv script: an entry that is still playing after 4 s is appended to the log, also while the panel is closed
-- (a track skipped at once is not logged).
local RECENT_LUA = [[local log = mp.get_opt("mbrecent-log")
local timer
mp.register_event("file-loaded", function()
  local p = mp.get_property("path")
  if timer then
    timer:kill()
  end
  timer = mp.add_timeout(4, function()
    if log and p and p ~= "" then
      local f = io.open(log, "a")
      if f then
        f:write(p, "\n")
        f:close()
      end
    end
  end)
end)
]]

local function sq(s)
  return "'" .. string.gsub(s, "'", "'\\''") .. "'"
end

local M = {}

-- Every mpv of the panel carries our socket in its command line; killing by that match leaves other mpv windows alone and also
-- ends an old mpv that never answered the IPC quit (one still resolving a stream), which used to keep playing next to the new one.
-- The [-] keeps pkill from matching its own shell.
local PATTERN = "[-]-input-ipc-server=" .. SOCK

local playGen = 0

function M.play(urls, shuffle, label, quiet, from)
  playGen += 1
  local gen = playGen
  noctalia.writeFile(LIST, table.concat(urls, "\n") .. "\n")
  if SAFE then
    noctalia.writeFile(RECENT_SCRIPT, RECENT_LUA)
  end
  local stop = "pkill -f " .. sq(PATTERN) .. "; for i in $(seq 1 30); do pgrep -f " .. sq(PATTERN) .. " >/dev/null || break; sleep 0.1; done; "
    .. "pkill -9 -f " .. sq(PATTERN) .. "; rm -f " .. sq(SOCK) .. "; true"
  noctalia.runAsync({ "sh", "-c", stop }, function()
    -- A newer play already took over; only the latest one starts an mpv.
    if gen ~= playGen then
      return
    end
    noctalia.runAsync("nohup mpv --no-video --force-window=no --input-ipc-server=" .. sq(SOCK)
      .. (SAFE and (" --script=" .. sq(RECENT_SCRIPT) .. " --script-opts=mbrecent-log=" .. sq(RECENT_LOG)) or "")
      .. (shuffle and " --shuffle" or "") .. (from and from > 1 and (" --playlist-start=" .. (from - 1)) or "") .. " --playlist=" .. sq(LIST) .. " >/dev/null 2>&1 &")
  end)
  if not quiet then
    noctalia.notify("Music", label)
  end
end

-- The urls mpv loaded since the last call, oldest first; the log is emptied.
function M.drainRecent(onDone)
  if not SAFE then
    onDone({})
    return
  end
  local cmd = 'f=$1; [ -s "$f" ] && mv "$f" "$f.$$" && { tail -n 15 "$f.$$"; rm -f "$f.$$"; }; true'
  noctalia.runAsync({ "sh", "-c", cmd, "sh", RECENT_LOG }, function(r)
    local urls = {}
    for l in string.gmatch(r.stdout or "", "[^\n]+") do
      table.insert(urls, l)
    end
    onDone(urls)
  end)
end

-- Jumps secs forward (negative: back) in the running mpv; a live stream just ignores it.
function M.seek(secs)
  noctalia.runAsync({ "sh", "-c", "echo '{\"command\":[\"seek\"," .. secs .. ",\"relative\"]}' | socat - " .. sq(SOCK) .. " >/dev/null 2>&1" })
end

-- "Artist - Title" the way the bar shows it; just the title when there is no artist or the title already starts with it.
local function label(artist, title)
  local lowTitle, lowArtist = string.lower(tostring(title)), string.lower(tostring(artist))
  if lowArtist ~= "" and lowTitle ~= "" and string.sub(lowTitle, 1, #lowArtist) ~= lowArtist then
    return artist .. " - " .. title
  end
  return title
end

-- After delay seconds: onDone(alive, label, path, playing, rawTitle, artist). alive is false when our mpv is gone, which means every entry failed;
-- path is the url it has loaded and playing is true once it really makes sound (time-pos exists), not while yt-dlp still resolves it.
-- Other mpv windows (a copied url from C-S-1) have an MPRIS player too, so the player is picked by the title our own mpv reports.
function M.verify(delay, onDone)
  local function ask(prop, tag)
    return "echo '{\"command\":[\"get_property\",\"" .. prop .. "\"]}' | socat - " .. sq(SOCK) .. " 2>/dev/null | sed 's/^/" .. tag .. "/'"
  end
  local cmd = "sleep " .. delay .. "; pgrep -f " .. sq(PATTERN) .. " >/dev/null || { echo __DEAD__; exit 0; }; "
    .. ask("path", "__PATH__") .. "; " .. ask("time-pos", "__POS__") .. "; " .. ask("media-title", "__MT__") .. "; "
    .. "for p in $(playerctl -l 2>/dev/null | grep '^mpv'); do printf '__PL__%s\t' \"$p\"; "
    .. "playerctl -p \"$p\" metadata --format '{{status}}\t{{artist}}\t{{title}}' 2>/dev/null; echo; done"
  noctalia.runAsync({ "sh", "-c", cmd }, function(r)
    local out = r.stdout or ""
    if string.find(out, "__DEAD__", 1, true) then
      onDone(false, "", "", false, "", "")
      return
    end
    local function prop(tag)
      local ok, data = pcall(noctalia.json.decode, string.match(out, tag .. "([^\n]*)") or "")
      return ok and type(data) == "table" and data.error == "success" and data.data or nil
    end
    local path, mediaTitle = prop("__PATH__"), prop("__MT__")
    local chosen, playingOne, first
    for line in string.gmatch(out, "__PL__([^\n]*)") do
      local _, status, artist, title = string.match(line, "^([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
      if status then
        local entry = { artist = noctalia.string.trim(artist), title = noctalia.string.trim(title) }
        first = first or entry
        if status == "Playing" then
          playingOne = playingOne or entry
        end
        if type(mediaTitle) == "string" and entry.title == noctalia.string.trim(mediaTitle) then
          chosen = chosen or entry
        end
      end
    end
    chosen = chosen or playingOne or first or { artist = "", title = "" }
    onDone(true, label(chosen.artist, chosen.title), type(path) == "string" and path or "", prop("__POS__") ~= nil, chosen.title, chosen.artist)
  end)
end

-- onDone gets the label (what the bar shows), "" when nothing plays, and the raw title and artist. delay waits for mpv to open the stream.
function M.title(delay, onDone)
  M.verify(delay, function(alive, text, _, _, title, artist)
    onDone(alive and text or "", title, artist)
  end)
end

return M
