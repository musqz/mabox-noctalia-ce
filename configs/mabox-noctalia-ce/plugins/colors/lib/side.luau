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
  noctalia.mkdirAll(noctalia.getenv("HOME") .. "/.config/mabox-noctalia-ce")
  noctalia.writeFile(path(), table.concat(out, "\n") .. "\n")
end

-- Pinned windows on the same side lie on top of each other: close the others, then run verb.
local PLUGINS = { "colors", "notes", "status", "configs", "capture" }
-- Plugins whose pinned window is a layer, driven through the plugin's "pin" service.
local LAYERED = { status = true }

local function dockPath()
  return noctalia.getenv("HOME") .. "/.config/mabox-noctalia-ce/pinned-dock"
end

function M.docked(plugin)
  for l in string.gmatch(noctalia.readFile(dockPath()) or "", "[^\n]+") do
    if l == plugin .. "=1" then
      return true
    end
  end
  return false
end

function M.setDocked(plugin, on)
  local out = {}
  for l in string.gmatch(noctalia.readFile(dockPath()) or "", "[^\n]+") do
    if string.match(l, "^[%w_-]+=1$") and l ~= plugin .. "=1" then
      table.insert(out, l)
    end
  end
  if on then
    table.insert(out, plugin .. "=1")
  end
  noctalia.mkdirAll(noctalia.getenv("HOME") .. "/.config/mabox-noctalia-ce")
  noctalia.writeFile(dockPath(), table.concat(out, "\n") .. (#out > 0 and "\n" or ""))
end

local function closeCmd(plugin, side)
  if LAYERED[plugin] then
    return "noctalia msg plugin mabox/" .. plugin .. ":pin all hide >/dev/null 2>&1"
  end
  return "noctalia msg panel-close " .. id(plugin, side) .. " >/dev/null 2>&1"
end

-- verb is "toggle" or "show".
local function command(plugin, side, verb)
  local sides = read()
  local cmd = {}
  for _, other in ipairs(PLUGINS) do
    if other ~= plugin and (sides[other] == "right" and "right" or "left") == side then
      table.insert(cmd, closeCmd(other, side))
    end
  end
  if LAYERED[plugin] then
    table.insert(cmd, "noctalia msg plugin mabox/" .. plugin .. ":pin all " .. verb)
  else
    table.insert(cmd, "noctalia msg " .. (verb == "toggle" and "panel-toggle " or "panel-open ") .. id(plugin, side))
  end
  return table.concat(cmd, "; ")
end

function M.toggle(plugin)
  noctalia.runAsync({ "sh", "-c", command(plugin, M.get(plugin), "toggle") })
end

-- From a pinned window: move this plugin's window to the other side.
function M.swap(plugin, current)
  local other = current == "left" and "right" or "left"
  M.set(plugin, other)
  if not LAYERED[plugin] then
    panel.close()
  end
  noctalia.runAsync({ "sh", "-c", command(plugin, other, "show") })
end

return M
