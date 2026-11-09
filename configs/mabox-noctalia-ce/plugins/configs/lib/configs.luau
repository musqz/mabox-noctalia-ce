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

-- Plugins with a pinned window.
local widgets = {}
local PINNED_PLUGINS = { { "colors", "Colors" }, { "notes", "Notes" }, { "status", "Status" }, { "configs", "Configs" } }

-- Ids of the plugins that declare a [[desktop_widget]] in their plugin.toml.
local WIDGET_IDS = [[
for d in $(noctalia msg plugins source list | awk '$2=="path"{print $3}'); do
  grep -l '^\[\[desktop_widget\]\]' "$d"/*/plugin.toml 2>/dev/null
done | xargs -r sed -s -n '1s/^id = "\(.*\)"/\1/p'
]]

-- Prints name<TAB>tooltip<TAB>left<TAB>middle<TAB>right<TAB>glyph for every custom_button widget that is in the bar.
local BUTTONS = [[
used=$(for k in start center end; do noctalia msg config-get "bar.default.$k"; done | grep -o "'[^']*'" | tr -d "'" | tr '\n' '|')
noctalia msg config-get widget | awk -v used="|$used" '
function unq(v,   q) { q = substr(v, 1, 1); v = substr(v, 2, length(v) - 2); if (q == "\"") { gsub(/\\\\/, "\001", v); gsub(/\\"/, "\"", v); gsub(/\001/, "\\", v) } return v }
/^\[[^.]*\]$/ { cur = substr($0, 2, length($0) - 2); sec = "top"; names[++n] = cur; next }
/^ *\[.*\.actions\]$/ { sec = "act"; next }
/^ *\[/ { sec = "other"; next }
{
  l = $0; sub(/^ +/, "", l); i = index(l, " = ")
  if (!i) next
  k = substr(l, 1, i - 1); v = unq(substr(l, i + 3))
  if (sec == "top") { if (k == "type" && v == "custom_button") btn[cur] = 1; if (k == "tooltip") tip[cur] = v; if (k == "glyph") gly[cur] = v }
  else if (sec == "act") act[cur, k] = v
}
END { for (j = 1; j <= n; j++) { c = names[j]; if (btn[c] && index(used, "|" c "|")) printf "%s\t%s\t%s\t%s\t%s\t%s\n", c, tip[c], act[c, "left"], act[c, "middle"], act[c, "right"], gly[c] } }
'
]]

-- Same columns as BUTTONS, read from the user's config.toml, else the packaged one.
local DEFAULTS = [[
f=${XDG_CONFIG_HOME:-$HOME/.config}/noctalia/config.toml
[ -r "$f" ] || f=/usr/share/mabox-noctalia-ce/noctalia/config.toml
[ -r "$f" ] && awk '
function unq(v,   q) { q = substr(v, 1, 1); v = substr(v, 2, length(v) - 2); if (q == "\"") { gsub(/\\\\/, "\001", v); gsub(/\\"/, "\"", v); gsub(/\001/, "\\", v) } return v }
/^\[widget\.[^.]*\]$/ { cur = substr($0, 9, length($0) - 9); sec = "top"; names[++n] = cur; next }
/^\[widget\.[^.]*\.actions\]$/ { sec = "act"; cur = substr($0, 9, length($0) - 17); next }
/^\[/ { sec = "other"; next }
{
  i = index($0, " = ")
  if (!i) next
  k = substr($0, 1, i - 1); v = unq(substr($0, i + 3))
  if (sec == "top") { if (k == "type" && v == "custom_button") btn[cur] = 1; if (k == "tooltip") tip[cur] = v; if (k == "glyph") gly[cur] = v }
  else if (sec == "act") act[cur, k] = v
}
END { for (j = 1; j <= n; j++) { c = names[j]; if (btn[c]) printf "%s\t%s\t%s\t%s\t%s\t%s\n", c, tip[c], act[c, "left"], act[c, "middle"], act[c, "right"], gly[c] } }
' "$f"
]]

-- $1 = widget, then key/value pairs (values already TOML-quoted); reload so the bar picks them up.
local SAVE = [[
n="$1"; shift
while [ $# -ge 2 ]; do
  noctalia msg config-set "widget.$n.$1" "$2" >/dev/null || exit 1
  shift 2
done
noctalia msg config-reload >/dev/null
]]

-- $1 = widget, then key/value pairs; also appends the widget to the end of the bar and reloads.
local ADD = [=[
n="$1"; shift
t=$(noctalia msg config-get "widget.$n.type" 2>/dev/null)
case "$t" in ""|*custom_button*) ;; *) exit 3 ;; esac
while [ $# -ge 2 ]; do
  noctalia msg config-set "widget.$n.$1" "$2" >/dev/null || exit 1
  shift 2
done
all=$(for k in start center end; do noctalia msg config-get "bar.default.$k"; done)
case "$all" in
  *"'$n'"*) ;;
  *) list=$(noctalia msg config-get bar.default.end | tr -d '\n')
     new=$(printf '%s' "$list" | sed -E "s/^\[[[:space:]]*\]$/['$n']/;t;s/,?[[:space:]]*\][[:space:]]*$/, '$n']/")
     noctalia msg config-set bar.default.end "$new" >/dev/null || exit 1 ;;
esac
noctalia msg config-reload >/dev/null
]=]

-- $1 = widget; takes it out of the bar lists and reloads. The [widget.x] block stays.
local REMOVE = [=[
n="$1"
e=$(printf '%s' "$n" | sed 's/[][\.*^$\/+?(){}|]/\\&/g')
found=0
for k in start center end; do
  list=$(noctalia msg config-get "bar.default.$k" 2>/dev/null | tr -d '\n')
  case "$list" in
    *"'$n'"*)
      found=1
      new=$(printf '%s' "$list" | sed -E "s/'$e'[[:space:]]*,[[:space:]]*//;t;s/,[[:space:]]*'$e'[[:space:]]*//;t;s/'$e'//")
      noctalia msg config-set "bar.default.$k" "$new" >/dev/null || exit 1 ;;
  esac
done
[ "$found" = 1 ] || exit 4
noctalia msg config-reload >/dev/null
]=]

