--!nonstrict
-- Configs: list of config files from paths.luau plus the user's config-paths.local.
local DEFAULT = require("./paths.luau")

local pinSide = require("./side.luau")
local kbd = require("./kbd.luau")

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
local plugins = {}
local failed = {}
local expanded = {}
local newName = ""
local newPath = ""
local render
local refresh
local row = 0

local function stop(id, col, action)
  kbd.stop(id, row, col, action)
end

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
  noctalia.runAsync({ "noctalia", "msg", "plugins", "list" }, function(result)
    plugins = {}
    failed = {}
    for l in string.gmatch(noctalia.readFile((noctalia.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/mb-plugin-errors") or "", "[^\n]+") do
      failed[l] = true
    end
    for l in string.gmatch(result.stdout or "", "[^\n]+") do
      local id = string.match(l, "^(%S+) %[%S+%] %S+ enabled")
      if id then
        table.insert(plugins, id)
      end
    end
    for id in pairs(failed) do
      if not table.find(plugins, id) then
        table.insert(plugins, id)
      end
    end
    render()
  end)
end

local RELOAD = [[
ERR="${XDG_RUNTIME_DIR:-/tmp}/mb-plugin-errors"
pin="$1"; shift
touch "$ERR"
for id in "$@"; do
  noctalia msg plugins disable "$id" >/dev/null 2>&1
  out=$(noctalia msg plugins enable "$id" 2>&1)
  grep -vxF "$id" "$ERR" >"$ERR.$$"; mv "$ERR.$$" "$ERR"
  case "$out" in error*) echo "$id" >>"$ERR" ;; esac
done
if [ -n "$pin" ]; then sleep 0.5; noctalia msg panel-open "$pin"; fi
]]

-- Reloading configs itself ends this script's panel: it goes last and a pinned window is reopened.
local function reloadPlugins(ids)
  local list, self = {}, false
  for _, id in ipairs(ids) do
    if id == "mabox/configs" then
      self = true
    else
      table.insert(list, id)
    end
  end
  if self then
    table.insert(list, "mabox/configs")
  end
  local pin = pinned and ("mabox/configs:pinned-" .. pinSide.get("configs")) or ""
  noctalia.runAsync({ "setsid", "-f", "sh", "-c", RELOAD, "sh", pin, table.unpack(list) }, function()
    refresh()
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
  row += 1
  local uid = e.group .. "|" .. e.name .. "|" .. e.path
  local function showIt() show(e.path) end
  local function openIt() open(e.path) end
  local function removeIt() removeCustom(e.name, e.path) end
  stop("f" .. uid, 1, showIt)
  stop("o" .. uid, 2, openIt)
  local items = {
    ui.label({ text = e.name, color = e.state == "ok" and "on_surface" or "on_surface_variant" }),
    ui.spacer({ flexGrow = 1 }),
    ui.button({ key = "f" .. uid, glyph = "folder", selected = kbd.sel("f" .. uid), variant = "ghost", controlSize = "sm", tooltip = "Show in file manager", onClick = showIt }),
    ui.button({
      key = "o" .. uid,
      selected = kbd.sel("o" .. uid),
      glyph = "pencil",
      variant = "ghost",
      controlSize = "sm",
      tooltip = e.state == "ok" and e.path or e.path .. " (missing)",
      onClick = openIt,
    }),
  }
  if e.group == "Custom" then
    stop("x" .. uid, 3, removeIt)
    table.insert(items, ui.button({ key = "x" .. uid, selected = kbd.sel("x" .. uid), glyph = "trash", variant = "ghost", controlSize = "sm", tooltip = "Remove from the list", onClick = removeIt }))
  end
  return ui.row({ gap = 6, align = "center" }, items)
end

render = function()
  kbd.begin()
  row = 0
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

  local function toggle(name)
    expanded[name] = not expanded[name] or nil
    saveExpanded()
    render()
  end

  local function pinOrClose()
    panel.close()
    if not pinned then
      pinSide.toggle("configs")
    end
  end
  local function moveSide()
    pinSide.swap("configs", pinned)
  end
  local function runLabwc()
    noctalia.runAsync({ "labwc", "--reconfigure" })
  end
  local function runFitts()
    panel.close()
    noctalia.runAsync({ "mb-fitts" })
  end
  local function runNoctalia()
    noctalia.runAsync({ "noctalia", "msg", "config-reload" })
  end
  local function reloadAll()
    reloadPlugins(plugins)
  end

  row += 1
  stop("refresh", 1, refresh)
  if pinned then
    stop("swap", 2, moveSide)
  end
  stop("pin", 3, pinOrClose)
  local top = ui.row({ gap = 6, align = "center" }, {
    ui.label({ text = "Configs", flexGrow = 1 }),
    ui.button({ key = "refresh", selected = kbd.sel("refresh"), glyph = "refresh", variant = "ghost", controlSize = "sm", tooltip = "Refresh", onClick = refresh }),
    pinned and ui.button({ key = "swap", selected = kbd.sel("swap"), glyph = "arrows-left-right", variant = "ghost", controlSize = "sm", tooltip = "Move to the other side", onClick = moveSide }) or ui.spacer({ width = 0 }),
    ui.button({ key = "pin", selected = kbd.sel("pin"), glyph = pinned and "x" or "pin", variant = "ghost", controlSize = "sm", tooltip = pinned and "Close" or "Pin window", onClick = pinOrClose }),
  })

  row += 1
  stop("labwc", 1, runLabwc)
  stop("fitts", 2, runFitts)
  stop("noctalia", 3, runNoctalia)
  local reload = ui.row({ gap = 6 }, {
    ui.button({ key = "labwc", selected = kbd.sel("labwc"), text = "labwc", glyph = "refresh", variant = "ghost", controlSize = "sm", flexGrow = 1, tooltip = "Apply changes to rc.xml, menu.xml and themerc without logging out", onClick = runLabwc }),
    ui.button({ key = "fitts", selected = kbd.sel("fitts"), glyph = "mouse", variant = "ghost", controlSize = "sm", tooltip = "Show what the screen edges and corners do (fittsmon)", onClick = runFitts }),
    ui.button({ key = "noctalia", selected = kbd.sel("noctalia"), text = "Noctalia", glyph = "refresh", variant = "ghost", controlSize = "sm", flexGrow = 1, tooltip = "Apply changes to the bar, widget tooltips and click actions", onClick = runNoctalia }),
  })

  local sideOpen = expanded["Pinned windows"]
  row += 1
  stop("h-side", 1, function() toggle("Pinned windows") end)
  local sideRows = {
    ui.button({
      key = "h-side",
      selected = kbd.sel("h-side"),
      text = "Pinned windows",
      glyph = sideOpen and "chevron-down" or "chevron-right",
      variant = "ghost",
      controlSize = "sm",
      contentAlign = "start",
      onClick = function() toggle("Pinned windows") end,
    }),
  }
  if sideOpen then
    for _, pl in ipairs(PINNED_PLUGINS) do
      row += 1
      local current = pinSide.get(pl[1])
      local function sideButton(value, text, col)
        local function pick()
          pinSide.set(pl[1], value)
          render()
        end
        local id = "p-" .. pl[1] .. value
        stop(id, col, pick)
        return ui.button({
          key = id,
          selected = kbd.sel(id),
          text = text,
          variant = current == value and "primary" or "ghost",
          controlSize = "sm",
          tooltip = "An open window moves after you close and reopen it",
          onClick = pick,
        })
      end
      table.insert(sideRows, ui.row({ gap = 6, align = "center" }, {
        ui.label({ text = pl[2] }),
        ui.spacer({ flexGrow = 1 }),
        sideButton("left", "Left", 1),
        sideButton("right", "Right", 2),
      }))
    end
  end
  table.insert(cards, ui.column({ fill = "surface_variant", radius = 8, padding = 8, gap = 4 }, sideRows))

  local plugOpen = expanded["Plugins"]
  row += 1
  stop("h-plug", 1, function() toggle("Plugins") end)
  stop("reload-all", 2, reloadAll)
  local plugRows = {
    ui.row({ gap = 6, align = "center" }, {
      ui.button({
        key = "h-plug",
        selected = kbd.sel("h-plug"),
        text = "Plugins",
        flexGrow = 1,
        glyph = plugOpen and "chevron-down" or "chevron-right",
        variant = "ghost",
        controlSize = "sm",
        contentAlign = "start",
        tooltip = "Click a plugin to restart it after editing its plugin.toml or Lua files",
        onClick = function() toggle("Plugins") end,
      }),
      ui.button({ key = "reload-all", selected = kbd.sel("reload-all"), text = "Reload all", glyph = "refresh", variant = "ghost", controlSize = "sm", tooltip = "Restart every enabled plugin; failed ones turn red", onClick = reloadAll }),
    }),
  }
  if plugOpen then
    for _, id in ipairs(plugins) do
      row += 1
      local function reloadOne()
        reloadPlugins({ id })
      end
      stop("pl-" .. id, 1, reloadOne)
      table.insert(plugRows, ui.button({ key = "pl-" .. id, selected = kbd.sel("pl-" .. id), text = id, glyph = failed[id] and "alert-circle" or "refresh", variant = failed[id] and "destructive" or "ghost", controlSize = "sm", contentAlign = "start", tooltip = failed[id] and "Failed to load; click to retry" or nil, onClick = reloadOne }))
    end
  end
  table.insert(cards, ui.column({ fill = "surface_variant", radius = 8, padding = 8, gap = 4 }, plugRows))

  for _, g in ipairs(order) do
    local closed = not expanded[g]
    row += 1
    stop("g-" .. g, 1, function() toggle(g) end)
    local rows = {
      ui.button({
        key = "g-" .. g,
        selected = kbd.sel("g-" .. g),
        text = g,
        glyph = closed and "chevron-right" or "chevron-down",
        variant = "ghost",
        controlSize = "sm",
        contentAlign = "start",
        onClick = function() toggle(g) end,
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
      row += 1
      local function files()
        show(noctalia.getenv("HOME") .. "/.config")
      end
      local function paste()
        pastePath(false)
      end
      stop("c-files", 1, files)
      stop("c-paste", 2, paste)
      stop("c-add", 3, addCustom)
      table.insert(rows, ui.column({ fill = "surface", radius = 6, padding = 8, gap = 4 }, {
        ui.label({ text = "Add a file", fontSize = 12 }),
        ui.label({ text = "Name (optional)", fontSize = 11, color = "on_surface_variant" }),
        ui.input({ key = "newName", value = newName, onChange = function(t) newName = t end }),
        ui.label({ text = "Path (~ allowed)", fontSize = 11, color = "on_surface_variant" }),
        ui.input({ key = "newPath", value = newPath, onChange = function(t) newPath = t end }),
        ui.row({ gap = 4 }, {
          ui.button({ key = "c-files", selected = kbd.sel("c-files"), text = "Files", glyph = "folder-open", variant = "ghost", controlSize = "sm", flexGrow = 1, tooltip = "Open the file manager, select a file, press Ctrl+C", onClick = files }),
          ui.button({ key = "c-paste", selected = kbd.sel("c-paste"), text = "Paste", glyph = "clipboard", variant = "ghost", controlSize = "sm", flexGrow = 1, tooltip = "Use the copied file", onClick = paste }),
          ui.button({ key = "c-add", selected = kbd.sel("c-add"), text = "Add", glyph = "plus", variant = "primary", controlSize = "sm", flexGrow = 1, onClick = addCustom }),
        }),
      }))
    end
    -- The pinned window has no fields: the copied file is added at once.
    if g == "Custom" and not closed and pinned then
      row += 1
      local function files()
        show(noctalia.getenv("HOME") .. "/.config")
      end
      local function addCopied()
        pastePath(true)
      end
      stop("c-files", 1, files)
      stop("c-copied", 2, addCopied)
      table.insert(rows, ui.row({ gap = 4 }, {
        ui.button({ key = "c-files", selected = kbd.sel("c-files"), text = "Files", glyph = "folder-open", variant = "ghost", controlSize = "sm", flexGrow = 1, tooltip = "Open the file manager, select a file, press Ctrl+C", onClick = files }),
        ui.button({ key = "c-copied", selected = kbd.sel("c-copied"), text = "Add copied", glyph = "plus", variant = "primary", controlSize = "sm", flexGrow = 1, tooltip = "Add the file you copied in the file manager", onClick = addCopied }),
      }))
    end
    table.insert(cards, ui.column({ fill = "surface_variant", radius = 8, padding = 8, gap = 4 }, rows))
  end

  local list = ui.scroll({ gap = 8, flexGrow = 1, key = "list", revealKey = kbd.reveal() }, cards)
  if pinned then
    panel.render(ui.column({ gap = 8, padding = 10, flexGrow = 1 }, { top, reload, list }))
  else
    panel.render(ui.column({ gap = 8, padding = 12, height = 520 }, { top, reload, list }))
  end
end

-- alt+s drops the cursor so the Add form's fields can be clicked and typed in.
local function handleKey(chord)
  if chord == "alt+s" then
    kbd.clear()
    render()
  elseif kbd.key(chord) == "moved" then
    render()
  end
end

local function start()
  loadExpanded()
  render()
  refresh()
end

return start, handleKey
end
