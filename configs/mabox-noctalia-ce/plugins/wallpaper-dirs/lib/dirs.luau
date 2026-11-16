--!nonstrict
-- Saved wallpaper folders, one absolute path per line in the plugin data dir.
local M = {}

local function file()
  return noctalia.pluginDataDir() .. "/dirs"
end

function M.load()
  local out = {}
  for line in string.gmatch(noctalia.readFile(file()) or "", "[^\n]+") do
    table.insert(out, line)
  end
  return out
end

function M.save(list)
  noctalia.mkdirAll(noctalia.pluginDataDir())
  return noctalia.writeFile(file(), table.concat(list, "\n") .. "\n")
end

function M.name(path)
  return string.match(path, "([^/]+)/*$") or path
end

-- mb-wallpaper-dir checks the folder and notifies; it exits non-zero when nothing is set.
function M.apply(path, cb)
  noctalia.runAsync({ "mb-wallpaper-dir", path }, function(r)
    if cb then
      cb(r)
    end
  end)
end

-- Runs detached (setsid) so the dialog survives the panel closing; adds the pick to the list and reopens the panel.
local BROWSE = [[p=$(yad --file --directory --center --width=1000 --height=650 --title="Wallpaper folder" --filename="$1/")
[ -n "$p" ] || [ "$3" = panel ] || exit 0
if [ -n "$p" ]; then
  p=$(readlink -f "$p")
  grep -qxF -- "$p" "$2" 2>/dev/null || echo "$p" >> "$2"
fi
noctalia msg panel-close; noctalia msg panel-open mabox/wallpaper-dirs:dirs]]

function M.browse(start, fromPanel)
  noctalia.mkdirAll(noctalia.pluginDataDir())
  noctalia.runAsync({ "setsid", "-f", "sh", "-c", BROWSE, "sh", start, file(), fromPanel and "panel" or "" })
end

-- The folder in use, read from Noctalia's state file: no process, so it cannot fail when many config-get calls run at once.
function M.currentSync()
  local base = noctalia.getenv("XDG_STATE_HOME")
  if not base or base == "" then
    base = noctalia.getenv("HOME") .. "/.local/state"
  end
  local inside = false
  for line in string.gmatch(noctalia.readFile(base .. "/noctalia/settings.toml") or "", "[^\n]+") do
    local h = string.match(line, "^%s*%[([^%]]+)%]%s*$")
    if h then
      inside = h == "wallpaper"
    elseif inside then
      local v = string.match(line, '^directory%s*=%s*"(.-)"') or string.match(line, "^directory%s*=%s*'(.-)'")
      if v then
        return v
      end
    end
  end
  return ""
end

-- config-get prints the value single-quoted.
function M.current(cb)
  noctalia.runAsync({ "noctalia", "msg", "config-get", "wallpaper.directory" }, function(r)
    cb(r.exitCode == 0 and string.match(r.stdout or "", "^%s*'(/.-)'%s*$") or "")
  end)
end

-- Slideshow interval in minutes; the config stores seconds.
function M.interval(cb)
  noctalia.runAsync({ "noctalia", "msg", "config-get", "wallpaper.automation.interval_seconds" }, function(r)
    local secs = tonumber(string.match(r.stdout or "", "%d+"))
    cb(r.exitCode == 0 and secs and math.max(1, math.floor(secs / 60 + 0.5)) or nil)
  end)
end

function M.setInterval(minutes, cb)
  noctalia.runAsync({ "noctalia", "msg", "config-set", "wallpaper.automation.interval_seconds", tostring(minutes * 60) }, function(r)
    cb(r.exitCode == 0)
  end)
end

-- config-get prints strings single-quoted and booleans bare.
function M.getAuto(key, cb)
  noctalia.runAsync({ "noctalia", "msg", "config-get", "wallpaper.automation." .. key }, function(r)
    cb(r.exitCode == 0 and string.match(r.stdout or "", "^%s*'?([%w_]+)'?%s*$") or nil)
  end)
end

function M.setAuto(key, value, cb)
  noctalia.runAsync({ "noctalia", "msg", "config-set", "wallpaper.automation." .. key, value }, function(r)
    cb(r.exitCode == 0)
  end)
end

-- Generic wallpaper.* keys (transition settings).
function M.get(key, cb)
  noctalia.runAsync({ "noctalia", "msg", "config-get", "wallpaper." .. key }, function(r)
    cb(r.exitCode == 0 and noctalia.string.trim(r.stdout or "") or nil)
  end)
end

function M.set(key, value, cb)
  noctalia.runAsync({ "noctalia", "msg", "config-set", "wallpaper." .. key, value }, function(r)
    cb(r.exitCode == 0)
  end)
end

return M