local FIELDS = {
  { "glyph", "Icon (Tabler name, e.g. camera)", "glyph" },
  { "tooltip", "Tooltip", "tooltip" },
  { "left", "Left click", "actions.left" },
  { "middle", "Middle click", "actions.middle" },
  { "right", "Right click", "actions.right" },
}

-- Prints plugin-id:panel-id for every [[panel]] of every plugin, except the pinned windows.
local PANELS = [[
noctalia msg plugins source list | awk '$2=="path"{print $3}' | while IFS= read -r d; do
  for f in "$d"/*/plugin.toml; do
    [ -f "$f" ] && awk '
      /^id = / { v = $3; gsub(/"/, "", v); if (!pid) pid = v; else if (p) { if (v !~ /^pin/) print pid ":" v; p = 0 } }
      /^\[\[panel\]\]/ { p = 1 }
    ' "$f"
  done
done | awk '!seen[$0]++'
]]
local entries = {}
local buttons = {}
local defaults = {}
local prev = {}
local version = {}

-- The Add form starts empty; these show as grey examples.
local EXAMPLE = {
  name = "status",
  glyph = "activity",
  tooltip = "system status",
  left = "exec noctalia msg panel-toggle mabox/status:main",
  middle = "none",
  right = "exec noctalia msg panel-toggle mabox/status:pinned-left",
}
local newBtn = { name = "", glyph = "", tooltip = "", left = "", middle = "", right = "" }
local newBtnVersion = 0
local panels = {}
local staticLoaded = false
local drafts = {}
local confirmRemove = {}
local plugins = {}
local failed = {}
local stopped = {}
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
    stopped = {}
    for l in string.gmatch(noctalia.readFile((noctalia.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/mb-plugin-errors") or "", "[^\n]+") do
      failed[l] = true
    end
    for l in string.gmatch(result.stdout or "", "[^\n]+") do
      local id, state = string.match(l, "^(%S+) %[%S+%] %S+ (%a+)")
      if id and (state == "enabled" or string.sub(id, 1, 6) == "mabox/") then
        table.insert(plugins, id)
        stopped[id] = state == "disabled" or nil
      end
    end
    for id in pairs(failed) do
      stopped[id] = true
      if not table.find(plugins, id) then
        table.insert(plugins, id)
      end
    end
    render()
  end)
  noctalia.runAsync({ "sh", "-c", BUTTONS }, function(result)
    buttons = {}
    for l in string.gmatch(result.stdout or "", "[^\n]+") do
      local name, tip, left, middle, right, glyph = string.match(l, "^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
      if name then
        table.insert(buttons, { name = name, tooltip = tip, left = left, middle = middle, right = right, glyph = glyph })
      end
    end
    render()
  end)
  if not staticLoaded then
    staticLoaded = true
    noctalia.runAsync({ "sh", "-c", DEFAULTS }, function(result)
      defaults = {}
      for l in string.gmatch(result.stdout or "", "[^\n]+") do
        local name, tip, left, middle, right, glyph = string.match(l, "^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
        if name then
          defaults[name] = { tooltip = tip, left = left, middle = middle, right = right, glyph = glyph }
        end
      end
      render()
    end)
    noctalia.runAsync({ "sh", "-c", PANELS }, function(result)
      panels = {}
      for l in string.gmatch(result.stdout or "", "[^\n]+") do
        local id, panelId = string.match(l, "^([^:]+):(.+)$")
        if id then
          panels[id] = panels[id] or {}
          table.insert(panels[id], panelId)
        end
      end
      render()
    end)
  end
  noctalia.runAsync({ "sh", "-c", WIDGET_IDS }, function(result)
    widgets = {}
    for id in string.gmatch(result.stdout or "", "[^\n]+") do
      widgets[id] = true
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
if [ -n "$pin" ]; then sleep 0.5; noctalia msg plugin "$pin" all show; fi
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
  local pin = pinned and "mabox/configs:pin" or ""
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

local function tomlString(s)
  local flat = string.gsub(s, "[\t\r\n]", " ")
  local esc = string.gsub(flat, '[\\"]', "\\%0")
  return '"' .. esc .. '"'
end

-- Noctalia runs a click action only as "exec <command>"; "none" disables it.
local function action(v)
  v = string.gsub(v, "^%s+", "")
  if v == "" then
    return "none"
  end
  if v == "none" or string.match(v, "^exec%s") then
    return v
  end
  return "exec " .. v
end

-- config-set arguments for the fields of values that differ from the live button; an empty click action becomes "none", an empty icon is ignored.
local function changes(b, values)
  local out = {}
  for _, f in ipairs(FIELDS) do
    local key = f[1]
    local live = b[key]
    local v = values[key]
    if key ~= "tooltip" and key ~= "glyph" then
      -- untouched click actions are checked too, so an old one without exec gets fixed on Save
      v = action(v ~= nil and v or live)
    end
    local same = v == nil or v == live or (key == "glyph" and v == "") or (v == "none" and live == "")
    if not same then
      table.insert(out, f[3])
      table.insert(out, tomlString(v))
    end
  end
  return out
end

local function card(rows)
  return ui.column({ fill = "surface_variant", radius = 10, padding = 8, gap = 4, border = "primary", borderWidth = 1 }, rows)
end

local function draftOf(name)
  drafts[name] = drafts[name] or {}
  return drafts[name]
end

-- What the fields show now: the edit if there is one, else the live value.
local function shown(b)
  local d = draftOf(b.name)
  local out = {}
  for _, f in ipairs(FIELDS) do
    local key = f[1]
    out[key] = d[key] ~= nil and d[key] or b[key]
  end
  return out
end

-- A new key rebuilds the input, which otherwise keeps the text it already shows.
local function fill(b, values)
  version[b.name] = (version[b.name] or 0) + 1
  local d = draftOf(b.name)
  for _, f in ipairs(FIELDS) do
    d[f[1]] = values[f[1]] or ""
  end
end

-- Reset and Undo only fill the fields; Save is what writes.
local function resetFields(b)
  local now = shown(b)
  local same = true
  for _, f in ipairs(FIELDS) do
    if now[f[1]] ~= (defaults[b.name][f[1]] or "") then
      same = false
    end
  end
  if not same then
    prev[b.name] = now
  end
  fill(b, defaults[b.name])
  render()
end

-- Swaps the fields with the values before the last Reset or Undo, so a second click goes back.
local function undoFields(b)
  local before = prev[b.name]
  if not before then
    return
  end
  prev[b.name] = shown(b)
  fill(b, before)
  render()
end

local function saveButton(b)
  local args = changes(b, draftOf(b.name))
  if #args == 0 then
    noctalia.notify("Configs", b.name .. ": nothing to save")
    return
  end
  noctalia.runAsync({ "sh", "-c", SAVE, "sh", b.name, table.unpack(args) }, function(result)
    if result.exitCode == 0 then
      for k in pairs(draftOf(b.name)) do
        drafts[b.name][k] = nil
      end
      prev[b.name] = nil
      version[b.name] = (version[b.name] or 0) + 1
      noctalia.notify("Configs", b.name .. " saved")
    else
      noctalia.notify("Configs", "Saving " .. b.name .. " failed; your edits are kept")
    end
    refresh()
  end)
end

local function removeButton(b)
  noctalia.runAsync({ "sh", "-c", REMOVE, "sh", b.name }, function(result)
    confirmRemove[b.name] = nil
    if result.exitCode == 0 then
      expanded["bb-" .. b.name] = nil
      drafts[b.name] = nil
      prev[b.name] = nil
      version[b.name] = nil
      saveExpanded()
      noctalia.notify("Configs", b.name .. " removed from the bar")
    elseif result.exitCode == 4 then
      noctalia.notify("Configs", b.name .. " is not in the bar")
    else
      noctalia.notify("Configs", "Removing " .. b.name .. " failed")
    end
    refresh()
  end)
end

local function addButton()
  local name = newBtn.name
  if not string.match(name, "^[%w_-]+$") then
    noctalia.notify("Configs", "Name: letters, digits, - and _ only")
    return
  end
  if newBtn.glyph == "" then
    noctalia.notify("Configs", "Enter an icon name")
    return
  end
  local argv = { "sh", "-c", ADD, "sh", name,
    "type", tomlString("custom_button"), "color", tomlString("on_surface"), "capsule", "false" }
  for _, f in ipairs(FIELDS) do
    local v = newBtn[f[1]]
    if f[1] ~= "tooltip" and f[1] ~= "glyph" then
      v = action(v)
    end
    table.insert(argv, f[3])
    table.insert(argv, tomlString(v))
  end
  noctalia.runAsync(argv, function(result)
    if result.exitCode == 0 then
      noctalia.notify("Configs", name .. " added to the bar")
      for k in pairs(newBtn) do
        newBtn[k] = ""
      end
      newBtnVersion += 1
    elseif result.exitCode == 3 then
      noctalia.notify("Configs", name .. " is already a widget that is not a button; pick another name")
    else
      noctalia.notify("Configs", "Adding " .. name .. " failed")
    end
    refresh()
  end)
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

  local function collapseAll()
    expanded = {}
    saveExpanded()
    render()
  end

  local function pinOrClose()
    pinSide.close("configs", pinned)
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
    pinSide.close("configs", pinned)
    noctalia.runAsync({ "mb-fitts" })
  end
  local function runNoctalia()
    noctalia.runAsync({ "noctalia", "msg", "config-reload" })
  end
  local function reloadAll()
    local running = {}
    for _, id in ipairs(plugins) do
      if not stopped[id] or failed[id] then
        table.insert(running, id)
      end
    end
    if #running > 0 then
      reloadPlugins(running)
    end
  end

  row += 1
  stop("collapse", 0, collapseAll)
  stop("refresh", 1, refresh)
  if pinned then
    stop("swap", 2, moveSide)
  end
  stop("pin", 3, pinOrClose)
  local top = ui.row({ gap = 6, align = "center" }, {
    ui.label({ text = "Configs", flexGrow = 1 }),
    ui.button({ key = "collapse", selected = kbd.sel("collapse"), glyph = "chevrons-up", variant = "ghost", controlSize = "sm", tooltip = "Collapse all sections", onClick = collapseAll }),
    ui.button({ key = "refresh", selected = kbd.sel("refresh"), glyph = "refresh", variant = "ghost", controlSize = "sm", tooltip = "Refresh", onClick = function() staticLoaded = false; refresh() end }),
    pinned and pinSide.dockButton("configs", pinned, render) or ui.spacer({ width = 0 }),
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
      variant = "outline",
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
  table.insert(cards, card(sideRows))

  local function pluginRows(list, into)
    for _, id in ipairs(list) do
      row += 1
      local open = expanded["pc-" .. id]
      local function toggleOne()
        toggle("pc-" .. id)
      end
      stop("pl-" .. id, 1, toggleOne)
      table.insert(into, ui.button({ key = "pl-" .. id, selected = kbd.sel("pl-" .. id), text = stopped[id] and (id .. "  (stopped)") or id, glyph = failed[id] and "alert-circle" or (open and "point-filled" or "point"), variant = failed[id] and "destructive" or (open and "outline" or "ghost"), controlSize = "sm", contentAlign = "start", tooltip = failed[id] and "Failed to load; open it and reload" or nil, onClick = toggleOne }))
      if open then
        local function reloadOne()
          reloadPlugins({ id })
        end
        row += 1
        stop("rl-" .. id, 1, reloadOne)
        local lines = {
          ui.button({ key = "rl-" .. id, selected = kbd.sel("rl-" .. id), text = "Reload", glyph = "refresh", variant = "ghost", controlSize = "sm", tooltip = "Restart after editing its plugin.toml or Lua files", onClick = reloadOne }),
        }
        local cmds = {
          { "start", "noctalia msg plugins enable " .. id, "Start: load the plugin" },
          { "stop", "noctalia msg plugins disable " .. id, "Stop: unload the plugin" },
          { "reload", "noctalia msg plugins disable " .. id .. " && noctalia msg plugins enable " .. id, "Reload: stop, then start" },
        }
        if not stopped[id] then
          for _, p in ipairs(panels[id] or {}) do
            table.insert(cmds, { "toggle-" .. p, "noctalia msg panel-toggle " .. id .. ":" .. p, "Toggle the " .. p .. " panel" })
          end
        end
        for _, c in ipairs(cmds) do
          row += 1
          local function copy()
            noctalia.runAsync({ "wl-copy", "--", c[2] }, function(result)
              if result.exitCode == 0 then
                noctalia.notify("Command copied", c[2])
              else
                noctalia.copyToClipboard(c[2], "text/plain")
                noctalia.notify("Command added to clipboard history", "Install wl-clipboard to paste it directly")
              end
            end)
          end
          stop("cp-" .. id .. c[1], 1, copy)
          table.insert(lines, ui.row({ gap = 6, align = "center" }, {
            ui.column({ gap = 0, flexGrow = 1 }, {
              ui.label({ text = c[3], fontSize = 13, fontWeight = "bold", color = "on_surface_variant" }),
              ui.label({ text = c[2], fontSize = 13, color = "hover" }),
            }),
            ui.button({ key = "cp-" .. id .. c[1], selected = kbd.sel("cp-" .. id .. c[1]), glyph = "copy", variant = "ghost", controlSize = "sm", tooltip = "Copy the command", onClick = copy }),
          }))
        end
        table.insert(into, ui.column({ fill = "surface", radius = 6, padding = 8, gap = 4 }, lines))
      end
    end
  end

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
        variant = "outline",
        controlSize = "sm",
        contentAlign = "start",
        tooltip = "Click a plugin for its commands and a reload button",
        onClick = function() toggle("Plugins") end,
      }),
      ui.button({ key = "reload-all", selected = kbd.sel("reload-all"), text = "Reload all", glyph = "refresh", variant = "ghost", controlSize = "sm", tooltip = "Restart every enabled plugin; failed ones turn red", onClick = reloadAll }),
    }),
  }
  local plugList, widgetList = {}, {}
  for _, id in ipairs(plugins) do
    table.insert(widgets[id] and widgetList or plugList, id)
  end
  if plugOpen then
    pluginRows(plugList, plugRows)
  end
  table.insert(cards, card(plugRows))

  local widOpen = expanded["Widgets"]
  row += 1
  stop("h-wid", 1, function() toggle("Widgets") end)
  local widRows = {
    ui.button({
      key = "h-wid",
      selected = kbd.sel("h-wid"),
      text = "Widgets",
      glyph = widOpen and "chevron-down" or "chevron-right",
      variant = "outline",
      controlSize = "sm",
      contentAlign = "start",
      tooltip = "Desktop widgets: click one for its commands and a reload button",
      onClick = function() toggle("Widgets") end,
    }),
  }
  if widOpen then
    pluginRows(widgetList, widRows)
  end
  table.insert(cards, card(widRows))

  local btnOpen = expanded["Bar buttons"]
  row += 1
  stop("h-btn", 1, function() toggle("Bar buttons") end)
  local btnRows = {
    ui.button({
      key = "h-btn",
      selected = kbd.sel("h-btn"),
      text = "Bar buttons",
      glyph = btnOpen and "chevron-down" or "chevron-right",
      variant = "outline",
      controlSize = "sm",
      contentAlign = "start",
      tooltip = "Tooltip and click actions of the buttons in the bar",
      onClick = function() toggle("Bar buttons") end,
    }),
  }
  if btnOpen then
    for _, b in ipairs(buttons) do
      row += 1
      local id = "bb-" .. b.name
      local isOpen = expanded[id]
      local function toggleOne()
        confirmRemove[b.name] = nil
        toggle(id)
      end
      stop(id, 1, toggleOne)
      table.insert(btnRows, ui.button({ key = id, selected = kbd.sel(id), text = b.name, glyph = isOpen and "point-filled" or "point", variant = "ghost", controlSize = "sm", contentAlign = "start", onClick = toggleOne }))
      if isOpen then
        local d = draftOf(b.name)
        local lines = {}
        for _, f in ipairs(FIELDS) do
          local key = f[1]
          table.insert(lines, ui.label({ text = f[2], fontSize = 11, color = "on_surface_variant" }))
          table.insert(lines, ui.input({
            key = id .. key .. (version[b.name] or 0),
            value = d[key] ~= nil and d[key] or b[key],
            onChange = function(t) d[key] = t end,
          }))
        end
        local function save()
          saveButton(b)
        end
        local function reset()
          resetFields(b)
        end
        local function undo()
          undoFields(b)
        end
        row += 1
        local extra = {}
        if defaults[b.name] then
          stop("br-" .. b.name, 1, reset)
          table.insert(extra, ui.button({ key = "br-" .. b.name, selected = kbd.sel("br-" .. b.name), text = "Reset", glyph = "refresh", variant = "outline", controlSize = "sm", flexGrow = 1, tooltip = "Fill the fields with the values from config.toml; Save applies it", onClick = reset }))
        end
        if prev[b.name] then
          stop("bu-" .. b.name, 2, undo)
          table.insert(extra, ui.button({ key = "bu-" .. b.name, selected = kbd.sel("bu-" .. b.name), text = "Undo", glyph = "arrow-back-up", variant = "outline", controlSize = "sm", flexGrow = 1, tooltip = "Back to the fields before the last Reset or Undo; click again to switch back", onClick = undo }))
        end
        if #extra > 0 then
          table.insert(lines, ui.row({ gap = 4 }, extra))
        end
        row += 1
        stop("bs-" .. b.name, 1, save)
        table.insert(lines, ui.button({ key = "bs-" .. b.name, selected = kbd.sel("bs-" .. b.name), text = "Save", glyph = "check", variant = "primary", controlSize = "sm", tooltip = "Apply the fields to the bar now", onClick = save }))
        local armed = confirmRemove[b.name]
        local function remove()
          if confirmRemove[b.name] then
            removeButton(b)
          else
            confirmRemove[b.name] = true
            render()
          end
        end
        row += 1
        stop("bx-" .. b.name, 1, remove)
        table.insert(lines, ui.button({ key = "bx-" .. b.name, selected = kbd.sel("bx-" .. b.name), text = armed and "Click again to remove" or "Remove", glyph = "trash", variant = armed and "destructive" or "outline", controlSize = "sm", tooltip = "Take this button out of the bar", onClick = remove }))
        table.insert(btnRows, ui.column({ fill = "surface", radius = 6, padding = 8, gap = 4 }, lines))
      end
    end
    local addOpen = expanded["bb-add"]
    row += 1
    local function toggleAdd()
      toggle("bb-add")
    end
    stop("bb-add", 1, toggleAdd)
    table.insert(btnRows, ui.button({ key = "bb-add", selected = kbd.sel("bb-add"), text = "+ Add button", glyph = addOpen and "point-filled" or "point", variant = "ghost", controlSize = "sm", contentAlign = "start", tooltip = "Put a new button in the bar", onClick = toggleAdd }))
    if addOpen then
      local function addIt()
        addButton()
      end
      local lines = {}
      local function field(label, key)
        table.insert(lines, ui.label({ text = label, fontSize = 11, color = "on_surface_variant" }))
        table.insert(lines, ui.input({
          key = "ba-" .. key .. newBtnVersion,
          value = newBtn[key],
          placeholder = EXAMPLE[key],
          onChange = function(t) newBtn[key] = t end,
        }))
      end
      field("Name (letters, digits, - and _)", "name")
      field("Icon (Tabler name)", "glyph")
      field("Tooltip", "tooltip")
      field("Left click", "left")
      field("Middle click", "middle")
      field("Right click", "right")
      row += 1
      stop("ba-add", 1, addIt)
      table.insert(lines, ui.button({ key = "ba-add", selected = kbd.sel("ba-add"), text = "Add to the bar", glyph = "plus", variant = "primary", controlSize = "sm", tooltip = "Create the button and put it at the end of the bar; reorder it in the Noctalia settings", onClick = addIt }))
      table.insert(btnRows, ui.column({ fill = "surface", radius = 6, padding = 8, gap = 4 }, lines))
    end
  end
  table.insert(cards, card(btnRows))

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
        variant = "outline",
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
    table.insert(cards, card(rows))
  end

  local list = ui.scroll({ gap = 8, flexGrow = 1, key = "list", revealKey = kbd.reveal() }, cards)
  if pinned then
    pinSide.render(pinned, ui.column({ gap = 8, padding = 10, flexGrow = 1 }, { top, reload, list }))
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
