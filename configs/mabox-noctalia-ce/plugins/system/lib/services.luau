--!nonstrict
-- Services tab: running state of system and user units; actions only in a terminal after a y/N prompt.

local MAX_ROWS = 40

-- Stopping or restarting these can end the session or the network stack; they get status only.
local PROTECTED = {
  "^dbus", "^systemd%-", "^user@", "^user%-runtime%-dir@", "^getty", "^serial%-getty", "^console%-getty",
  "^display%-manager", "^lightdm", "^sddm", "^gdm", "^polkit", "^seatd", "^elogind", "^app%-", "^NetworkManager", "^wpa_supplicant", "^iwd", "^accounts%-daemon", "^rtkit",
}

local FILTERS = { { "failed", "Failed" }, { "running", "Running" }, { "all", "All" } }

-- Prints the command, runs it only after y; the unit name is an argument, never part of the script text.
local RUN_UNIT = [[
printf '%s\n\n' "$*"
printf 'Run this command? [y/N] '
read -r a
case $a in y|Y) "$@" ;; *) echo cancelled ;; esac
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
  return string.match(name, "^[%w:_@%.\\][%w:_@%.%-\\]*%.service$") ~= nil
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
  local query = ""
  local data = {}
  local openUnit = nil
  local statusText = {}
  local session = 0

  local function loadScope(which)
    local argv = { "systemctl" }
    if which == "user" then
      table.insert(argv, "--user")
    end
    for _, a in ipairs({ "list-units", "--type=service", "--all", "--no-legend", "--plain", "--no-pager" }) do
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
    query = ""
  end

  local function fetchStatus(name)
    local key = scope .. ":" .. name
    statusText[key] = "Reading..."
    render()
    local mine = session
    local cmd = "systemctl " .. (scope == "user" and "--user " or "") .. "status --no-pager -n 12 -- '" .. name .. "' 2>&1 | mb-sysreport scrub \"$@\""
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
  end

  local function action(verb, name)
    local argv = { "sh", "-c", RUN_UNIT, "sh" }
    if scope == "system" then
      table.insert(argv, "sudo")
    end
    table.insert(argv, "systemctl")
    if scope == "user" then
      table.insert(argv, "--user")
    end
    table.insert(argv, verb)
    table.insert(argv, "--")
    table.insert(argv, name)
    terminal(table.unpack(argv))
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
    return part("System", "system") .. "   |   " .. part("User", "user")
  end

  local function matches(u)
    if filter == "failed" and u.active ~= "failed" then
      return false
    end
    if filter == "running" and u.sub ~= "running" then
      return false
    end
    return query == "" or string.find(string.lower(u.name), string.lower(query), 1, true) ~= nil
  end

  local function dot(u)
    local color = u.active == "failed" and "error" or (u.sub == "running" and "primary" or "on_surface_variant")
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
      local buttons = {
        ui.button({ text = "Reload status", glyph = "refresh", variant = "outline", controlSize = "sm", onClick = function() fetchStatus(u.name) end }),
      }
      if protected(u.name) then
        table.insert(items, ui.label({ text = "Protected: stopping or restarting it can end your session. Status only.", fontSize = 11, color = "on_surface_variant" }))
      else
        local function btn(text, glyph, verb)
          table.insert(buttons, ui.button({ text = text, glyph = glyph, variant = "outline", controlSize = "sm",
            tooltip = "Opens a terminal that shows the command and asks first", onClick = function() action(verb, u.name) end }))
        end
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
      table.insert(items, ui.row({ gap = 6 }, buttons))
    end
    return ui.column({ key = "u" .. scope .. u.name, fill = "surface_variant", radius = 10, padding = 10, gap = 6, border = u.active == "failed" and "error" or "primary", borderWidth = 1 }, items)
  end

  local function body()
    local chips = {}
    for _, s in ipairs({ { "system", "System" }, { "user", "User" } }) do
      table.insert(chips, ui.button({ key = "sc-" .. s[1], text = s[2], variant = scope == s[1] and "primary" or "outline", controlSize = "sm",
        onClick = function() scope = s[1] openUnit = nil render() end }))
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
        table.insert(rows, ui.label({ text = filter == "failed" and "No failed services." or "No matching services.", color = "on_surface_variant" }))
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
