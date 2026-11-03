--!nonstrict
-- Pinned windows: the side (left or right) per plugin, one "plugin=side" line each in
-- ~/.config/mabox-noctalia-ce/pinned-side. Keep this file identical in every plugin's lib/.
local M = {}

local function path()
  return noctalia.getenv("HOME") .. "/.config/mabox-noctalia-ce/pinned-side"
end

local function id(plugin, side)
  return "mabox/" .. plugin .. ":pinned-" .. side
end

local function read()
  local sides = {}
  for l in string.gmatch(noctalia.readFile(path()) or "", "[^\n]+") do
    local k, v = string.match(l, "^(%S+)=(%S+)$")
    if k then
      sides[k] = v
    end
  end
  return sides
end

function M.get(plugin)
  return read()[plugin] == "right" and "right" or "left"
end

function M.set(plugin, side)
  local sides = read()
  sides[plugin] = side
  local keys = {}
  for k in pairs(sides) do
    table.insert(keys, k)
  end
  table.sort(keys)
  local out = {}
  for _, k in ipairs(keys) do
    table.insert(out, k .. "=" .. sides[k])
  end
  noctalia.writeFile(path(), table.concat(out, "\n") .. "\n")
end

function M.toggle(plugin)
  noctalia.runAsync({ "noctalia", "msg", "panel-toggle", id(plugin, M.get(plugin)) })
end

-- From a pinned window: move this plugin's window to the other side.
function M.swap(plugin, current)
  local other = current == "left" and "right" or "left"
  M.set(plugin, other)
  panel.close()
  noctalia.runAsync({ "noctalia", "msg", "panel-open", id(plugin, other) })
end

return M
