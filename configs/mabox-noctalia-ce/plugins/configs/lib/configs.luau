--!nonstrict
-- Configs: list of config files from paths.luau plus the user's config-paths.local.
local DEFAULT = require("./paths.luau")

local pinSide = require("./side.luau")

return function(pinned)
-- Prints group|name|path|state for every entry whose command (or path) exists.
local PROBE = [[
printf '%s\n' "$1" | while IFS='|' read -r g n c p; do
  [ -n "$p" ] || continue
  case $p in "~"*) p=$HOME${p#"~"} ;; esac
  if [ "$c" = "-" ]; then [ -e "$p" ] || continue
  else command -v "$c" >/dev/null || continue; fi
  if [ -e "$p" ]; then s=ok; else s=missing; fi
  printf '%s|%s|%s|%s\n' "$g" "$n" "$p" "$s"
done
]]

local OPEN = [[
if [ -d "$1" ]; then exec xdg-open "$1"; fi
if command -v geany >/dev/null; then exec geany "$1"; fi
exec xdg-open "$1"
]]

-- A directory opens itself, a file opens its folder.
local SHOW = [[
if [ -d "$1" ]; then exec xdg-open "$1"; fi
exec xdg-open "$(dirname "$1")"
]]

-- Path of the file copied in the file manager (Ctrl+C or Copy Path): file:// uri or plain text.
local PASTE = [[
c=$(wl-paste -n -t text/uri-list 2>/dev/null | head -n1 | tr -d '\r')
[ -n "$c" ] || c=$(wl-paste -n 2>/dev/null | head -n1)
c=${c#file://}
printf '%b' "$(printf '%s' "$c" | sed 's/%\(..\)/\\x\1/g')"
]]

-- Plugins with pinned-left and pinned-right panels.
local PINNED_PLUGINS = { { "colors", "Colors" }, { "notes", "Notes" }, { "status", "Status" }, { "configs", "Configs" } }

local entries = {}
local expanded = {}
local newName = ""
local newPath = ""
local render
local refresh

local function localFile()
  return noctalia.getenv("HOME") .. "/.config/mabox-noctalia-ce/config-paths.local"
end

local function statePath()
  local dir = noctalia.pluginDataDir()
  return dir and dir .. "/expanded" or nil
end

local function loadExpanded()
  local path = statePath()
  expanded = {}
  for l in string.gmatch((path and noctalia.readFile(path)) or "", "[^\n]+") do
    expanded[l] = true
  end
end

local function saveExpanded()
  local path = statePath()
  if not path then
    return
  end
  noctalia.mkdirAll(noctalia.pluginDataDir())
  local out = {}
  for g in pairs(expanded) do
    table.insert(out, g)
  end
  table.sort(out)
  noctalia.writeFile(path, table.concat(out, "\n") .. "\n")
end

local function localList()
  local raw = noctalia.readFile(localFile())
  local out = {}
  for l in string.gmatch(raw or "", "[^\n]+") do
    if not string.find(l, "^%s*#") then
      table.insert(out, l)
    end
  end
  return out
end

refresh = function()
  local all = {}
  for _, l in ipairs(DEFAULT) do
    table.insert(all, l)
  end
  for _, l in ipairs(localList()) do
    table.insert(all, l)
  end
  noctalia.runAsync({ "sh", "-c", PROBE, "sh", table.concat(all, "\n") }, function(result)
    entries = {}
    for l in string.gmatch(result.stdout or "", "[^\n]+") do
      local g, n, p, s = string.match(l, "^([^|]*)|([^|]*)|([^|]*)|(%a+)$")
      if g then
        table.insert(entries, { group = g, name = n, path = p, state = s })
      end
    end
    render()
  end)
end

local function addCustom()
  local path = string.gsub(string.gsub(newPath, "[|\n]", ""), "^%s+", "")
  path = string.gsub(path, "%s+$", "")
  local name = string.gsub(newName ~= "" and newName or (string.match(path, "([^/]+)/*$") or ""), "[|\n]", " ")
  if name == "" or path == "" then
    noctalia.notify("Configs", "Enter a name and a path")
    return
  end
  local raw = noctalia.readFile(localFile()) or ""
  if raw ~= "" and string.sub(raw, -1) ~= "\n" then
    raw = raw .. "\n"
  end
  noctalia.writeFile(localFile(), raw .. "Custom|" .. name .. "|-|" .. path .. "\n")
  newName, newPath = "", ""
  refresh()
end

local function pastePath(thenAdd)
  noctalia.runAsync({ "sh", "-c", PASTE }, function(result)
    local p = string.gsub(result.stdout or "", "%s+$", "")
    if p == "" then
      noctalia.notify("Configs", "Copy a file in the file manager first")
      return
    end
    newPath = p
    if thenAdd then
      addCustom()
    else
      render()
    end
  end)
end

local function removeCustom(name, path)
  local home = noctalia.getenv("HOME")
  local prefix = "Custom|" .. name .. "|"
  local out = {}
  local done = false
  for l in string.gmatch(noctalia.readFile(localFile()) or "", "[^\n]+") do
    local raw = string.match(l, "^[^|]*|[^|]*|[^|]*|(.*)$") or ""
    raw = string.gsub(raw, "^~", home)
    if not done and string.sub(l, 1, #prefix) == prefix and raw == path then
      done = true
    else
      table.insert(out, l)
    end
  end
  noctalia.writeFile(localFile(), #out > 0 and table.concat(out, "\n") .. "\n" or "")
  refresh()
end

local function open(path)
  noctalia.runAsync({ "setsid", "-f", "sh", "-c", OPEN, "sh", path })
end

local function show(path)
  noctalia.runAsync({ "setsid", "-f", "sh", "-c", SHOW, "sh", path })
end

local function entryRow(e)
  local items = {
    ui.label({ text = e.name, color = e.state == "ok" and "on_surface" or "on_surface_variant" }),
    ui.spacer({ flexGrow = 1 }),
    ui.button({ glyph = "folder", variant = "ghost", controlSize = "sm", tooltip = "Show in file manager", onClick = function() show(e.path) end }),
    ui.button({
      glyph = "pencil",
      variant = "ghost",
      controlSize = "sm",
      tooltip = e.state == "ok" and e.path or e.path .. " (missing)",
      onClick = function() open(e.path) end,
    }),
  }
  if e.group == "Custom" then
    table.insert(items, ui.button({ glyph = "trash", variant = "ghost", controlSize = "sm", tooltip = "Remove from the list", onClick = function() removeCustom(e.name, e.path) end }))
  end
  return ui.row({ gap = 6, align = "center" }, items)
end

render = function()
  local cards = {}
  local order = {}
  local groups = {}
  for _, e in ipairs(entries) do
    if not groups[e.group] then
      groups[e.group] = {}
      table.insert(order, e.group)
    end
    table.insert(groups[e.group], e)
  end
  for i, g in ipairs(order) do
    if g == "Custom" then
      table.remove(order, i)
      break
    end
  end
  table.insert(order, "Custom")
  for _, g in ipairs(order) do
    local closed = not expanded[g]
    local rows = {
      ui.button({
        text = g,
        glyph = closed and "chevron-right" or "chevron-down",
        variant = "ghost",
        controlSize = "sm",
        contentAlign = "start",
        onClick = function()
          expanded[g] = closed or nil
          saveExpanded()
          render()
        end,
      }),
    }
    if not closed then
      groups[g] = groups[g] or {}
      for _, e in ipairs(groups[g]) do
        if e.state == "ok" then
          table.insert(rows, entryRow(e))
        end
      end
      for _, e in ipairs(groups[g]) do
        if e.state ~= "ok" then
          table.insert(rows, entryRow(e))
        end
      end
    end
    if g == "Custom" and not closed and not pinned then
      table.insert(rows, ui.column({ fill = "surface", radius = 6, padding = 8, gap = 4 }, {
        ui.label({ text = "Add a file", fontSize = 12 }),
        ui.label({ text = "Name (optional)", fontSize = 11, color = "on_surface_variant" }),
        ui.input({ key = "newName", value = newName, onChange = function(t) newName = t end }),
        ui.label({ text = "Path (~ allowed)", fontSize = 11, color = "on_surface_variant" }),
        ui.input({ key = "newPath", value = newPath, onChange = function(t) newPath = t end }),
        ui.row({ gap = 4 }, {
          ui.button({ text = "Files", glyph = "folder-open", variant = "ghost", controlSize = "sm", flexGrow = 1, tooltip = "Open the file manager, select a file, press Ctrl+C", onClick = function() show(noctalia.getenv("HOME") .. "/.config") end }),
          ui.button({ text = "Paste", glyph = "clipboard", variant = "ghost", controlSize = "sm", flexGrow = 1, tooltip = "Use the copied file", onClick = function() pastePath(false) end }),
          ui.button({ text = "Add", glyph = "plus", variant = "primary", controlSize = "sm", flexGrow = 1, onClick = addCustom }),
        }),
      }))
    end
    -- The pinned window takes no keyboard input: no fields, the copied file is added at once.
    if g == "Custom" and not closed and pinned then
      table.insert(rows, ui.row({ gap = 4 }, {
        ui.button({ text = "Files", glyph = "folder-open", variant = "ghost", controlSize = "sm", flexGrow = 1, tooltip = "Open the file manager, select a file, press Ctrl+C", onClick = function() show(noctalia.getenv("HOME") .. "/.config") end }),
        ui.button({ text = "Add copied", glyph = "plus", variant = "primary", controlSize = "sm", flexGrow = 1, tooltip = "Add the file you copied in the file manager", onClick = function() pastePath(true) end }),
      }))
    end
    table.insert(cards, ui.column({ fill = "surface_variant", radius = 8, padding = 8, gap = 4 }, rows))
  end
  local top = ui.row({ gap = 6, align = "center" }, {
    ui.label({ text = "Configs", flexGrow = 1 }),
    ui.button({ glyph = "refresh", variant = "ghost", controlSize = "sm", tooltip = "Refresh", onClick = refresh }),
    pinned and ui.button({ glyph = "arrows-left-right", variant = "ghost", controlSize = "sm", tooltip = "Move to the other side", onClick = function() pinSide.swap("configs", pinned) end }) or ui.spacer({ width = 0 }),
    ui.button({ glyph = pinned and "x" or "pin", variant = "ghost", controlSize = "sm", tooltip = pinned and "Close" or "Pin window", onClick = function()
      panel.close()
      if not pinned then
        pinSide.toggle("configs")
      end
    end }),
  })
  local reload = ui.row({ gap = 6 }, {
    ui.button({ text = "Reload labwc", glyph = "refresh", variant = "ghost", controlSize = "sm", flexGrow = 1, tooltip = "labwc --reconfigure: rc.xml, menu.xml, themerc", onClick = function() noctalia.runAsync({ "labwc", "--reconfigure" }) end }),
    ui.button({ text = "Reload Noctalia", glyph = "refresh", variant = "ghost", controlSize = "sm", flexGrow = 1, tooltip = "Reload the Noctalia config: bar widgets, tooltips, actions", onClick = function() noctalia.runAsync({ "noctalia", "msg", "config-reload" }) end }),
  })
  local sideOpen = expanded["Pinned windows"]
  local sideRows = {
    ui.button({
      text = "Pinned windows",
      glyph = sideOpen and "chevron-down" or "chevron-right",
      variant = "ghost",
      controlSize = "sm",
      contentAlign = "start",
      onClick = function()
        expanded["Pinned windows"] = not sideOpen or nil
        saveExpanded()
        render()
      end,
    }),
  }
  if sideOpen then
    for _, pl in ipairs(PINNED_PLUGINS) do
      local current = pinSide.get(pl[1])
      local function sideButton(value, text)
        return ui.button({
          text = text,
          variant = current == value and "primary" or "ghost",
          controlSize = "sm",
          tooltip = "An open window moves after you close and reopen it",
          onClick = function()
            pinSide.set(pl[1], value)
            render()
          end,
        })
      end
      table.insert(sideRows, ui.row({ gap = 6, align = "center" }, {
        ui.label({ text = pl[2] }),
        ui.spacer({ flexGrow = 1 }),
        sideButton("left", "Left"),
        sideButton("right", "Right"),
      }))
    end
  end
  table.insert(cards, 1, ui.column({ fill = "surface_variant", radius = 8, padding = 8, gap = 4 }, sideRows))
  local list = ui.scroll({ gap = 8, flexGrow = 1, key = "list" }, cards)
  if pinned then
    panel.render(ui.column({ gap = 8, padding = 10, flexGrow = 1 }, { top, reload, list }))
  else
    panel.render(ui.column({ gap = 8, padding = 12, height = 520 }, { top, reload, list }))
  end
end

local function start()
  loadExpanded()
  render()
  refresh()
end

return start
end
