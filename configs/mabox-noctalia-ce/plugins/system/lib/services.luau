--!nonstrict
-- Services tab: running state of system and user units. Actions run in a terminal after a y/N prompt (system units: the unit name typed); Edit opens an editor or a drop-in.

local MAX_ROWS = 40

-- Stopping or restarting these can end the session or the network stack; they get status only.
local PROTECTED = {
  "^dbus", "^systemd%-", "^user@", "^user%-runtime%-dir@", "^getty", "^serial%-getty", "^console%-getty",
  "^display%-manager", "^lightdm", "^sddm", "^gdm", "^polkit", "^seatd", "^elogind", "^app%-", "^NetworkManager", "^wpa_supplicant", "^iwd", "^accounts%-daemon", "^rtkit",
}

local FILTERS = { { "failed", "Failed" }, { "running", "Running" }, { "all", "All" } }

-- Same rules as RUN_UNIT, for a fixed list of commands.
local REPAIR_TIMER = [[
u=$1
printf '%s\n' "systemctl --user daemon-reload" "systemctl --user reset-failed $u" "systemctl --user enable --now $u" "systemctl --user status --no-pager $u"
printf '\nRun these commands in order? [y/N] '
read -r a
case $a in
  y|Y)
    systemctl --user daemon-reload &&
    systemctl --user reset-failed "$u" &&
    systemctl --user enable --now "$u" &&
    systemctl --user status --no-pager "$u" ;;
  *) echo cancelled ;;
esac
printf '\nPress Enter to close '
read -r _
]]

-- Prints the command, runs it only after y; the unit name is an argument, never part of the script text.
local RUN_UNIT = [[
printf '%s\n\n' "$*"
printf 'Run this command? [y/N] '
read -r a
case $a in y|Y) "$@" ;; *) echo cancelled ;; esac
printf '\nPress Enter to close '
read -r _
]]

-- System units: shows the unit's state and dependents, then wants the unit name typed, not just y.
local RUN_SYSTEM = [[
unit=$1; shift
printf '%s\n\n' "$*"
echo 'SYSTEM service: this affects the whole machine and every user.'
printf 'Enabled at boot: '; systemctl is-enabled -- "$unit" 2>&1
echo 'Units that depend on it:'
systemctl list-dependencies --reverse --plain --no-pager -- "$unit" 2>&1 | sed 1d | head -n 15
printf '\nType the unit name (%s) to continue: ' "$unit"
read -r a
if [ "$a" = "$unit" ]; then "$@"; else echo cancelled; fi
printf '\nPress Enter to close '
read -r _
]]

-- A file you own is edited in place; a packaged file or a template instance gets a drop-in, pre-filled with a commented template (systemctl edit drops an empty one).
local EDIT_USER = [[
ed=${VISUAL:-$EDITOR}
[ -n "$ed" ] || ed=$(command -v nano || command -v micro || command -v vim || command -v vi)
d=$HOME/.config/systemd/user/$1.d
f=$d/override.conf
if [ -w "$2" ] && [ "${1#*@}" = "$1" ] && [ -n "$ed" ]; then
  $ed "$2" && systemctl --user daemon-reload && echo 'daemon-reload done'
elif [ -n "$ed" ] && [ ! -e "$f" ]; then
  mkdir -p "$d"
  case $1 in
    *.timer) printf '[Timer]\n# Packaged values add up: clear first, then set. Remove the # to use a line.\n#OnUnitActiveSec=\n#OnUnitActiveSec=3h\n' > "$f" ;;
    *) printf '[Service]\n# Remove the # to use a line.\n#Environment=NAME=value\n' > "$f" ;;
  esac
  $ed "$f"
  if grep -qv -e '^ *#' -e '^ *$' -e '^ *\[' "$f"; then
    systemctl --user daemon-reload && echo "drop-in saved. Restart the unit to apply: systemctl --user restart $1"
  else
    rm -f "$f"; rmdir "$d" 2>/dev/null; echo 'no change, drop-in not kept'
  fi
else
  systemctl --user edit -- "$1"
fi
printf '\nPress Enter to close '
read -r _
]]

-- A packaged system file stays untouched: the change goes into a drop-in; systemctl edit reloads by itself.
local EDIT_SYSTEM = [[
echo 'Edits a drop-in for the SYSTEM unit; the packaged file is not changed.'
ed=${VISUAL:-$EDITOR}
[ -n "$ed" ] || ed=$(command -v nano || command -v micro || command -v vim || command -v vi)
if [ -n "$ed" ]; then sudo env SYSTEMD_EDITOR="$ed" systemctl edit -- "$1"; else sudo systemctl edit -- "$1"; fi
printf '\nPress Enter to close '
read -r _
]]

