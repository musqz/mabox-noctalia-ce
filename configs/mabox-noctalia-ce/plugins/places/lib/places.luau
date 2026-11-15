--!nonstrict
-- Places: standard folders, file manager bookmarks and recent files; folders expand in place, right click opens pcmanfm.

local pinSide = require("./side.luau")
local logo = require("./celogo.luau")
local hotkey = require("./hotkey.luau")

return function(pinned)
local SIZES = { 5, 10, 20, 50 }

local HOME = noctalia.getenv("HOME")
local FOLDERS = {
  { name = "Home", glyph = "home", path = HOME },
  { name = "Downloads", glyph = "download", path = HOME .. "/Downloads" },
  { name = "Documents", glyph = "files", path = HOME .. "/Documents" },
  { name = "Music", glyph = "music", path = HOME .. "/Music" },
  { name = "Pictures", glyph = "photo", path = HOME .. "/Pictures" },
  { name = "Videos", glyph = "video", path = HOME .. "/Videos" },
  { name = "Trash", glyph = "trash", open = "trash:///" },
}

local places = {}
local drives = {}
local recent = {}
local expanded = {}
local listing = {}
local size = 10
local query = ""
local searchNonce = 0
local render

local ORDER = { "places", "bookmarks", "drives", "recent" }
local TITLES = { places = "Folders", bookmarks = "Bookmarks", drives = "Drives", recent = "Recent" }
local order = { table.unpack(ORDER) }
local hidden = {}
local editing = false

