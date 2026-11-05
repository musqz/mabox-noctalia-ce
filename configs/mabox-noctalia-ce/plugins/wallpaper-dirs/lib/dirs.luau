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
local BROWSE = [[p=$(yad --file --directory --center --width=1000 --height=650 --title="Wallpaper folder" --filename="$1/") || exit 0
if [ -n "$p" ]; then
  p=$(readlink -f "$p")
  grep -qxF -- "$p" "$2" 2>/dev/null || echo "$p" >> "$2"
fi
noctalia msg panel-close; noctalia msg panel-open mabox/wallpaper-dirs:dirs]]

function M.browse(start)
  noctalia.mkdirAll(noctalia.pluginDataDir())
  noctalia.runAsync({ "setsid", "-f", "sh", "-c", BROWSE, "sh", start, file() })
end

-- config-get prints the value single-quoted.
function M.current(cb)
  noctalia.runAsync({ "noctalia", "msg", "config-get", "wallpaper.directory" }, function(r)
    cb(r.exitCode == 0 and string.match(r.stdout or "", "^%s*'(/.-)'%s*$") or "")
  end)
end

return M
