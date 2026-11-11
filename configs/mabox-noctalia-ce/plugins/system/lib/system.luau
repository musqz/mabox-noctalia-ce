--!nonstrict
-- System: tabs fed by `mb-sysreport <tab>`; the text is already sanitized.
local kbd = require("./kbd.luau")
local FIXES = require("./fixes.luau")
local newServices = require("./services.luau")

local TABS = {
  { id = "overview", label = "Overview" },
  { id = "hardware", label = "Hardware" },
  { id = "logs", label = "Logs" },
  { id = "report", label = "Report" },
  { id = "services", label = "Services" },
  { id = "fixes", label = "Fixes" },
  { id = "settings", label = "Settings" },
}

-- What the Report can hold; ids are `mb-sysreport report --parts` names.
local GROUPS = {
  { name = "Basics", items = {
    { "overview", "Overview" }, { "hardware", "Hardware" },
  } },
  { name = "Logs", items = {
    { "log-system", "System warnings" }, { "log-user", "User warnings" }, { "log-prev", "Previous boot" }, { "log-kernel", "Kernel" },
    { "log-failed", "Failed services" }, { "log-crashes", "Crashes" }, { "log-noctalia", "Noctalia" }, { "log-pacman", "Pacman" },
  } },
  { name = "Topics", items = {
    { "full", "Full system" }, { "hardware-only", "Hardware only" }, { "audio", "Audio" }, { "graphics", "Graphics" },
    { "network", "Network" }, { "bluetooth", "Bluetooth" }, { "disks", "Disks" }, { "boot", "Boot and kernel" },
    { "packages", "Packages" }, { "power", "Power" }, { "desktop", "Desktop and Noctalia" },
  } },
}

-- Detached (setsid) so the dialog outlives the panel; the pick goes to a file the panel reads when it reopens.
local BROWSE = [[s=${1:-$HOME/Documents}
case $s in "~"*) s=$HOME${s#"~"} ;; esac
p=$(yad --file --directory --center --width=1000 --height=650 --title="Save location" --filename="$s/")
[ -n "$p" ] && readlink -f "$p" > "$2"
noctalia msg panel-close; noctalia msg panel-open mabox/system:system]]

