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

function M.play(urls, shuffle, label, quiet)
  noctalia.writeFile(LIST, table.concat(urls, "\n") .. "\n")
  local cmd = "(echo '{\"command\":[\"quit\"]}' | socat - " .. sq(SOCK) .. " >/dev/null 2>&1 || true); "
    .. "for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [ -S " .. sq(SOCK) .. " ] || break; sleep 0.1; done; rm -f " .. sq(SOCK) .. "; "
    .. "nohup mpv --no-video --force-window=no --input-ipc-server=" .. sq(SOCK)
    .. (shuffle and " --shuffle" or "") .. " --playlist=" .. sq(LIST) .. " >/dev/null 2>&1 &"
  noctalia.runAsync(cmd)
  if not quiet then
    noctalia.notify("Music", label)
  end
end

-- onDone gets the title MPRIS reports (what the bar shows), or "" when nothing plays. delay waits for mpv to open the stream.
function M.title(delay, onDone)
  local cmd = (delay > 0 and ("sleep " .. delay .. "; ") or "") .. "playerctl metadata --format '{{title}}' 2>/dev/null"
  noctalia.runAsync({ "sh", "-c", cmd }, function(r)
    onDone(r.exitCode == 0 and noctalia.string.trim(r.stdout or "") or "")
  end)
end

return M
