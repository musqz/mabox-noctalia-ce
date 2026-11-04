--!nonstrict
-- System: tabs fed by `mb-sysreport <tab>`; the text is already sanitized.
local kbd = require("./kbd.luau")

local TABS = {
  { id = "overview", label = "Overview" },
  { id = "hardware", label = "Hardware" },
  { id = "logs", label = "Logs" },
  { id = "report", label = "Report" },
  { id = "settings", label = "Settings" },
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
  local pasteUrl = ""
  local note = ""
  local confirming = false
  local link = nil
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

  local function settingsPath()
    local dir = noctalia.pluginDataDir()
    return dir and dir .. "/settings" or nil
  end

  local function loadSettings()
    local path = settingsPath()
    pasteUrl = path and string.match(noctalia.readFile(path) or "", "paste_url=([^\n]*)") or ""
    pasteUrl = noctalia.string.trim(pasteUrl)
  end

  local function saveSettings()
    local path = settingsPath()
    if path then
      noctalia.mkdirAll(noctalia.pluginDataDir())
      noctalia.writeFile(path, "paste_url=" .. pasteUrl .. "\n")
    end
  end

  local function pasteHost()
    local authority = string.match(pasteUrl, "^https?://([^/?#]+)")
    -- user@host in the address would show one host in the prompt and post to another.
    if not authority or string.find(authority, "@", 1, true) then
      return nil
    end
    return authority
  end

  local function load(id, force)
    if id == "settings" or (cache[id] and not force) then
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
    note, confirming, link = "", false, nil
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

  local function reportText()
    local entry = cache.report
    return entry and not entry.loading and entry.text or nil
  end

  -- Via a file: a whole report is bigger than one argv entry may be (128 KB).
  local function copy(text, what)
    local dir = noctalia.pluginDataDir()
    local file = dir and dir .. "/copy.txt"
    if file then
      noctalia.mkdirAll(dir)
      noctalia.writeFile(file, text)
    end
    -- wl-copy sets the live selection; copyToClipboard only reaches the history.
    noctalia.runAsync({ "sh", "-c", 'wl-copy < "$1"; rc=$?; rm -f "$1"; exit $rc', "sh", file or "/dev/null" }, function(result)
      if result.exitCode ~= 0 then
        noctalia.copyToClipboard(text, "text/plain")
      end
      noctalia.notify("System", what .. " copied")
    end)
  end

  local function save()
    noctalia.runAsync({ "mb-sysreport", "report", "--save" }, function(result)
      local out = noctalia.string.trim(result.stdout or "")
      note = result.exitCode == 0 and ("Saved: " .. out) or "Save failed"
      noctalia.notify("System", note)
      render()
    end)
  end

  -- Sends the text on screen, not a fresh run, so what the user read is what leaves.
  local function upload(text)
    local dir = noctalia.pluginDataDir()
    if not dir or not pasteHost() then
      note = "Set an http(s) address in Settings"
      return
    end
    noctalia.mkdirAll(dir)
    local file = dir .. "/upload.txt"
    noctalia.writeFile(file, text)
    note = "Uploading"
    noctalia.runAsync({ "sh", "-c", 'curl -sS --max-time 30 --data-binary @"$1" "$2"; rc=$?; rm -f "$1"; exit $rc', "sh", file, pasteUrl }, function(result)
      local out = noctalia.string.trim(result.stdout or "")
      if result.exitCode == 0 and out ~= "" then
        link = out
        note = "Uploaded"
      else
        note = "Upload failed: " .. noctalia.string.trim(result.stderr or "")
      end
      render()
    end)
    render()
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
    elseif tab == "report" then
      local text = reportText()
      if text then
        table.insert(items, ui.button({ text = "Copy", glyph = "copy", variant = "ghost", controlSize = "sm", onClick = function() copy(text, "Report") end }))
        table.insert(items, ui.button({ text = "Save", glyph = "device-floppy", variant = "ghost", controlSize = "sm", onClick = save }))
        if pasteHost() then
          table.insert(items, ui.button({ text = "Upload", glyph = "upload", variant = "ghost", controlSize = "sm", onClick = function() confirming = true render() end }))
        end
      end
    elseif tab == "hardware" then
      table.insert(items, ui.button({ text = "btop", glyph = "terminal-2", variant = "ghost", controlSize = "sm", onClick = function() terminal("btop") end }))
      table.insert(items, ui.button({ text = "fastfetch", glyph = "terminal-2", variant = "ghost", controlSize = "sm", onClick = function() terminal("sh", "-c", "fastfetch; read -r _") end }))
    end
    return items
  end

  local function settingsBody()
    local bad = pasteUrl ~= "" and not pasteHost()
    return {
      ui.label({ text = "Upload address (optional)", fontSize = 12 }),
      ui.label({ text = "A pastebin that takes a raw POST body and answers with the link. Empty: the Report tab has no Upload button and nothing leaves this machine.", fontSize = 11, color = "on_surface_variant" }),
      ui.input({
        key = "paste_url",
        value = pasteUrl,
        placeholder = "https://paste.example.org/",
        controlSize = "sm",
        onChange = function(text)
          pasteUrl = noctalia.string.trim(text)
          saveSettings()
          render()
        end,
      }),
      bad and ui.label({ text = "Only http(s) addresses are used", fontSize = 11, color = "primary" }) or ui.spacer({ height = 0 }),
    }
  end

  local function statusRows()
    local rows = {}
    if confirming and pasteHost() then
      table.insert(rows, ui.row({ gap = 6, align = "center", fill = "surface_variant", radius = 8, padding = 6 }, {
        ui.label({ text = "Send the report shown below to " .. pasteHost() .. "?", fontSize = 12, flexGrow = 1 }),
        ui.button({ text = "Send", variant = "primary", controlSize = "sm", onClick = function()
          confirming = false
          local text = reportText()
          if text then
            upload(text)
          end
        end }),
        ui.button({ text = "Cancel", variant = "ghost", controlSize = "sm", onClick = function() confirming = false render() end }),
      }))
    end
    if note ~= "" then
      local line = { ui.label({ text = link and (note .. ": " .. link) or note, fontSize = 12, flexGrow = 1 }) }
      if link then
        local url = link
        table.insert(line, ui.button({ text = "Copy link", glyph = "copy", variant = "ghost", controlSize = "sm", onClick = function() copy(url, "Link") end }))
      end
      table.insert(rows, ui.row({ gap = 6, align = "center" }, line))
    end
    return rows
  end

  render = function()
    kbd.begin()
    local entry = cache[tab]
    local text = entry and entry.text or "Loading"
    local head = extras()
    table.insert(head, ui.spacer({ flexGrow = 1 }))
    if tab ~= "settings" then
      table.insert(head, ui.button({ glyph = "refresh", variant = "ghost", controlSize = "sm", tooltip = "Refresh", onClick = function() load(tab, true) end }))
    end
    table.insert(head, ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "Close", onClick = function() panel.close() end }))
    local body
    if tab == "settings" then
      body = ui.column({ gap = 6, flexGrow = 1 }, settingsBody())
    else
      body = ui.scroll({ flexGrow = 1, key = "text" .. tab, revealKey = kbd.reveal() }, {
        ui.label({ text = text, fontSize = 12, fontFamily = "monospace", color = entry and entry.loading and "on_surface_variant" or "on_surface" }),
      })
    end
    local right = { ui.row({ gap = 6, align = "center" }, head) }
    if tab == "report" then
      table.insert(right, ui.label({ text = "Read the text before you share it. Names, addresses and ids are removed, but log lines can still hold personal details.", fontSize = 11, color = "on_surface_variant" }))
      for _, r in ipairs(statusRows()) do
        table.insert(right, r)
      end
    end
    table.insert(right, body)
    panel.render(ui.row({ gap = 8, padding = 12, height = 560 }, {
      sidebar(),
      ui.column({ gap = 8, flexGrow = 1 }, right),
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
    note, confirming, link = "", false, nil
    loadSettings()
    kbd.clear()
    loadTab()
    load(tab)
    render()
  end, onKey
end
