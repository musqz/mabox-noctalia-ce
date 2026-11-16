--!nonstrict
-- One mpv with an IPC socket (for mpv-mpris and the title lookup); a new play replaces the running one.

local RUNTIME = noctalia.getenv("XDG_RUNTIME_DIR")
if not RUNTIME or RUNTIME == "" then
  RUNTIME = "/tmp"
end
local SOCK = RUNTIME .. "/mpvsocket"
local LIST = RUNTIME .. "/mb-music-playlist.txt"

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
  local stop = "pkill -f " .. sq(PATTERN) .. "; for i in $(seq 1 30); do pgrep -f " .. sq(PATTERN) .. " >/dev/null || break; sleep 0.1; done; "
    .. "pkill -9 -f " .. sq(PATTERN) .. "; rm -f " .. sq(SOCK) .. "; true"
  noctalia.runAsync({ "sh", "-c", stop }, function()
    -- A newer play already took over; only the latest one starts an mpv.
    if gen ~= playGen then
      return
    end
    noctalia.runAsync("nohup mpv --no-video --force-window=no --input-ipc-server=" .. sq(SOCK)
      .. (shuffle and " --shuffle" or "") .. (from and from > 1 and (" --playlist-start=" .. (from - 1)) or "") .. " --playlist=" .. sq(LIST) .. " >/dev/null 2>&1 &")
  end)
  if not quiet then
    noctalia.notify("Music", label)
  end
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

local function split(line)
  local artist, title = string.match(line or "", "^([^\t]*)\t(.*)$")
  return noctalia.string.trim(artist or ""), noctalia.string.trim(title or line or "")
end

-- onDone gets the label MPRIS gives (what the bar shows), "" when nothing plays, and the raw title and artist. delay waits for mpv to open the stream.
function M.title(delay, onDone)
  local cmd = (delay > 0 and ("sleep " .. delay .. "; ") or "") .. "playerctl -p mpv metadata --format '{{artist}}\t{{title}}' 2>/dev/null"
  noctalia.runAsync({ "sh", "-c", cmd }, function(r)
    if r.exitCode ~= 0 then
      onDone("", "", "")
      return
    end
    local artist, title = split(string.match(r.stdout or "", "^([^\n]*)"))
    onDone(label(artist, title), title, artist)
  end)
end

-- After delay seconds: onDone(alive, label, path, playing, rawTitle, artist). alive is false when mpv is gone, which means every entry failed;
-- path is the url mpv has loaded and playing is true once it really makes sound (time-pos exists), not while yt-dlp still resolves it.
function M.verify(delay, onDone)
  local function ask(prop, tag)
    return "echo '{\"command\":[\"get_property\",\"" .. prop .. "\"]}' | socat - " .. sq(SOCK) .. " 2>/dev/null | sed 's/^/" .. tag .. "/'"
  end
  local cmd = "sleep " .. delay .. "; pgrep -x mpv >/dev/null || { echo __DEAD__; exit 0; }; "
    .. "playerctl -p mpv metadata --format '{{artist}}\t{{title}}' 2>/dev/null; echo; " .. ask("path", "__PATH__") .. "; " .. ask("time-pos", "__POS__")
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
    local path = prop("__PATH__")
    local artist, title = split(string.match(out, "^([^\n]*)"))
    onDone(true, label(artist, title), type(path) == "string" and path or "", prop("__POS__") ~= nil, title, artist)
  end)
end

return M