local function unescape(s)
  s = string.gsub(s, "%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
  return s
end

local function sizeFile()
  return noctalia.pluginDataDir() .. "/recent-size"
end

local function loadSize()
  local n = tonumber(string.match(noctalia.readFile(sizeFile()) or "", "%d+"))
  for _, s in ipairs(SIZES) do
    if s == n then
      size = n
    end
  end
end

local function setSize(n)
  size = n
  noctalia.mkdirAll(noctalia.pluginDataDir())
  noctalia.writeFile(sizeFile(), n .. "\n")
  render()
end

local function layoutFile()
  return noctalia.pluginDataDir() .. "/layout"
end

-- One id per line in order; a leading "!" marks a hidden card.
local function loadLayout()
  order, hidden = {}, {}
  local seen = {}
  for l in string.gmatch(noctalia.readFile(layoutFile()) or "", "[^\n]+") do
    local hide, id = string.match(l, "^(!?)(%a+)$")
    if id and TITLES[id] and not seen[id] then
      seen[id] = true
      table.insert(order, id)
      hidden[id] = hide == "!" or nil
    end
  end
  for _, id in ipairs(ORDER) do
    if not seen[id] then
      table.insert(order, id)
    end
  end
end

local function saveLayout()
  local out = {}
  for _, id in ipairs(order) do
    table.insert(out, (hidden[id] and "!" or "") .. id)
  end
  noctalia.mkdirAll(noctalia.pluginDataDir())
  noctalia.writeFile(layoutFile(), table.concat(out, "\n") .. "\n")
  render()
end

local function moveCard(i, d)
  local j = i + d
  if j < 1 or j > #order then
    return
  end
  order[i], order[j] = order[j], order[i]
  saveLayout()
end

local function toggleCard(id)
  hidden[id] = (not hidden[id]) or nil
  saveLayout()
end

local function loadPlaces()
  places = {}
  for _, f in ipairs(FOLDERS) do
    local target = f.open or f.path
    table.insert(places, { name = f.name, glyph = f.glyph, path = f.path, open = target, ok = f.open ~= nil or noctalia.fileExists(target), std = true })
  end
  local raw = noctalia.readFile(HOME .. "/.config/gtk-3.0/bookmarks") or ""
  if raw == "" then
    raw = noctalia.readFile(HOME .. "/.gtk-bookmarks") or ""
  end
  for line in string.gmatch(raw, "[^\n]+") do
    local uri, label = string.match(line, "^(%S+)%s*(.-)%s*$")
    if uri then
      local path = string.match(uri, "^file://(/.*)$")
      path = path and unescape(path)
      if label == "" then
        label = unescape(string.match(uri, "([^/]+)/*$") or uri)
      end
      table.insert(places, { name = label, glyph = "bookmark", path = path, open = path or uri, ok = path == nil or noctalia.fileExists(path) })
    end
  end
end

-- Parsing the xbel in Luau exceeds the script CPU budget, so python reads it.
local RECENT = [[import os, re, sys, urllib.parse
from html import unescape
raw = open(os.path.expanduser("~/.local/share/recently-used.xbel"), errors="replace").read()
found = []
for tag in re.findall(r"<bookmark\s[^>]*>", raw):
    h = re.search(r'href="file://([^"]*)"', tag)
    m = re.search(r'modified="([^"]*)"', tag)
    if h:
        found.append((m.group(1) if m else "", urllib.parse.unquote(unescape(h.group(1)))))
found.sort(reverse=True)
n = 0
for _, p in found:
    if os.path.exists(p) and "\n" not in p:
        print(p)
        n += 1
        if n >= int(sys.argv[1]):
            break]]

local function loadRecent()
  noctalia.runAsync({ "python3", "-I", "-c", RECENT, tostring(SIZES[#SIZES]) }, function(r)
    recent = {}
    for p in string.gmatch(r.stdout or "", "[^\n]+") do
      table.insert(recent, { path = p, name = string.match(p, "([^/]+)/*$") or p, dir = string.match(p, "^(.*)/[^/]*$") or "" })
    end
    render()
  end)
end

-- Removable (hotplug) partitions and anything udisks mounted under /run/media.
local function loadDrives()
  noctalia.runAsync({ "lsblk", "-P", "-p", "-o", "NAME,LABEL,MOUNTPOINT,TYPE,FSTYPE,HOTPLUG,SIZE" }, function(r)
    drives = {}
    for line in string.gmatch(r.stdout or "", "[^\n]+") do
      local d = {}
      for k, v in string.gmatch(line, '(%u+)="([^"]*)"') do
        d[k] = string.gsub(v, "\\x(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
      end
      local mp = d.MOUNTPOINT or ""
      if d.TYPE == "part" and (d.FSTYPE or "") ~= "" and not string.find(d.FSTYPE, "^crypto") and not string.find(d.FSTYPE, "_member$") and d.FSTYPE ~= "swap" and (d.HOTPLUG == "1" or string.find(mp, "^/run/media/")) then
        table.insert(drives, { dev = d.NAME, name = d.LABEL ~= "" and d.LABEL or string.match(d.NAME, "[^/]+$"), mount = mp, size = d.SIZE })
      end
    end
    render()
  end)
end

local function reload()
  loadPlaces()
  for path in pairs(expanded) do
    listDir(path)
  end
  render()
  loadDrives()
  loadRecent()
end

local function done()
  if not pinned then
    panel.close()
  end
end

local function openFolder(p)
  noctalia.runAsync({ "pcmanfm", p.open })
  done()
end

local function openDrive(d)
  if d.mount ~= "" then
    openFolder({ open = d.mount })
    return
  end
  noctalia.runAsync({ "udisksctl", "mount", "-b", d.dev }, function(r)
    local mp = string.match(r.stdout or "", " at (/[^\n]-)%.?%s*$")
    if mp then
      noctalia.runAsync({ "pcmanfm", mp })
    else
      noctalia.runAsync({ "notify-send", "-a", "Places", "Mount failed", d.name .. ": " .. noctalia.string.trim(r.stderr or "") })
    end
    loadDrives()
  end)
  done()
end

local function unmountDrive(d)
  noctalia.runAsync({ "udisksctl", "unmount", "-b", d.dev }, function(r)
    if r.exitCode ~= 0 then
      noctalia.runAsync({ "notify-send", "-a", "Places", "Unmount failed", d.name .. ": " .. noctalia.string.trim(r.stderr or "") })
    end
    loadDrives()
  end)
end

local function openFile(f)
  noctalia.runAsync({ "xdg-open", f.path })
  done()
end

-- wl-copy sets the live selection; copyToClipboard only reaches the history.
local function copyPath(f)
  noctalia.runAsync({ "wl-copy", "--", f.path }, function(r)
    if r.exitCode ~= 0 then
      noctalia.copyToClipboard(f.path, "text/plain")
    end
  end)
end

local function fsearch(text)
  if noctalia.string.trim(text or "") == "" then
    noctalia.runAsync({ "runraisehide", "fsearch" })
  else
    noctalia.runAsync({ "fsearch", "-s", text })
  end
  done()
end

-- Folder contents come from python: a script callback only gets 25 ms of CPU.
local LIST = [[import os, sys
out = []
try:
    with os.scandir(sys.argv[1]) as it:
        for e in it:
            if not e.name.startswith(".") and "\n" not in e.name:
                out.append((0 if e.is_dir() else 1, e.name.lower(), e.name))
except OSError:
    pass
for kind, _, name in sorted(out)[:300]:
    print("df"[kind] + name)]]

local function listDir(path)
  noctalia.runAsync({ "python3", "-I", "-c", LIST, path }, function(r)
    local items = {}
    for l in string.gmatch(r.stdout or "", "[^\n]+") do
      table.insert(items, { dir = string.sub(l, 1, 1) == "d", name = string.sub(l, 2) })
    end
    listing[path] = items
    render()
  end)
end

local function toggleDir(path)
  expanded[path] = (not expanded[path]) or nil
  if expanded[path] then
    listDir(path)
  end
  render()
end

-- Terminal from the Agents plugin setting, then $TERMINAL, then the first installed one.
local TERMINAL = [[t=$(sed -n 's/^terminal=//p' "${XDG_CONFIG_HOME:-$HOME/.config}/mabox/mb-agent-sessions.conf" 2>/dev/null)
for t in "$t" ${TERMINAL%% *} foot kitty alacritty terminator xfce4-terminal xterm; do
  if [ -n "$t" ] && command -v "$t" >/dev/null; then cd "$1" && exec setsid "$t"; fi
done]]

local function openTerminal(path)
  noctalia.runAsync({ "sh", "-c", TERMINAL, "sh", path })
  done()
end

local function dirRow(path, name, glyph, depth)
  local open = expanded[path]
  local row = {}
  if depth > 0 then
    table.insert(row, ui.box({ width = depth * 10, height = 0 }))
  end
  table.insert(row, ui.button({
    key = "t" .. path,
    glyph = open and "chevron-down" or glyph,
    text = name,
    variant = "ghost",
    contentAlign = "start",
    flexGrow = 1,
    tooltip = path .. "\nClick: show or hide the content, right click: open in the file manager",
    onClick = function() toggleDir(path) end,
    onRightClick = function() openFolder({ open = path }) end,
  }))
  if open then
    table.insert(row, ui.button({ key = "tt" .. path, glyph = "terminal-2", variant = "ghost", controlSize = "sm", tooltip = "Open in terminal", onClick = function() openTerminal(path) end }))
  end
  return ui.row({ key = "r" .. path, gap = 2, align = "center" }, row)
end

-- Rows under an expanded folder, subfolders first; recurses into expanded subfolders.
local function childRows(path, depth, out)
  local items = listing[path]
  if not items then
    return
  end
  if #items == 0 then
    table.insert(out, ui.row({ key = "e" .. path, gap = 0 }, { ui.box({ width = depth * 10 + 12, height = 0 }), ui.label({ text = "empty", color = "outline_variant" }) }))
  end
  for _, it in ipairs(items) do
    local full = (path == "/" and "" or path) .. "/" .. it.name
    if it.dir then
      table.insert(out, dirRow(full, it.name, "folder", depth))
      if expanded[full] then
        childRows(full, depth + 1, out)
      end
    else
      table.insert(out, ui.row({ key = "f" .. full, gap = 0, align = "center" }, {
        ui.box({ width = depth * 10, height = 0 }),
        ui.button({
          glyph = "file",
          text = it.name,
          variant = "ghost",
          contentAlign = "start",
          flexGrow = 1,
          tooltip = full .. "\nClick: open, right click: copy the path",
          onClick = function() openFile({ path = full }) end,
          onRightClick = function() copyPath({ path = full }) end,
        }),
      }))
    end
  end
end

local function card(key, children)
  return ui.column({ key = key, fill = "surface_variant", radius = 10, padding = 10, gap = 2, border = "primary", borderWidth = 1 }, children)
end

local function placeRows()
  local std, marks = {}, {}
  for i, p in ipairs(places) do
    local list = p.std and std or marks
    if p.path and p.ok then
      table.insert(list, dirRow(p.path, p.name, p.glyph, 0))
      if expanded[p.path] then
        childRows(p.path, 1, list)
      end
    else
      table.insert(list, ui.button({
        key = "p" .. i,
        glyph = p.glyph,
        text = p.name,
        variant = "ghost",
        contentAlign = "start",
        enabled = p.ok,
        tooltip = p.ok and (p.open .. "\nClick: open") or (p.open .. " is not available"),
        onClick = function() openFolder(p) end,
      }))
    end
  end
  local cards = { places = card("places", std) }
  if #marks > 0 then
    table.insert(marks, 1, ui.label({ text = "Bookmarks", color = "on_surface_variant" }))
    cards.bookmarks = card("bookmarks", marks)
  end
  return cards
end

local function driveCard()
  if #drives == 0 then
    return nil
  end
  local rows = {}
  for i, d in ipairs(drives) do
    local mounted = d.mount ~= ""
    table.insert(rows, ui.row({ key = "d" .. i, gap = 4, align = "center" }, {
      ui.button({
        glyph = "device-floppy",
        text = d.name .. "  " .. d.size,
        variant = "ghost",
        contentAlign = "start",
        flexGrow = 1,
        tooltip = mounted and (d.mount .. "\nClick: open") or (d.dev .. "\nClick: mount and open"),
        onClick = function() openDrive(d) end,
      }),
      mounted and ui.button({ key = "ej" .. i, glyph = "player-eject", variant = "ghost", controlSize = "sm", tooltip = "Unmount", onClick = function() unmountDrive(d) end }) or ui.box({ key = "ej" .. i, height = 0 }),
    }))
  end
  return card("drives", rows)
end

local function recentCard()
  local sizes = {}
  for _, n in ipairs(SIZES) do
    table.insert(sizes, ui.button({ key = "sz" .. n, text = tostring(n), variant = n == size and "primary" or "ghost", controlSize = "sm", tooltip = "Show " .. n .. " recent files", onClick = function() setSize(n) end }))
  end
  local rows = {
    ui.row({ gap = 4, align = "center" }, {
      ui.label({ text = "Recent", color = "on_surface_variant", flexGrow = 1 }),
      table.unpack(sizes),
    }),
  }
  for i, f in ipairs(recent) do
    if i > size then
      break
    end
    table.insert(rows, ui.button({
      key = "r" .. i,
      glyph = "file",
      text = f.name,
      variant = "ghost",
      contentAlign = "start",
      tooltip = f.dir .. "\nClick: open, right click: copy the path",
      onClick = function() openFile(f) end,
      onRightClick = function() copyPath(f) end,
    }))
  end
  if #rows == 1 then
    table.insert(rows, ui.label({ text = "No recent files", color = "on_surface_variant" }))
  end
  return card("recent", rows)
end

local function searchRow()
  return ui.row({ gap = 6, align = "center" }, {
    ui.input({
      key = "search" .. searchNonce,
      focus = not pinned,
      value = query,
      placeholder = "FSearch",
      controlSize = "sm",
      flexGrow = 1,
      onChange = function(text)
        local flip = (query == "") ~= (text == "")
        query = text
        if flip then
          render()
        end
      end,
      onSubmit = function() fsearch(query) end,
    }),
    ui.button({ key = "clear", glyph = "backspace", variant = "ghost", controlSize = "sm", enabled = query ~= "", tooltip = "Clear the search", onClick = function()
      query = ""
      searchNonce += 1
      render()
    end }),
    ui.button({ glyph = "search", variant = "ghost", controlSize = "sm", tooltip = "Open FSearch (Enter: search for the typed text)", onClick = function() fsearch(query) end }),
  })
end

render = function()
  local head
  local editButton = ui.button({ key = "edit", glyph = "adjustments", variant = editing and "primary" or "ghost", controlSize = "sm", tooltip = "Show, hide and move the cards", onClick = function()
    editing = not editing
    render()
  end })
  local collapseButton = ui.button({ key = "collapse", glyph = "arrows-minimize", variant = "ghost", controlSize = "sm", enabled = next(expanded) ~= nil, tooltip = "Close all open folders", onClick = function()
    expanded = {}
    render()
  end })
  if pinned then
    head = {
      ui.row({ gap = 8, align = "center" }, {
        logo(),
        ui.label({ text = "Places" }),
        ui.label({ text = hotkey("mb-pinned places"), color = "outline_variant", flexGrow = 1 }),
      }),
      ui.row({ gap = 6, align = "center" }, {
        ui.button({ glyph = "refresh", variant = "ghost", controlSize = "sm", tooltip = "Reload", onClick = reload }),
        editButton,
        collapseButton,
        ui.spacer({ flexGrow = 1 }),
        pinSide.dockButton("places", pinned, render),
        ui.button({ glyph = "arrows-left-right", variant = "ghost", controlSize = "sm", tooltip = "Move to the other side", onClick = function() pinSide.swap("places", pinned) end }),
        ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "Close", onClick = function() pinSide.close("places", pinned) end }),
      }),
      searchRow(),
    }
  else
    head = {
      ui.row({ gap = 8, align = "center" }, {
        logo(),
        ui.label({ text = "Places" }),
        ui.label({ text = hotkey("mabox/places:main"), color = "outline_variant", flexGrow = 1 }),
      }),
      searchRow(),
    }
    table.insert(head, 2, ui.row({ gap = 6, align = "center" }, {
      editButton,
      collapseButton,
      ui.spacer({ flexGrow = 1 }),
      ui.button({ glyph = "refresh", variant = "ghost", controlSize = "sm", tooltip = "Reload", onClick = reload }),
      ui.button({ glyph = "pin", variant = "ghost", controlSize = "sm", tooltip = "Pin window", onClick = function()
        panel.close()
        pinSide.toggle("places")
      end }),
      ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "Close", onClick = function() panel.close() end }),
    }))
  end
  loadLayout()
  local byId = placeRows()
  byId.drives = driveCard()
  byId.recent = recentCard()
  local cards = {}
  for i, id in ipairs(order) do
    if editing and byId[id] then
      table.insert(cards, ui.row({ key = "ed-" .. id, gap = 4, align = "center" }, {
        ui.label({ text = TITLES[id], color = hidden[id] and "outline_variant" or "on_surface", flexGrow = 1 }),
        ui.button({ key = "up-" .. id, glyph = "arrow-up", variant = "ghost", controlSize = "sm", enabled = i > 1, tooltip = "Move up", onClick = function() moveCard(i, -1) end }),
        ui.button({ key = "dn-" .. id, glyph = "arrow-down", variant = "ghost", controlSize = "sm", enabled = i < #order, tooltip = "Move down", onClick = function() moveCard(i, 1) end }),
        ui.button({ key = "ey-" .. id, glyph = hidden[id] and "eye-off" or "eye", variant = "ghost", controlSize = "sm", tooltip = hidden[id] and "Show" or "Hide", onClick = function() toggleCard(id) end }),
      }))
    elseif byId[id] and not hidden[id] then
      table.insert(cards, byId[id])
    end
  end
  table.insert(head, ui.scroll({ gap = 8, flexGrow = 1, key = "list" }, cards))
  pinSide.render(pinned, ui.column({ gap = 8, padding = 10, flexGrow = 1, height = (not pinned) and 712 or nil }, head))
end

local function open()
  editing = false
  expanded = {}
  listing = {}
  loadLayout()
  loadSize()
  reload()
end

local function tick() end

local function close() end

local function key(chord)
  if chord == "escape" then
    panel.close()
  end
end

return open, tick, close, key
end
