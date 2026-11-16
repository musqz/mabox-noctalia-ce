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

function M.play(urls, shuffle, label, quiet, from)
  noctalia.writeFile(LIST, table.concat(urls, "\n") .. "\n")
  local cmd = "(echo '{\"command\":[\"quit\"]}' | socat - " .. sq(SOCK) .. " >/dev/null 2>&1 || true); "
    .. "for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [ -S " .. sq(SOCK) .. " ] || break; sleep 0.1; done; rm -f " .. sq(SOCK) .. "; "
    .. "nohup mpv --no-video --force-window=no --input-ipc-server=" .. sq(SOCK)
    .. (shuffle and " --shuffle" or "") .. (from and from > 1 and (" --playlist-start=" .. (from - 1)) or "") .. " --playlist=" .. sq(LIST) .. " >/dev/null 2>&1 &"
  noctalia.runAsync(cmd)
  if not quiet then
    noctalia.notify("Music", label)
  end
end

-- Jumps secs forward (negative: back) in the running mpv; a live stream just ignores it.
function M.seek(secs)
  noctalia.runAsync({ "sh", "-c", "echo '{\"command\":[\"seek\"," .. secs .. ",\"relative\"]}' | socat - " .. sq(SOCK) .. " >/dev/null 2>&1" })
end

-- onDone gets the title MPRIS reports (what the bar shows), or "" when nothing plays. delay waits for mpv to open the stream.
function M.title(delay, onDone)
  local cmd = (delay > 0 and ("sleep " .. delay .. "; ") or "") .. "playerctl metadata --format '{{title}}' 2>/dev/null"
  noctalia.runAsync({ "sh", "-c", cmd }, function(r)
    onDone(r.exitCode == 0 and noctalia.string.trim(r.stdout or "") or "")
  end)
end

-- After delay seconds: onDone(alive, title, path, playing). alive is false when mpv is gone, which means every entry failed;
-- path is the url mpv has loaded and playing is true once it really makes sound (time-pos exists), not while yt-dlp still resolves it.
function M.verify(delay, onDone)
  local function ask(prop, tag)
    return "echo '{\"command\":[\"get_property\",\"" .. prop .. "\"]}' | socat - " .. sq(SOCK) .. " 2>/dev/null | sed 's/^/" .. tag .. "/'"
  end
  local cmd = "sleep " .. delay .. "; pgrep -x mpv >/dev/null || { echo __DEAD__; exit 0; }; "
    .. "playerctl metadata --format '{{title}}' 2>/dev/null; echo; " .. ask("path", "__PATH__") .. "; " .. ask("time-pos", "__POS__")
  noctalia.runAsync({ "sh", "-c", cmd }, function(r)
    local out = r.stdout or ""
    if string.find(out, "__DEAD__", 1, true) then
      onDone(false, "", "", false)
      return
    end
    local function prop(tag)
      local ok, data = pcall(noctalia.json.decode, string.match(out, tag .. "([^\n]*)") or "")
      return ok and type(data) == "table" and data.error == "success" and data.data or nil
    end
    local path = prop("__PATH__")
    onDone(true, noctalia.string.trim(string.match(out, "^([^\n]*)") or ""), type(path) == "string" and path or "", prop("__POS__") ~= nil)
  end)
end

return M
