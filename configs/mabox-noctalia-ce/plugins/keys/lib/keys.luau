--!nonstrict
-- Keys: binds from `mb-keys list --tsv`, grouped in cards; Basics, All or a search over everything.
local GROUP_ORDER = { "Panels", "Apps", "Windows", "Workspaces", "Desktop", "Capture", "Media", "Jump", "Custom", "labwc defaults", "Helpers", "Other" }

return function(wide)
  local columns = wide and 3 or 2
  local keyWidth = wide and 190 or 150
  local binds = {}
  local mode = "basics"
  local tab = "basics"
  local query = ""
  local failed = false
  local status = ""
  local editing = nil
  local conflict = nil
  local armed = false
  local backups = {}
  local nonce = 0
  local render
  local reload

  local function statePath()
    local dir = noctalia.pluginDataDir()
    return dir and dir .. "/mode" or nil
  end

  local function loadMode()
    local path = statePath()
    mode = path and string.match(noctalia.readFile(path) or "", "^all") and "all" or "basics"
  end

  local function setMode(m)
    mode = m
    tab = m
    editing, conflict, armed, status = nil, nil, false, ""
    local path = statePath()
    if path then
      noctalia.mkdirAll(noctalia.pluginDataDir())
      noctalia.writeFile(path, m .. "\n")
    end
    render()
  end

  local function parse(text)
    binds = {}
    for line in string.gmatch(text, "[^\n]+") do
      local f = {}
      for part in string.gmatch(line .. "\t", "(.-)\t") do
        table.insert(f, part)
      end
      if #f >= 9 then
        local mods = {}
        for m in string.gmatch(f[2], "[^+]+") do
          table.insert(mods, m)
        end
        table.insert(binds, { spec = f[1], mods = mods, key = f[3], group = f[4], basic = f[5] == "1", desc = f[6], command = f[7], run = f[8] == "1", edit = f[9] == "1" })
      end
    end
  end

  local function matches(b, q)
    local hay = string.lower(table.concat(b.mods, " ") .. " " .. b.key .. " " .. b.spec .. " " .. b.desc .. " " .. b.command .. " " .. b.group)
    return string.find(hay, q, 1, true) ~= nil
  end

  local function visible()
    local q = string.lower(noctalia.string.trim(query))
    local groups, order = {}, {}
    for _, b in ipairs(binds) do
      local show
      if q ~= "" then
        show = matches(b, q)
      else
        show = tab == "edit" or tab == "all" or b.basic
      end
      if show then
        if not groups[b.group] then
          groups[b.group] = {}
          table.insert(order, b.group)
        end
        table.insert(groups[b.group], b)
      end
    end
    local rank = {}
    for i, g in ipairs(GROUP_ORDER) do
      rank[g] = i
    end
    table.sort(order, function(a, b)
      return (rank[a] or 99) < (rank[b] or 99)
    end)
    return groups, order
  end

  local function run(b)
    if not b.run then
      return
    end
    panel.close()
    noctalia.runAsync({ "setsid", "-f", "sh", "-c", b.command })
  end

  local function chips(b)
    local items = {}
    local parts = {}
    for _, m in ipairs(b.mods) do
      table.insert(parts, m)
    end
    table.insert(parts, b.key)
    for _, p in ipairs(parts) do
      table.insert(items, ui.row({ fill = "surface_variant", radius = 4, padding = 3 }, { ui.label({ text = p, fontSize = 11 }) }))
    end
    return ui.row({ gap = 3, align = "center", width = keyWidth }, items)
  end

  local function splitSpec(spec)
    local prefix, key = string.match(spec, "^(.*)%-(.+)$")
    local mods = {}
    for m in string.gmatch(prefix or "", "[^-]+") do
      mods[m] = true
    end
    return mods, key or spec
  end

  local function startEdit(b)
    local mods, key = splitSpec(b.spec)
    editing = { orig = b.spec, mods = mods, key = key, command = b.run and b.command or nil, desc = b.desc, run = b.run }
    conflict, armed, status = nil, false, ""
    nonce = nonce + 1
    render()
  end

  local function startAdd()
    editing = { orig = nil, mods = {}, key = "", command = "", desc = "", run = true }
    conflict, armed, status = nil, false, ""
    nonce = nonce + 1
    render()
  end

  local function composeSpec()
    local out = ""
    for _, m in ipairs({ "W", "A", "C", "S", "M", "H" }) do
      if editing.mods[m] then
        out = out .. m .. "-"
      end
    end
    return out .. noctalia.string.trim(editing.key)
  end

  -- Runs mb-keys; it backs rc.xml up, rewrites the lines and reloads labwc.
  local function helper(argv, done)
    noctalia.runAsync(argv, function(result)
      if result.exitCode ~= 0 then
        status = noctalia.string.trim(result.stderr or "") ~= "" and noctalia.string.trim(result.stderr) or "mb-keys failed"
        render()
        return
      end
      editing, conflict, armed = nil, nil, false
      status = done
      reload()
    end)
  end

  local function save()
    local spec = composeSpec()
    local cmd = noctalia.string.trim(editing.command or "")
    if noctalia.string.trim(editing.key) == "" then
      status = "Enter a key"
      render()
      return
    elseif editing.run and cmd == "" then
      status = "Enter a command"
      render()
      return
    end
    local desc = noctalia.string.trim(editing.desc or "")
    local argv
    if editing.orig then
      argv = { "mb-keys", "set", editing.orig, "--key=" .. spec }
      if editing.run then
        table.insert(argv, "--command=" .. cmd)
      end
      if desc ~= "" then
        table.insert(argv, "--desc=" .. desc)
      end
    else
      argv = { "mb-keys", "add" }
      if desc ~= "" then
        table.insert(argv, "--desc=" .. desc)
      end
      table.insert(argv, "--")
      table.insert(argv, spec)
      table.insert(argv, cmd)
    end
    helper(argv, "Saved, labwc reloaded")
  end

  local function trySave()
    local spec = composeSpec()
    if editing.orig == spec then
      save()
      return
    end
    local argv = { "mb-keys", "check", spec }
    if editing.orig then
      table.insert(argv, "--ignore")
      table.insert(argv, editing.orig)
    end
    noctalia.runAsync(argv, function(result)
      if not editing then
        return
      end
      if result.exitCode ~= 0 then
        status = "Could not check the key: " .. noctalia.string.trim(result.stderr or "")
        render()
        return
      end
      local found = {}
      for line in string.gmatch(result.stdout or "", "[^\n]+") do
        local kind, k, d = string.match(line, "^(%S+)\t([^\t]*)\t(.*)$")
        if kind then
          table.insert(found, (kind == "default" and "labwc default: " or "") .. d .. " (" .. k .. ")")
        end
      end
      if #found > 0 then
        conflict = found
        render()
      else
        save()
      end
    end)
  end

  local function remove()
    if not armed then
      armed = true
      render()
      return
    end
    helper({ "mb-keys", "delete", editing.orig }, "Deleted, labwc reloaded")
  end

  local function editor()
    local mods = {}
    for _, m in ipairs({ { "W", "Super" }, { "A", "Alt" }, { "C", "Ctrl" }, { "S", "Shift" } }) do
      table.insert(mods, ui.button({
        text = m[2],
        variant = editing.mods[m[1]] and "primary" or "ghost",
        controlSize = "sm",
        onClick = function()
          editing.mods[m[1]] = not editing.mods[m[1]] or nil
          conflict = nil
          render()
        end,
      }))
    end
    local items = {
      ui.row({ gap = 4, align = "center" }, mods),
      ui.input({ key = "ek" .. nonce, value = editing.key, placeholder = "key: k, Return, F5, XF86AudioMute", controlSize = "sm", focus = editing.orig == nil, onChange = function(t) if editing then editing.key = t conflict = nil end end }),
    }
    if editing.run then
      table.insert(items, ui.input({ key = "ec" .. nonce, value = editing.command, placeholder = "command", controlSize = "sm", onChange = function(t) if editing then editing.command = t end end }))
    end
    table.insert(items, ui.input({ key = "ed" .. nonce, value = editing.desc, placeholder = "description", controlSize = "sm", onChange = function(t) if editing then editing.desc = t end end }))
    if conflict then
      table.insert(items, ui.label({ text = "Already used by: " .. table.concat(conflict, "; "), fontSize = 11, color = "error" }))
    end
    local buttons = { ui.spacer({ flexGrow = 1 }) }
    if editing.orig then
      table.insert(buttons, ui.button({ text = armed and "Really delete?" or "Delete", glyph = "trash", variant = armed and "primary" or "ghost", controlSize = "sm", onClick = remove }))
    end
    table.insert(buttons, ui.button({ text = "Cancel", variant = "ghost", controlSize = "sm", onClick = function() editing, conflict, armed = nil, nil, false render() end }))
    table.insert(buttons, ui.button({ text = conflict and "Save anyway" or "Save", glyph = "check", variant = "primary", controlSize = "sm", onClick = conflict and save or trySave }))
    table.insert(items, ui.row({ gap = 6, align = "center" }, buttons))
    return ui.column({ fill = "surface", radius = 6, padding = 8, gap = 6 }, items)
  end

  local function bindRow(b)
    if editing and editing.orig == b.spec and tab == "edit" then
      return editor()
    end
    local middle = ui.label({ text = b.desc, flexGrow = 1, fontSize = 12 })
    if (tab == "all" or noctalia.string.trim(query) ~= "") and b.command ~= b.desc then
      middle = ui.column({ gap = 0, flexGrow = 1 }, {
        ui.label({ text = b.desc, fontSize = 12 }),
        ui.label({ text = b.command, fontSize = 10, color = "on_surface_variant" }),
      })
    end
    local action = ui.spacer({ width = 0 })
    if tab == "edit" then
      if b.edit then
        action = ui.button({ glyph = "pencil", variant = "ghost", controlSize = "sm", tooltip = "Edit", onClick = function() startEdit(b) end })
      end
    elseif b.run then
      action = ui.button({ glyph = "player-play", variant = "ghost", controlSize = "sm", tooltip = b.command, onClick = function() run(b) end })
    end
    return ui.row({ gap = 8, align = "center" }, { chips(b), middle, action })
  end

  local function backupLabel(name)
    local y, mo, d, h, mi, sec = string.match(name, "^rc%.xml%.(%d%d%d%d)(%d%d)(%d%d)%-(%d%d)(%d%d)(%d%d)")
    return y and (y .. "-" .. mo .. "-" .. d .. " " .. h .. ":" .. mi .. ":" .. sec) or name
  end

  local function backupBody()
    if #backups == 0 then
      return { ui.label({ text = "No backups yet; one is made before every change", color = "on_surface_variant" }) }
    end
    local rows = {}
    for _, name in ipairs(backups) do
      table.insert(rows, ui.row({ gap = 8, align = "center" }, {
        ui.label({ text = backupLabel(name), flexGrow = 1 }),
        ui.button({ text = "Restore", glyph = "restore", variant = "ghost", controlSize = "sm", tooltip = "The current rc.xml is backed up first", onClick = function() helper({ "mb-keys", "restore", name }, "Restored " .. backupLabel(name)) end }),
      }))
    end
    return { ui.column({ fill = "surface_variant", radius = 8, padding = 8, gap = 4 }, rows) }
  end

  local function body()
    if tab == "backups" then
      return backupBody()
    end
    local groups, order = visible()
    if #binds == 0 then
      return { ui.label({ text = failed and "Could not read rc.xml" or "No keybinds found", color = "on_surface_variant" }) }
    end
    if #order == 0 then
      return { ui.label({ text = "Nothing matches", color = "on_surface_variant" }) }
    end
    -- Shortest column gets the next card.
    local cols, heights = {}, {}
    for i = 1, columns do
      cols[i], heights[i] = {}, 0
    end
    for _, g in ipairs(order) do
      local rows = { ui.label({ text = g, fontSize = 13 }) }
      for _, b in ipairs(groups[g]) do
        table.insert(rows, bindRow(b))
      end
      local at = 1
      for i = 2, columns do
        if heights[i] < heights[at] then
          at = i
        end
      end
      table.insert(cols[at], ui.column({ fill = "surface_variant", radius = 8, padding = 8, gap = 4 }, rows))
      heights[at] = heights[at] + #groups[g] + 2
    end
    local out = {}
    for i = 1, columns do
      table.insert(out, ui.column({ gap = 8, flexGrow = 1, flexBasis = 0 }, cols[i]))
    end
    local result = {}
    if editing and editing.orig == nil and tab == "edit" then
      table.insert(result, editor())
    end
    table.insert(result, ui.row({ gap = 8, align = "start" }, out))
    return result
  end

  local function swap()
    panel.close()
    noctalia.runAsync({ "noctalia", "msg", "panel-open", "mabox/keys:" .. (wide and "keys" or "keys-wide") })
  end

  local function loadBackups()
    noctalia.runAsync({ "mb-keys", "backups" }, function(result)
      backups = {}
      for name in string.gmatch(result.stdout or "", "[^\n]+") do
        table.insert(backups, name)
      end
      render()
    end)
  end

  local function goTab(t)
    query = ""
    tab = t
    editing, conflict, armed, status = nil, nil, false, ""
    if t == "backups" then
      loadBackups()
    end
    render()
  end

  render = function()
    local searching = noctalia.string.trim(query) ~= ""
    local function tabButton(t, text)
      return ui.button({
        text = text,
        variant = (tab == t and (not searching or t == "edit")) and "primary" or "ghost",
        controlSize = "sm",
        onClick = function()
          if t == "basics" or t == "all" then
            query = ""
            setMode(t)
          else
            goTab(t)
          end
        end,
      })
    end
    local children = {
      ui.row({ gap = 6, align = "center" }, {
        ui.input({
          key = "search",
          value = query,
          focus = true,
          placeholder = "search key, action or command",
          controlSize = "sm",
          flexGrow = 1,
          onChange = function(text)
            query = text
            if tab == "backups" then
              tab = mode
            end
            render()
          end,
        }),
        tabButton("basics", "Basics"),
        tabButton("all", "All"),
        tabButton("edit", "Edit"),
        tabButton("backups", "Backups"),
        ui.button({ glyph = wide and "arrows-minimize" or "arrows-maximize", variant = "ghost", controlSize = "sm", tooltip = wide and "Compact" or "Full width", onClick = swap }),
        ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "Close", onClick = function() panel.close() end }),
      }),
    }
    if tab == "edit" or status ~= "" then
      local bar = {}
      if tab == "edit" then
        table.insert(bar, ui.button({ text = "Add key", glyph = "plus", variant = "ghost", controlSize = "sm", onClick = startAdd }))
      end
      table.insert(bar, ui.label({ text = status, fontSize = 11, color = "on_surface_variant", flexGrow = 1 }))
      table.insert(children, ui.row({ gap = 6, align = "center" }, bar))
    end
    table.insert(children, ui.scroll({ flexGrow = 1, key = "list" }, body()))
    panel.render(ui.column({ gap = 8, padding = 12, height = 560 }, children))
  end

  reload = function()
    noctalia.runAsync({ "mb-keys", "list", "--tsv" }, function(result)
      failed = result.exitCode ~= 0
      if not failed then
        parse(result.stdout or "")
      end
      if tab == "backups" then
        loadBackups()
      else
        render()
      end
    end)
  end

  return function()
    loadMode()
    tab = mode
    query = ""
    status = ""
    editing, conflict, armed = nil, nil, false
    binds = {}
    render()
    reload()
  end
end