local LINKS = {
  { label = "Manual", url = "https://maboxlinux.org/users-guide/" },
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
  local picked = {}
  local choosing = false
  local runs = {}
  local hideWords = ""
  local saveDir = ""
  local private = false
  local checks = {}
  local cmdNonce = 0
  local openFix = nil
  local manjaro = true
  local note = ""
  local render
  local services

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

  local function standardParts()
    local set = {}
    for _, g in ipairs(GROUPS) do
      if g.name ~= "Topics" then
        for _, it in ipairs(g.items) do
          set[it[1]] = true
        end
      end
    end
    return set
  end

  local function partsList()
    local list = {}
    for _, g in ipairs(GROUPS) do
      for _, it in ipairs(g.items) do
        if picked[it[1]] then
          table.insert(list, it[1])
        end
      end
    end
    return list
  end

  local function loadSettings()
    local path = settingsPath()
    -- Line-anchored: a value may hold another key's name.
    local content = "\n" .. (path and noctalia.readFile(path) or "")
    local function key(name)
      return string.match(content, "\n" .. name .. "=([^\n]*)")
    end
    hideWords = noctalia.string.trim(key("hide") or "")
    saveDir = noctalia.string.trim(key("save_dir") or "")
    local saved = key("parts")
    if saved then
      picked = {}
      for id in string.gmatch(saved, "[^,]+") do
        picked[id] = true
      end
    else
      picked = standardParts()
    end
  end

  local function saveSettings()
    local path = settingsPath()
    if path then
      noctalia.mkdirAll(noctalia.pluginDataDir())
      noctalia.writeFile(path, "hide=" .. hideWords .. "\nsave_dir=" .. saveDir .. "\nparts=" .. table.concat(partsList(), ",") .. "\n")
    end
  end

  -- The folder chosen in the dialog arrives through a file; the panel was closed and reopened meanwhile.
  local function applyPick()
    local dir = noctalia.pluginDataDir()
    local pick = dir and noctalia.string.trim(noctalia.readFile(dir .. "/picked") or "") or ""
    if pick ~= "" then
      saveDir = pick
      noctalia.writeFile(dir .. "/picked", "")
      saveSettings()
    end
  end

  -- Cache key of what the current tab shows.
  local function current()
    return tab
  end

  -- Private keeps everything; public hides names, addresses, ids and the words from Settings.
  local function flags()
    if private then
      return { "--raw" }
    end
    local list = {}
    if hideWords ~= "" then
      table.insert(list, "--hide")
      table.insert(list, hideWords)
    end
    return list
  end

  local function load(id, force)
    if id == "services" then
      services.load(force)
      return
    end
    if id == "settings" or id == "fixes" or (cache[id] and not force) then
      return
    end
    cache[id] = { loading = true, text = cache[id] and cache[id].text }
    local mine = session
    runs[id] = (runs[id] or 0) + 1
    local run = runs[id]
    local argv = { "mb-sysreport", id }
    if id == "report" then
      local list = partsList()
      if #list == 0 then
        cache[id] = { text = "Nothing selected. Choose what the report should hold." }
        render()
        return
      end
      table.insert(argv, "--parts")
      table.insert(argv, table.concat(list, ","))
    end
    for _, f in ipairs(flags()) do
      table.insert(argv, f)
    end
    noctalia.runAsync(argv, function(result)
      if mine ~= session or run ~= runs[id] then
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

  -- Mode or hide words changed: everything is collected again.
  local function recollect()
    cache, checks = {}, {}
    session += 1
    note = ""
    load(current())
    if tab ~= "report" then
      load("report")
    end
    render()
  end

  local function setTab(id)
    tab = id
    note = ""
    local path = statePath()
    if path then
      noctalia.mkdirAll(noctalia.pluginDataDir())
      noctalia.writeFile(path, id .. "\n")
    end
    load(current())
    render()
  end

  local function terminal(...)
    noctalia.runAsync({ "sh", "-c", FIND_TERM, "sh", ... })
  end

  local function fixCommand(f)
    return not manjaro and f.arch_fix or f.fix
  end

  local function check(i)
    local f = FIXES[i]
    checks[i] = "Checking"
    render()
    local mine = session
    -- Through the scrubber: the output can hold the user name, addresses and ids.
    local argv = { "sh", "-c", "{ " .. f.check .. '\n} 2>&1 | mb-sysreport scrub "$@"', "sh" }
    for _, fl in ipairs(flags()) do
      table.insert(argv, fl)
    end
    noctalia.runAsync(argv, function(result)
      if mine ~= session then
        return
      end
      local out = noctalia.string.trim(result.stdout or "")
      checks[i] = out ~= "" and out or "(no output)"
      render()
    end)
  end

  local RUN_FIX = [[
printf '%s\n\n' "$1"
printf 'Run this command? [y/N] '
read -r a
case $a in y|Y) sh -c "$1" ;; *) echo cancelled ;; esac
printf '\nPress Enter to close '
read -r _
]]

  local function runFix(i)
    terminal("sh", "-c", RUN_FIX, "sh", fixCommand(FIXES[i]))
  end

  local function reportText()
    local entry = cache.report
    return entry and not entry.loading and entry.text or nil
  end

  -- Same default as mb-sysreport: Documents, or the home folder when that is missing.
  local OPEN_DIR = [[d=$1
[ -n "$d" ] || d=$(xdg-user-dir DOCUMENTS)
case $d in "~"*) d=$HOME${d#"~"} ;; esac
[ -d "$d" ] || { [ -z "$1" ] && d=$HOME; }
[ -d "$d" ] || { echo "$d is not a folder" >&2; exit 1; }
exec xdg-open "$d"]]

  local function openSaveDir()
    noctalia.runAsync({ "sh", "-c", OPEN_DIR, "sh", saveDir }, function(result)
      if result.exitCode ~= 0 then
        noctalia.notify("System", noctalia.string.trim(result.stderr or "") ~= "" and noctalia.string.trim(result.stderr) or "Could not open the folder")
      end
    end)
  end

  -- Via a file: a whole report is bigger than one argv entry may be (128 KB).
  local function copy(text, what, sensitive)
    local dir = noctalia.pluginDataDir()
    if not dir then
      noctalia.copyToClipboard(text, "text/plain")
      return
    end
    noctalia.mkdirAll(dir)
    local file = dir .. "/copy.txt"
    noctalia.writeFile(file, text)
    -- wl-copy sets the live selection; copyToClipboard only reaches the history.
    noctalia.runAsync({ "sh", "-c", 'wl-copy < "$1"; rc=$?; rm -f "$1"; exit $rc', "sh", file }, function(result)
      if result.exitCode ~= 0 then
        noctalia.copyToClipboard(text, "text/plain")
      end
      noctalia.notify("System", sensitive and private and "Private text copied. Do not paste it in a public place." or (what .. " copied"))
    end)
  end

  -- Writes the text on screen, so the file is what the user read.
  local function save()
    local dir = noctalia.pluginDataDir()
    local text = reportText()
    if not dir or not text or #partsList() == 0 then
      return
    end
    noctalia.mkdirAll(dir)
    local file = dir .. "/save.txt"
    noctalia.writeFile(file, text)
    local argv = { "mb-sysreport", "put", file }
    if saveDir ~= "" then
      table.insert(argv, "--dir")
      table.insert(argv, saveDir)
    end
    for _, f in ipairs(flags()) do
      if f == "--raw" then
        table.insert(argv, f)
      end
    end
    noctalia.runAsync(argv, function(result)
      local out = noctalia.string.trim(result.stdout or "")
      note = result.exitCode == 0 and ("Saved: " .. out) or ("Save failed: " .. noctalia.string.trim(result.stderr or ""))
      noctalia.notify("System", note)
      render()
    end)
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
      table.insert(items, ui.button({ text = "Choose parts (" .. #partsList() .. ")", glyph = choosing and "chevron-up" or "chevron-down", variant = "outline", controlSize = "sm", onClick = function() choosing = not choosing render() end }))
      local text = reportText()
      if text then
        if #partsList() > 0 then
          table.insert(items, ui.button({ text = "Save", glyph = "device-floppy", variant = "ghost", controlSize = "sm", onClick = save }))
        end
      end
      table.insert(items, ui.button({ glyph = "folder-open", variant = "ghost", controlSize = "sm", tooltip = "Open the save folder", onClick = openSaveDir }))
    elseif tab == "hardware" then
      table.insert(items, ui.button({ text = "btop", glyph = "terminal-2", variant = "ghost", controlSize = "sm", onClick = function() terminal("btop") end }))
      table.insert(items, ui.button({ text = "fastfetch", glyph = "terminal-2", variant = "ghost", controlSize = "sm", onClick = function() terminal("sh", "-c", "fastfetch; read -r _") end }))
    end
    return items
  end

  local function settingsBody()
    return {
      ui.label({ text = "Save location", fontSize = 12 }),
      ui.label({ text = "Folder for saved reports. Empty: your Documents folder.", fontSize = 11, color = "on_surface_variant" }),
      ui.row({ gap = 6, align = "center" }, {
        ui.input({
          key = "save_dir",
          value = saveDir,
          placeholder = "~/Documents",
          controlSize = "sm",
          flexGrow = 1,
          onChange = function(text)
            saveDir = noctalia.string.trim(text)
            saveSettings()
          end,
        }),
        ui.button({ glyph = "folder-open", variant = "outline", controlSize = "sm", tooltip = "Open this folder", onClick = openSaveDir }),
        ui.button({ text = "Browse", glyph = "folder-open", variant = "outline", controlSize = "sm", onClick = function()
          local dir = noctalia.pluginDataDir()
          if dir then
            noctalia.mkdirAll(dir)
            noctalia.runAsync({ "setsid", "-f", "sh", "-c", BROWSE, "sh", saveDir, dir .. "/picked" })
          end
        end }),
      }),
      ui.label({ text = "Words to hide (public view)", fontSize = 12 }),
      ui.label({ text = "Comma separated. Each word is replaced by <hidden>, on top of names, addresses and ids.", fontSize = 11, color = "on_surface_variant" }),
      ui.input({
        key = "hide_words",
        value = hideWords,
        placeholder = "Philips, mynas, jane",
        controlSize = "sm",
        onChange = function(text)
          hideWords = noctalia.string.trim(text)
          saveSettings()
          cache, checks = {}, {}
          session += 1
          services.clearStatus()
        end,
      }),
    }
  end

  local function ring(key, child)
    return ui.row({ key = key, padding = 3, radius = 8, border = "primary", borderWidth = kbd.sel(key) and 3 or 0 }, { child })
  end

  -- Titles only; the open one shows when/how, the command and the buttons.
  local function fixesBody()
    local rows = {}
    for i, f in ipairs(FIXES) do
      local open = openFix == i
      local hid = "fh" .. i
      local toggle = function()
        openFix = if open then nil else i
        render()
      end
      kbd.stop(hid, i * 2, 0, toggle)
      local card = {
        ui.row({ key = hid, gap = 6, align = "center", padding = 3, radius = 8, border = "primary", borderWidth = kbd.sel(hid) and 3 or 0 }, {
          ui.label({ text = f.title, fontWeight = "bold", fontSize = 14, flexGrow = 1 }),
          ui.button({ glyph = open and "chevron-up" or "chevron-down", variant = "ghost", controlSize = "sm", tooltip = open and "Less" or "More", onClick = toggle }),
        }),
      }
      if open then
        local cid, rid = "fc" .. i, "fr" .. i
        local checkAction = function() check(i) end
        local runAction = function() runFix(i) end
        local buttons = {}
        if f.check then
          kbd.stop(cid, i * 2 + 1, 0, checkAction)
          table.insert(buttons, ring(cid, ui.button({ text = "Check", glyph = "search", variant = "outline", controlSize = "sm", onClick = checkAction })))
        end
        table.insert(buttons, ui.button({ text = "Copy command", glyph = "copy", variant = "outline", controlSize = "sm", onClick = function() copy(fixCommand(f), "Command") end }))
        kbd.stop(rid, i * 2 + 1, 1, runAction)
        table.insert(buttons, ring(rid, ui.button({ text = "Run in terminal", glyph = "terminal-2", variant = "outline", controlSize = "sm", onClick = runAction })))
        table.insert(card, ui.label({ text = f.when, fontSize = 11, color = "on_surface_variant" }))
        table.insert(card, ui.label({ text = f.how, fontSize = 11, color = "on_surface_variant" }))
        -- An input so the text can be selected and copied with Ctrl+C; edits are undone, the run uses the table.
        table.insert(card, ui.column({ fill = "surface", radius = 6, padding = 6, border = "on_surface_variant", borderWidth = 1 }, {
          ui.input({
            key = "cmd" .. i .. "_" .. cmdNonce,
            value = fixCommand(f),
            multiline = true,
            frameVisible = false,
            height = 14 + 18 * math.ceil(#fixCommand(f) / 80),
            onChange = function()
              cmdNonce += 1
              render()
            end,
          }),
        }))
        table.insert(card, ui.row({ gap = 6 }, buttons))
        if checks[i] then
          table.insert(card, ui.label({ text = checks[i], fontSize = 11, fontFamily = "monospace" }))
        end
      end
      table.insert(rows, ui.column({ key = "fix" .. i, fill = "surface_variant", radius = 10, padding = 12, gap = 8, border = "primary", borderWidth = 1 }, card))
    end
    return rows
  end

  local function statusRows()
    local rows = {}
    if note ~= "" then
      local line = { ui.label({ text = note, fontSize = 12, flexGrow = 1 }) }
      table.insert(rows, ui.row({ gap = 6, align = "center" }, line))
    end
    return rows
  end

  render = function()
    kbd.begin()
    local entry = cache[current()]
    local text = entry and entry.text or "Collecting, this takes a few seconds..."
    local head = extras()
    table.insert(head, ui.spacer({ flexGrow = 1 }))
    local plain = tab == "settings" or tab == "fixes" or tab == "services"
    if not plain and entry and not entry.loading and entry.text then
      local shown = entry.text
      table.insert(head, ui.button({ text = private and "Copy private" or "Copy", glyph = "copy", variant = "outline", controlSize = "sm", tooltip = "Copy all text on this tab", onClick = function() copy(shown, "Text", true) end }))
    end
    if tab ~= "settings" and tab ~= "services" then
      local function mode(label, on, tip, set)
        table.insert(head, ui.button({ text = (on and "✓ " or "") .. label, variant = on and "primary" or "outline", controlSize = "sm", tooltip = tip, onClick = function()
          if not on then
            private = false
            set()
            recollect()
          end
        end }))
      end
      mode("Public", not private, "Names, addresses, ids and your hide words are removed", function() end)
      mode("Private", private, "Nothing is removed. Keep it to yourself", function() private = true end)
    end
    if tab ~= "settings" and tab ~= "fixes" then
      table.insert(head, ui.button({ glyph = "refresh", variant = "ghost", controlSize = "sm", tooltip = "Refresh", onClick = function() load(current(), true) end }))
    end
    table.insert(head, ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "Close", onClick = function() panel.close() end }))
    local body
    if tab == "fixes" then
      body = ui.scroll({ flexGrow = 1, key = "textfixes", revealKey = kbd.reveal() }, {
        ui.column({ gap = 10 }, fixesBody()),
      })
    elseif tab == "services" then
      body = services.body()
    elseif tab == "settings" then
      body = ui.column({ gap = 6, flexGrow = 1 }, settingsBody())
    else
      body = ui.column({ fill = "surface_variant", radius = 8, padding = 8, flexGrow = 1 }, {
        ui.scroll({ flexGrow = 1, key = "text" .. current(), revealKey = kbd.reveal() }, {
          ui.label({ text = text, fontSize = 12, fontFamily = "monospace", color = entry and entry.loading and "on_surface_variant" or "on_surface" }),
        }),
      })
    end
    local right = { ui.row({ gap = 6, align = "center" }, head) }
    if private and tab ~= "settings" and tab ~= "services" then
      table.insert(right, ui.row({ gap = 6, align = "center", fill = "surface_variant", radius = 8, padding = 8, border = "primary", borderWidth = 1 }, {
        ui.label({ text = "Private view. Names, addresses and ids are shown. Keep this text to yourself: do not paste it in a forum, an issue or a chat.", fontSize = 11, flexGrow = 1 }),
      }))
    end
    if tab == "report" and choosing then
      local function pick(set)
        picked = set
        saveSettings()
        cache.report = nil
        load("report")
        render()
      end
      local box = {}
      for _, g in ipairs(GROUPS) do
        local chips = {}
        for _, it in ipairs(g.items) do
          local on = picked[it[1]] == true
          table.insert(chips, ui.button({ key = "part-" .. it[1], text = (on and "✓ " or "") .. it[2], variant = on and "primary" or "outline", controlSize = "sm", onClick = function()
            picked[it[1]] = not on or nil
            pick(picked)
          end }))
        end
        table.insert(box, ui.label({ text = g.name, fontSize = 12, fontWeight = "bold" }))
        for n = 1, #chips, 6 do
          table.insert(box, ui.row({ gap = 4 }, { table.unpack(chips, n, math.min(n + 5, #chips)) }))
        end
      end
      -- Fixed height: the rows of chips are not measured reliably, so the box scrolls instead of overlapping.
      table.insert(right, ui.column({ gap = 6, height = 270, fill = "surface_variant", radius = 10, padding = 10, border = "primary", borderWidth = 1 }, {
        ui.row({ gap = 6, align = "center" }, {
          ui.label({ text = "Include in the report", fontSize = 12, fontWeight = "bold", flexGrow = 1 }),
          ui.button({ text = "Standard", variant = "outline", controlSize = "sm", onClick = function() pick(standardParts()) end }),
          ui.button({ text = "None", variant = "outline", controlSize = "sm", onClick = function() pick({}) end }),
        }),
        ui.scroll({ flexGrow = 1, key = "parts" }, {
          ui.column({ gap = 6 }, box),
        }),
      }))
    end
    if tab == "report" and not private then
      table.insert(right, ui.label({ text = "Read the text before you share it. Names, addresses and ids are removed, but log lines can still hold personal details.", fontSize = 11, color = "on_surface_variant" }))
    end
    if tab == "report" then
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

  services = newServices(function() render() end, function(...) terminal(...) end, function()
    -- Always the public scrub: this tab has no Public/Private switch.
    local list = {}
    if hideWords ~= "" then
      table.insert(list, "--hide")
      table.insert(list, hideWords)
    end
    return list
  end)

  local function onKey(chord)
    if kbd.key(chord) == "moved" then
      render()
    end
  end

  return function()
    cache = {}
    checks = {}
    private = false
    choosing = false
    openFix = nil
    services.reset()
    session += 1
    noctalia.runAsync({ "sh", "-c", "command -v pacman-mirrors >/dev/null" }, function(result)
      manjaro = result.exitCode == 0
    end)
    note = ""
    loadSettings()
    applyPick()
    kbd.clear()
    loadTab()
    load(current())
    -- Collected in the background so the Report tab is ready when it is opened.
    if tab ~= "report" then
      load("report")
    end
    render()
  end, onKey
end