local function protected(name)
  for _, p in ipairs(PROTECTED) do
    if string.find(name, p) then
      return true
    end
  end
  return false
end

local function validUnit(name)
  local kind = string.match(name, "^[%w:_@%.\\][%w:_@%.%-\\]*%.(%a+)$")
  return kind == "service" or kind == "timer"
end

local function parse(out)
  local units, failed, total = {}, 0, 0
  for l in string.gmatch(out, "[^\n]+") do
    local name, loaded, active, sub, desc = string.match(l, "^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s*(.*)$")
    if name and loaded ~= "not-found" and validUnit(name) then
      total += 1
      if active == "failed" then
        failed += 1
      end
      table.insert(units, { name = name, active = active, sub = sub, desc = desc })
    end
  end
  table.sort(units, function(a, b)
    if (a.active == "failed") ~= (b.active == "failed") then
      return a.active == "failed"
    end
    return a.name < b.name
  end)
  return { units = units, failed = failed, total = total }
end

return function(render, terminal, flags)
  local scope = "system"
  local filter = "running"
  local savedFilter = "running"
  local query = ""
  local data = {}
  local openUnit = nil
  local statusText = {}
  local pathText = {}
  local pathPending = {}
  local session = 0

  local function loadScope(which)
    local argv = { "systemctl" }
    if which ~= "system" then
      table.insert(argv, "--user")
    end
    for _, a in ipairs({ "list-units", "--type=" .. (which == "timers" and "timer" or "service"), "--all", "--no-legend", "--plain", "--no-pager" }) do
      table.insert(argv, a)
    end
    local mine = session
    noctalia.runAsync(argv, function(result)
      if mine ~= session then
        return
      end
      data[which] = result.exitCode == 0 and parse(result.stdout or "") or { units = {}, failed = 0, total = 0, error = noctalia.string.trim(result.stderr or "") }
      render()
    end)
  end

  local function reset()
    session += 1
    data = {}
    openUnit = nil
    statusText = {}
    pathText = {}
    pathPending = {}
    query = ""
  end

  local function fetchPath(name)
    local key = scope .. ":" .. name
    if pathText[key] or pathPending[key] then
      return
    end
    pathPending[key] = true
    local argv = { "systemctl" }
    if scope ~= "system" then
      table.insert(argv, "--user")
    end
    for _, a in ipairs({ "show", "-p", "FragmentPath", "--value", "--", name }) do
      table.insert(argv, a)
    end
    local mine = session
    noctalia.runAsync(argv, function(result)
      if mine ~= session then
        return
      end
      pathPending[key] = nil
      local out = noctalia.string.trim(result.stdout or "")
      pathText[key] = out ~= "" and out or nil
      render()
    end)
  end

  local function fetchStatus(name)
    local key = scope .. ":" .. name
    fetchPath(name)
    statusText[key] = "Reading..."
    render()
    local mine = session
    local cmd = "systemctl " .. (scope ~= "system" and "--user " or "") .. "status --no-pager -n 12 -- '" .. name .. "' 2>&1 | mb-sysreport scrub \"$@\""
    local argv = { "sh", "-c", cmd, "sh" }
    for _, f in ipairs(flags()) do
      table.insert(argv, f)
    end
    noctalia.runAsync(argv, function(result)
      if mine ~= session then
        return
      end
      local out = noctalia.string.trim(result.stdout or "")
      statusText[key] = out ~= "" and out or "(no output)"
      render()
    end)
  end

  local function load(force)
    if force then
      session += 1
      data = {}
      statusText = {}
      if openUnit then
        fetchStatus(openUnit)
      end
    end
    if not data.system then
      loadScope("system")
    end
    if not data.user then
      loadScope("user")
    end
    if not data.timers then
      loadScope("timers")
    end
  end

  local function action(verb, name, flag)
    local argv = { "sh", "-c", scope == "system" and RUN_SYSTEM or RUN_UNIT, "sh" }
    if scope == "system" then
      table.insert(argv, name)
      table.insert(argv, "sudo")
    end
    table.insert(argv, "systemctl")
    if scope ~= "system" then
      table.insert(argv, "--user")
    end
    table.insert(argv, verb)
    if flag then
      table.insert(argv, flag)
    end
    table.insert(argv, "--")
    table.insert(argv, name)
    terminal(table.unpack(argv))
  end

  local function editUnit(name, path)
    if scope == "system" then
      terminal("sh", "-c", EDIT_SYSTEM, "sh", name)
    else
      terminal("sh", "-c", EDIT_USER, "sh", name, path)
    end
  end

  local function openFolder(path)
    noctalia.runAsync({ "sh", "-c", 'exec setsid -f xdg-open "$(dirname "$1")"', "sh", path })
  end

  local function copyStatus(text, path)
    if text == "" or text == "Reading..." then
      noctalia.notify("System", "Status is not loaded yet")
      return
    end
    local all = path ~= "" and (text .. "\nFile: " .. path) or text
    noctalia.runAsync({ "sh", "-c", 'printf "%s\\n" "$1" | wl-copy', "sh", all }, function(result)
      if result.exitCode ~= 0 then
        noctalia.copyToClipboard(all, "text/plain")
      end
      noctalia.notify("System", "Status copied")
    end)
  end

  local function summary()
    local function part(label, which)
      local d = data[which]
      if not d then
        return label .. ": ..."
      end
      if d.error then
        return label .. ": unavailable"
      end
      return string.format("%s: %d units, %d failed", label, d.total, d.failed)
    end
    return part("System", "system") .. "   |   " .. part("User", "user") .. "   |   " .. part("Timers", "timers")
  end

  local function isRunning(u)
    if scope == "timers" then
      return u.active == "active"
    end
    return u.sub == "running"
  end

  local function matches(u)
    if filter == "failed" and u.active ~= "failed" then
      return false
    end
    if filter == "running" and not isRunning(u) then
      return false
    end
    return query == "" or string.find(string.lower(u.name), string.lower(query), 1, true) ~= nil
  end

  local function dot(u)
    local color = u.active == "failed" and "error" or (isRunning(u) and "primary" or "on_surface_variant")
    return ui.glyph({ name = "circle-filled", size = 10, color = color })
  end

  local function unitCard(u)
    local open = openUnit == u.name
    local toggle = function()
      openUnit = not open and u.name or nil
      if openUnit and not statusText[scope .. ":" .. u.name] then
        fetchStatus(u.name)
      else
        render()
      end
    end
    local items = {
      ui.row({ key = "uh" .. u.name, gap = 8, align = "center" }, {
        dot(u),
        ui.label({ text = u.name, fontWeight = "bold", fontSize = 13, flexGrow = 1 }),
        ui.label({ text = u.sub, fontSize = 11, color = u.active == "failed" and "error" or "on_surface_variant" }),
        ui.button({ glyph = open and "chevron-up" or "chevron-down", variant = "ghost", controlSize = "sm", tooltip = open and "Less" or "Status and actions", onClick = toggle }),
      }),
    }
    if open then
      if u.desc ~= "" then
        table.insert(items, ui.label({ text = u.desc, fontSize = 11, color = "on_surface_variant" }))
      end
      table.insert(items, ui.label({ text = statusText[scope .. ":" .. u.name] or "", fontSize = 11, fontFamily = "monospace" }))
      local path = pathText[scope .. ":" .. u.name] or ""
      local pathLabel = path ~= "" and path or (pathPending[scope .. ":" .. u.name] and "reading..." or "(none)")
      table.insert(items, ui.label({ text = "File: " .. pathLabel, fontSize = 11, fontFamily = "monospace", color = "on_surface_variant" }))
      if scope == "system" then
        table.insert(items, ui.label({ text = "System service: changes affect the whole machine. Stop, Restart, Start and Reset failed ask for the unit name in a terminal and use sudo. Edit changes a drop-in with sudo.", fontSize = 11, color = "error" }))
      end
      local buttons = {
        ui.button({ glyph = "refresh", variant = "outline", controlSize = "sm", tooltip = "Reload status", onClick = function() fetchStatus(u.name) end }),
      }
      table.insert(buttons, ui.button({ glyph = "copy", variant = "outline", controlSize = "sm", tooltip = "Copy the status text",
        onClick = function() copyStatus(statusText[scope .. ":" .. u.name] or "", path) end }))
      if path ~= "" then
        table.insert(buttons, ui.button({ text = "Open folder", glyph = "folder-open", variant = "outline", controlSize = "sm", onClick = function() openFolder(path) end }))
      end
      if protected(u.name) then
        table.insert(items, ui.label({ text = "Protected: stopping or restarting it can end your session. Status only.", fontSize = 11, color = "on_surface_variant" }))
      else
        if path ~= "" then
          table.insert(buttons, ui.button({ text = "Edit", glyph = "edit", variant = "outline", controlSize = "sm",
            tooltip = scope == "system" and "Edit a drop-in with sudo systemctl edit" or "Edit the file, or a drop-in when it is packaged or a template instance",
            onClick = function() editUnit(u.name, path) end }))
        end
        local function btn(text, glyph, verb, flag, target)
          table.insert(buttons, ui.button({ text = text, glyph = glyph, variant = "outline", controlSize = "sm",
            tooltip = "Opens a terminal that shows the command and asks first", onClick = function() action(verb, target or u.name, flag) end }))
        end
        if scope == "timers" then
          btn("Run now", "player-play", "start", nil, (string.gsub(u.name, "%.timer$", ".service")))
          btn(isRunning(u) and "Stop" or "Start", isRunning(u) and "player-stop" or "player-play", isRunning(u) and "stop" or "start")
          btn("Enable", "toggle-right", "enable", "--now")
          btn("Disable", "toggle-left", "disable", "--now")
          table.insert(buttons, ui.button({ text = "Repair", glyph = "tool", variant = "outline", controlSize = "sm",
            tooltip = "daemon-reload, reset-failed, enable --now, status: asks first",
            onClick = function() terminal("sh", "-c", REPAIR_TIMER, "sh", u.name) end }))
        else
          if u.active == "failed" then
            btn("Reset failed", "eraser", "reset-failed")
          end
          btn("Restart", "refresh-dot", "restart")
          if u.sub == "running" then
            btn("Stop", "player-stop", "stop")
          else
            btn("Start", "player-play", "start")
          end
        end
      end
      table.insert(items, ui.row({ gap = 6 }, buttons))
    end
    return ui.column({ key = "u" .. scope .. u.name, fill = "surface_variant", radius = 10, padding = 10, gap = 6, border = u.active == "failed" and "error" or (scope == "system" and "secondary" or "primary"), borderWidth = scope == "system" and 2 or 1 }, items)
  end

  local function body()
    local chips = {}
    for _, s in ipairs({ { "system", "System" }, { "user", "User" }, { "timers", "Timers" } }) do
      table.insert(chips, ui.button({ key = "sc-" .. s[1], text = s[2], variant = scope == s[1] and "primary" or "outline", controlSize = "sm",
        onClick = function()
          if s[1] == "timers" and scope ~= "timers" then
            savedFilter = filter
            filter = "all"
          elseif s[1] ~= "timers" and scope == "timers" then
            filter = savedFilter
          end
          scope = s[1]
          openUnit = nil
          render()
        end }))
    end
    table.insert(chips, ui.spacer({ width = 8 }))
    for _, f in ipairs(FILTERS) do
      table.insert(chips, ui.button({ key = "sf-" .. f[1], text = f[2], variant = filter == f[1] and "primary" or "outline", controlSize = "sm",
        onClick = function() filter = f[1] render() end }))
    end
    table.insert(chips, ui.input({ key = "svcq", value = query, placeholder = "Filter by name", controlSize = "sm", flexGrow = 1, frameVisible = true,
      onChange = function(v) query = v render() end }))

    local d = data[scope]
    local rows = {}
    if not d then
      table.insert(rows, ui.label({ text = "Reading units...", color = "on_surface_variant" }))
    elseif d.error then
      table.insert(rows, ui.label({ text = "systemctl failed: " .. d.error, color = "error" }))
    else
      local shown, hidden = 0, 0
      for _, u in ipairs(d.units) do
        if matches(u) then
          if shown < MAX_ROWS then
            shown += 1
            table.insert(rows, unitCard(u))
          else
            hidden += 1
          end
        end
      end
      if shown == 0 then
        table.insert(rows, ui.label({ text = filter == "failed" and "No failed units." or (scope == "timers" and "No matching timers." or "No matching services."), color = "on_surface_variant" }))
      end
      if hidden > 0 then
        table.insert(rows, ui.label({ text = hidden .. " more: type in the filter to narrow the list.", fontSize = 11, color = "on_surface_variant" }))
      end
    end
    return ui.column({ gap = 8, flexGrow = 1 }, {
      ui.label({ text = summary(), fontSize = 12, color = "on_surface_variant" }),
      ui.row({ gap = 6, align = "center" }, chips),
      ui.scroll({ flexGrow = 1, key = "svcscroll" }, { ui.column({ gap = 8 }, rows) }),
    })
  end

  local function clearStatus()
    statusText = {}
    if openUnit then
      fetchStatus(openUnit)
    end
  end

  return { load = load, reset = reset, body = body, clearStatus = clearStatus }
end
