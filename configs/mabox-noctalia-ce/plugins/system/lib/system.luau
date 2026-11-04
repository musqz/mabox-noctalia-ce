--!nonstrict
-- System: tabs fed by `mb-sysreport <tab>`; the text is already sanitized.
local kbd = require("./kbd.luau")

local TABS = {
  { id = "overview", label = "Overview" },
  { id = "hardware", label = "Hardware" },
}

local LINKS = {
  { label = "Manual", url = "https://maboxlinux.org/manual/" },
  { label = "Forum", url = "https://forum.maboxlinux.org/" },
  { label = "Website", url = "https://maboxlinux.org/" },
}

-- setsid: the panel closing when the terminal takes focus would otherwise kill it.
local FIND_TERM = [[
for t in "${TERMINAL:-}" foot kitty alacritty terminator xfce4-terminal xterm; do
  [ -n "$t" ] && command -v "$t" >/dev/null && break
done
case $t in terminator|xfce4-terminal) f=-x ;; *) f=-e ;; esac
exec setsid -f "$t" "$f" "$@"
]]

return function()
  local tab = "overview"
  local cache = {}
  local session = 0
  local render

  local function statePath()
    local dir = noctalia.pluginDataDir()
    return dir and dir .. "/tab" or nil
  end

  local function loadTab()
    local path = statePath()
    local saved = path and noctalia.string.trim(noctalia.readFile(path) or "") or ""
    tab = "overview"
    for _, t in ipairs(TABS) do
      if t.id == saved then
        tab = saved
      end
    end
  end

  local function load(id, force)
    if cache[id] and not force then
      return
    end
    cache[id] = { loading = true, text = cache[id] and cache[id].text }
    local mine = session
    noctalia.runAsync({ "mb-sysreport", id }, function(result)
      if mine ~= session then
        return
      end
      local text = result.stdout or ""
      if result.stdoutTruncated then
        text = text .. "\n(output truncated)"
      end
      cache[id] = { text = result.exitCode == 0 and text or "mb-sysreport failed: " .. (result.stderr or "") }
      render()
    end)
    render()
  end

  local function setTab(id)
    tab = id
    local path = statePath()
    if path then
      noctalia.mkdirAll(noctalia.pluginDataDir())
      noctalia.writeFile(path, id .. "\n")
    end
    load(id)
    render()
  end

  local function terminal(...)
    noctalia.runAsync({ "sh", "-c", FIND_TERM, "sh", ... })
  end

  local function sidebar()
    local items = {}
    for i, t in ipairs(TABS) do
      local sid = "s" .. t.id
      local action = function() setTab(t.id) end
      kbd.stop(sid, i, -1, action)
      table.insert(items, ui.row({ key = sid, padding = 3, radius = 8, border = "primary", borderWidth = kbd.sel(sid) and 3 or 0 }, {
        ui.button({ text = t.label, variant = t.id == tab and "primary" or "ghost", controlSize = "sm", flexGrow = 1, onClick = action }),
      }))
    end
    return ui.column({ width = 150, gap = 2 }, items)
  end

  local function extras()
    local items = {}
    if tab == "overview" then
      for _, l in ipairs(LINKS) do
        table.insert(items, ui.button({ text = l.label, glyph = "external-link", variant = "ghost", controlSize = "sm", onClick = function() noctalia.runAsync({ "xdg-open", l.url }) end }))
      end
    elseif tab == "hardware" then
      table.insert(items, ui.button({ text = "btop", glyph = "terminal-2", variant = "ghost", controlSize = "sm", onClick = function() terminal("btop") end }))
      table.insert(items, ui.button({ text = "fastfetch", glyph = "terminal-2", variant = "ghost", controlSize = "sm", onClick = function() terminal("sh", "-c", "fastfetch; read -r _") end }))
    end
    return items
  end

  render = function()
    kbd.begin()
    local entry = cache[tab]
    local text = entry and entry.text or "Loading"
    local head = extras()
    table.insert(head, ui.spacer({ flexGrow = 1 }))
    table.insert(head, ui.button({ glyph = "refresh", variant = "ghost", controlSize = "sm", tooltip = "Refresh", onClick = function() load(tab, true) end }))
    table.insert(head, ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "Close", onClick = function() panel.close() end }))
    local side = sidebar()
    panel.render(ui.row({ gap = 8, padding = 12, height = 560 }, {
      side,
      ui.column({ gap = 8, flexGrow = 1 }, {
        ui.row({ gap = 6, align = "center" }, head),
        ui.scroll({ flexGrow = 1, key = "text" .. tab, revealKey = kbd.reveal() }, {
          ui.label({ text = text, fontSize = 12, fontFamily = "monospace", color = entry and entry.loading and "on_surface_variant" or "on_surface" }),
        }),
      }),
    }))
  end

  local function onKey(chord)
    if kbd.key(chord) == "moved" then
      render()
    end
  end

  return function()
    cache = {}
    session += 1
    kbd.clear()
    loadTab()
    load(tab)
    render()
  end, onKey
end
