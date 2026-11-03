--!nonstrict
-- Pinned windows: one side (left or right) for all mabox plugins, saved in
-- ~/.config/mabox-noctalia-ce/pinned-side. Keep this file identical in every plugin's lib/.
local M = {}

local function path()
  return noctalia.getenv("HOME") .. "/.config/mabox-noctalia-ce/pinned-side"
end

local function id(plugin, side)
  return "mabox/" .. plugin .. ":pinned-" .. side
end

function M.get()
  return string.find(noctalia.readFile(path()) or "", "right", 1, true) and "right" or "left"
end

function M.toggle(plugin)
  noctalia.runAsync({ "noctalia", "msg", "panel-toggle", id(plugin, M.get()) })
end

-- From a pinned window: save the other side for all plugins and reopen this window there; windows of other plugins that are open stay until moved or closed.
function M.swap(plugin, current)
  local other = current == "left" and "right" or "left"
  noctalia.writeFile(path(), other .. "\n")
  panel.close()
  noctalia.runAsync({ "noctalia", "msg", "panel-open", id(plugin, other) })
end

return M
