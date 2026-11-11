--!nonstrict
-- Pinned windows: the side (left or right) per plugin, one "plugin=side" line each in
-- ~/.config/mabox-noctalia-ce/pinned-side. Keep this file identical in every plugin's lib/.
local M = {}

-- Width of a pinned window in px, also the space a docked one reserves.
M.ZONE = 330

local function path()
  return noctalia.getenv("HOME") .. "/.config/mabox-noctalia-ce/pinned-side"
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
local PLUGINS = { "colors", "notes", "status", "configs", "capture", "places" }
-- Pinned windows are layers; each plugin's "pin" service shows and hides them.

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

local function pinCmd(plugin, verb)
  return "noctalia msg plugin mabox/" .. plugin .. ":pin all " .. verb .. " >/dev/null 2>&1"
end

-- Shell command that shows the pinned window again (after the script ran something with focus elsewhere).
function M.reopenCmd(plugin)
  return pinCmd(plugin, "show")
end

-- verb is "toggle" or "show".
local function command(plugin, side, verb)
  local sides = read()
  local cmd = {}
  for _, other in ipairs(PLUGINS) do
    if other ~= plugin and (sides[other] == "right" and "right" or "left") == side then
      table.insert(cmd, pinCmd(other, "hide"))
    end
  end
  table.insert(cmd, pinCmd(plugin, verb))
  return table.concat(cmd, "; ")
end

function M.toggle(plugin)
  noctalia.runAsync({ "sh", "-c", command(plugin, M.get(plugin), "toggle") })
end

-- From a pinned window: move this plugin's window to the other side.
function M.swap(plugin, current)
  local other = current == "left" and "right" or "left"
  M.set(plugin, other)
  noctalia.runAsync({ "sh", "-c", command(plugin, other, "show") })
end

-- Closes the window this script runs in: the pinned layer through the pin service, else the panel.
function M.close(plugin, pinned)
  if pinned then
    noctalia.runAsync({ "noctalia", "msg", "plugin", "mabox/" .. plugin .. ":pin", "all", "hide" })
  else
    panel.close()
  end
end

function M.render(pinned, tree)
  if pinned then
    -- A layer has no background of its own.
    layer.render(ui.column({ fill = "surface", flexGrow = 1 }, { tree }))
  else
    panel.render(tree)
  end
end

-- Dock button of a pinned window; rerender redraws it after the change.
function M.dockButton(plugin, pinned, rerender)
  local on = M.docked(plugin)
  return ui.button({
    glyph = "layout-sidebar",
    variant = on and "primary" or "ghost",
    controlSize = "sm",
    tooltip = on and "Float" or "Dock (reserve the space)",
    onClick = function()
      M.setDocked(plugin, not on)
      noctalia.layer.configure("pinned-" .. pinned, { exclusiveZone = not on and M.ZONE or 0 })
      rerender()
    end,
  })
end

return M
