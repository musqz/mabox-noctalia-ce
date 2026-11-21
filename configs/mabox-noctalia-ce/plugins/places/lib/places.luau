--!nonstrict
-- Places: standard folders, file manager bookmarks and recent files; folders expand in place, right click opens the file manager.

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
local newIn = nil
local newTag = nil
local newName = ""
local size = 10
local query = ""
local treeQuery = ""
local treeIdx = 1
local hitKey = nil
local hitPath = nil
local forceOpen = {}
local driveMode = 0
-- Search scope, index 1-3: folders only, folders and drives, drives only.
local DRIVE_MODES = {
  { glyph = "folder", text = "Folders", tooltip = "Searching your folders only (click: add the mounted drives)" },
  { glyph = "database", text = "Folders + drives", tooltip = "Searching your folders and the mounted drives (click: drives only)" },
  { glyph = "server", text = "Drives", tooltip = "Searching the mounted drives only (click: folders only)" },
}
local autoOpened = {}
local hitCount = 0
local indexReady = false
local indexGen = 0
local HIT_ROWS = 60
local hitMore = 0 -- matches beyond the listed ones
local treeNonce = 0
local hitList = {} -- every folder the tree search found, shallow ones first
local searchNonce = 0
local render
local listDir

local ORDER = { "quick", "places", "bookmarks", "drives", "recent" }
local TITLES = { quick = "Quick", places = "Folders", bookmarks = "Bookmarks", drives = "Drives", recent = "Recent" }
local order = { table.unpack(ORDER) }
local hidden = {}
local folded = {}
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

-- Quick: a working list of folders and files kept at the top while a project is going on, saved as named project profiles.
-- Files hold one "d<TAB>path" or "f<TAB>path" per line: the list in <data>/quick, a profile in <data>/quick-profiles/<name>.list.
local quick = {}
local qProfiles = {}
local qName = ""
local qNonce = 0
local qDel, qDelAt = nil, 0

local function quickFile()
  return noctalia.pluginDataDir() .. "/quick"
end

local function profDir()
  return noctalia.pluginDataDir() .. "/quick-profiles"
end

local function parseQuick(text)
  local list = {}
  for l in string.gmatch(text or "", "[^\n]+") do
    local kind, path = string.match(l, "^([df])\t(.+)$")
    if kind then
      table.insert(list, { kind = kind, path = path })
    end
  end
  return list
end

local function quickText()
  local out = {}
  for _, q in ipairs(quick) do
    table.insert(out, q.kind .. "\t" .. q.path)
  end
  return table.concat(out, "\n") .. (#out > 0 and "\n" or "")
end

local qActive = nil -- the project stars go into; nil: the temporary list

local function activeFile()
  return noctalia.pluginDataDir() .. "/quick-active"
end

local function listFile()
  return qActive and (profDir() .. "/" .. qActive .. ".list") or quickFile()
end

local function saveQuick()
  noctalia.mkdirAll(noctalia.pluginDataDir())
  noctalia.mkdirAll(profDir())
  noctalia.writeFile(listFile(), quickText())
end

local function setActive(name)
  qActive = name
  noctalia.mkdirAll(noctalia.pluginDataDir())
  noctalia.writeFile(activeFile(), (name or "") .. "\n")
end

local quickSet = {}

local function isQuick(path)
  return quickSet[path] == true
end

-- The panel and the pinned window are two Lua states over the same files: the active project and its list are read again
-- before they are changed or drawn, else the one with the older copy overwrites the other's stars.
local function reloadQuick()
  local name = noctalia.string.trim(noctalia.readFile(activeFile()) or "")
  qActive = (name ~= "" and noctalia.fileExists(profDir() .. "/" .. name .. ".list")) and name or nil
  quick = parseQuick(noctalia.readFile(listFile()))
  quickSet = {}
  for _, q in ipairs(quick) do
    quickSet[q.path] = true
  end
end

local function toggleQuick(kind, path)
  reloadQuick()
  for i, q in ipairs(quick) do
    if q.path == path then
      table.remove(quick, i)
      saveQuick()
      render()
      return
    end
  end
  table.insert(quick, { kind = kind, path = path })
  saveQuick()
  render()
end

local function loadQProfiles()
  qProfiles = {}
  for _, f in (noctalia.listDir(profDir()) or {}) do
    local name = string.match(f, "^(.+)%.list$")
    if name then
      table.insert(qProfiles, name)
    end
  end
  table.sort(qProfiles)
end

-- A new project becomes the active one. Made from the temporary list it keeps that list; made inside a project it starts empty.
local function saveQProfile()
  local name = noctalia.string.trim((string.gsub(qName, "[^%w _%-]", "")))
  if name == "" then
    return
  end
  reloadQuick()
  noctalia.mkdirAll(profDir())
  -- an existing name only becomes the active project; its list is kept
  if not noctalia.fileExists(profDir() .. "/" .. name .. ".list") then
    noctalia.writeFile(profDir() .. "/" .. name .. ".list", qActive and "" or quickText())
  end
  setActive(name)
  qName = ""
  qNonce += 1
  loadQProfiles()
  render()
end

-- Clicking the active project again goes back to the temporary list.
local function toggleQProfile(name)
  reloadQuick()
  setActive(qActive ~= name and name or nil)
  render()
end

local function deleteQProfile()
  reloadQuick()
  local name = qDel
  qDel = nil
  if name then
    if qActive == name then
      setActive(nil)
    end
    noctalia.runAsync({ "rm", "-f", "--", profDir() .. "/" .. name .. ".list" }, function()
      loadQProfiles()
      render()
    end)
  end
end

-- Stars only show while a project is active: they go into that project.
local function starButton(kind, path, tag)
  if not qActive then
    return ui.box({ key = "st" .. tag .. path, width = 0, height = 0 })
  end
  local on = isQuick(path)
  return ui.button({
    key = "st" .. tag .. path,
    glyph = on and "star-filled" or "star",
    variant = on and "primary" or "ghost",
    controlSize = "sm",
    onClick = function() toggleQuick(kind, path) end,
  })
end

local function layoutFile()
  return noctalia.pluginDataDir() .. "/layout"
end

-- One id per line in order; a leading "!" marks a hidden card, "~" a folded one.
local function loadLayout()
  order, hidden, folded = {}, {}, {}
  local seen = {}
  for l in string.gmatch(noctalia.readFile(layoutFile()) or "", "[^\n]+") do
    local hide, fold, id = string.match(l, "^(!?)(~?)(%a+)$")
    if id and TITLES[id] and not seen[id] then
      seen[id] = true
      table.insert(order, id)
      hidden[id] = hide == "!" or nil
      folded[id] = fold == "~" or nil
    end
  end
  for _, id in ipairs(ORDER) do
    if not seen[id] then
      -- a card added later: Quick belongs on top, the rest goes last
      table.insert(order, id == "quick" and 1 or #order + 1, id)
    end
  end
end

local function saveLayout()
  local out = {}
  for _, id in ipairs(order) do
    table.insert(out, (hidden[id] and "!" or "") .. (folded[id] and "~" or "") .. id)
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

local function toggleFold(id)
  if forceOpen[id] then
    forceOpen[id] = nil
  else
    folded[id] = (not folded[id]) or nil
  end
  saveLayout()
end

-- The trash of the home disk; gio trash --empty clears every trash it knows. Emptying asks first and the question lapses.
local trashCount = 0
local trashAsk, trashAt = false, 0

local function countTrash()
  local items = noctalia.listDir(HOME .. "/.local/share/Trash/files")
  trashCount = 0
  for _ in (items or {}) do
    trashCount += 1
  end
end

local function emptyTrash()
  trashAsk = false
  noctalia.runAsync({ "gio", "trash", "--empty" }, function(r)
    countTrash()
    if r.exitCode ~= 0 then
      noctalia.notify("Places", "Could not empty the trash")
    end
    render()
  end)
  render()
end

local function loadPlaces()
  countTrash()
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

-- Partitions with a filesystem, mounted or not; the system mounts are left out.
local SYSTEM = { "/", "/boot", "/efi", "/usr", "/var", "/home", "/opt", "/srv", "/root", "/tmp", "/etc" }
local function isSystemMount(mp)
  for _, p in ipairs(SYSTEM) do
    if mp == p or (p ~= "/" and string.sub(mp, 1, #p + 1) == p .. "/") then
      return true
    end
  end
  return false
end

local function loadDrives()
  noctalia.runAsync({ "lsblk", "-P", "-p", "-o", "NAME,LABEL,MOUNTPOINT,TYPE,FSTYPE,HOTPLUG,SIZE" }, function(r)
    drives = {}
    for line in string.gmatch(r.stdout or "", "[^\n]+") do
      local d = {}
      for k, v in string.gmatch(line, '(%u+)="([^"]*)"') do
        d[k] = string.gsub(v, "\\x(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
      end
      local mp = d.MOUNTPOINT or ""
      if d.TYPE == "part" and (d.FSTYPE or "") ~= "" and not string.find(d.FSTYPE, "^crypto") and not string.find(d.FSTYPE, "_member$") and d.FSTYPE ~= "swap" and not isSystemMount(mp) then
        table.insert(drives, { dev = d.NAME, name = d.LABEL ~= "" and d.LABEL or string.match(d.NAME, "[^/]+$"), mount = mp, size = d.SIZE, hot = d.HOTPLUG == "1" })
      end
    end
    render()
  end)
end

local function reload()
  indexReady = false
  indexGen += 1
  indexing = false
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
  noctalia.runAsync({ "mb-files", p.open })
  done()
end

local function openFileDir(path)
  local d = string.match(path, "^(.*)/[^/]*$")
  openFolder({ open = (d == nil or d == "") and "/" or d })
end

local function openDrive(d)
  if d.mount ~= "" then
    openFolder({ open = d.mount })
    return
  end
  noctalia.runAsync({ "udisksctl", "mount", "-b", d.dev }, function(r)
    local mp = string.match(r.stdout or "", " at (/[^\n]-)%.?%s*$")
    if mp then
      noctalia.runAsync({ "mb-files", mp })
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

listDir = function(path)
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
  autoOpened[path] = nil
  expanded[path] = (not expanded[path]) or nil
  if newIn == path then
    newIn = nil
  end
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

local function createFolder(path)
  local name = noctalia.string.trim(newName)
  if name == "" or string.find(name, "/", 1, true) or name == "." or name == ".." then
    noctalia.notify("Places", "Use a folder name without a slash")
    return
  end
  if string.sub(name, 1, 1) == "." or string.find(name, "\n", 1, true) then
    noctalia.notify("Places", "Hidden names are not shown in this list")
    return
  end
  noctalia.runAsync({ "mkdir", "--", path .. "/" .. name }, function(r)
    if r.exitCode ~= 0 then
      noctalia.notify("Places", "Could not create " .. name .. ": " .. noctalia.string.trim(r.stderr or ""))
      return
    end
    newIn = nil
    newName = ""
    listDir(path)
  end)
end

local function newFolderRow(path, depth, tag)
  return ui.row({ key = "nf" .. tag .. path, gap = 4, align = "center" }, {
    ui.box({ width = depth * 10 + 12, height = 0 }),
    ui.input({ key = "nfi" .. tag .. path, focus = true, value = newName, placeholder = "New folder name", controlSize = "sm", flexGrow = 1, onChange = function(t) newName = t end, onSubmit = function() createFolder(path) end }),
    ui.button({ key = "nfb" .. tag .. path, glyph = "check", variant = "ghost", controlSize = "sm", tooltip = "Create the folder", onClick = function() createFolder(path) end }),
  })
end

local function dirRow(path, name, glyph, depth, tag, fill)
  local open = expanded[path]
  local row = {}
  if depth > 0 then
    table.insert(row, ui.box({ width = depth * 10, height = 0 }))
  end
  local title = ui.button({
    key = "t" .. tag .. path,
    selected = hitKey == "r" .. tag .. path,
    glyph = open and "chevron-down" or glyph,
    text = name,
    variant = "ghost",
    contentAlign = "start",
    flexGrow = 1,
    tooltip = path .. "\nClick: show or hide the content, right click: open in the file manager",
    onClick = function() toggleDir(path) end,
    onRightClick = function() openFolder({ open = path }) end,
  })
  if open and depth > 0 then
    -- The name of an open subfolder takes the hover color; a button has no text color, so it is a row of glyph and label.
    title = ui.row({
      key = "to" .. tag .. path,
      gap = 6,
      align = "center",
      padding = 6,
      flexGrow = 1,
      tooltip = path .. "\nClick: hide the content, right click: open in the file manager",
      onClick = function() toggleDir(path) end,
      onRightClick = function() openFolder({ open = path }) end,
    }, {
      ui.glyph({ name = "chevron-down", size = 14, color = "hover" }),
      ui.label({ text = name, color = "hover", maxLines = 1, flexGrow = 1 }),
    })
  end
  table.insert(row, title)
  if open then
    table.insert(row, ui.button({ key = "tn" .. tag .. path, glyph = "folder-plus", variant = (newIn == path and newTag == tag) and "primary" or "ghost", controlSize = "sm", tooltip = "New folder", onClick = function()
      newIn = (newIn ~= path or newTag ~= tag) and path or nil
      newTag = tag
      newName = ""
      render()
    end }))
    table.insert(row, ui.button({ key = "tt" .. tag .. path, glyph = "terminal-2", variant = "ghost", controlSize = "sm", tooltip = "Open in terminal", onClick = function() openTerminal(path) end }))
  end
  table.insert(row, starButton("d", path, tag))
  return ui.row({ key = "r" .. tag .. path, gap = 2, align = "center", fill = fill, radius = fill and 6 or nil }, row)
end

-- Rows under an expanded folder, subfolders first; recurses into expanded subfolders.
local function childRows(path, depth, out, tag)
  local items = listing[path]
  if not items then
    return
  end
  if #items == 0 then
    table.insert(out, ui.row({ key = "e" .. tag .. path, gap = 0 }, { ui.box({ width = depth * 10 + 12, height = 0 }), ui.label({ text = "empty", color = "outline_variant" }) }))
  end
  -- Every second row of a folder's content gets a slightly darker background. Both fills are explicit: a retained widget
  -- would keep an old one when the rows move after a fold.
  local function stripe(i)
    return i % 2 == 1 and "surface" or "surface_variant"
  end
  for i, it in ipairs(items) do
    local full = (path == "/" and "" or path) .. "/" .. it.name
    if it.dir then
      if expanded[full] then
        -- An open folder at any level sits in a frame of its own with its content; the key differs from the closed row.
        local group = { dirRow(full, it.name, "folder", depth, tag, stripe(i)) }
        if newIn == full and newTag == tag then
          table.insert(group, newFolderRow(full, depth + 1, tag))
        end
        childRows(full, depth + 1, group, tag)
        table.insert(out, ui.column({ key = "frame" .. tag .. full, gap = 2, padding = 4, radius = 8, border = "outline_variant", borderWidth = 1 }, group))
      else
        table.insert(out, dirRow(full, it.name, "folder", depth, tag, stripe(i)))
      end
    else
      table.insert(out, ui.row({ key = "f" .. tag .. full, gap = 0, align = "center", fill = stripe(i), radius = 6 }, {
        ui.box({ width = depth * 10, height = 0 }),
        ui.button({
          selected = hitKey == "f" .. tag .. full,
          glyph = "file",
          text = it.name,
          variant = "ghost",
          contentAlign = "start",
          flexGrow = 1,
          tooltip = full .. "\nClick: open, right click: open the folder",
          onClick = function() openFile({ path = full }) end,
          onRightClick = function() openFileDir(full) end,
        }),
        starButton("f", full, tag),
      }))
    end
  end
end

local function card(key, children, extra, whenClosed)
  local closed = folded[key] and not forceOpen[key]
  local top = { ui.button({
    key = "fold-" .. key,
    glyph = closed and "chevron-right" or "chevron-down",
    text = TITLES[key],
    variant = "outline",
    controlSize = "sm",
    contentAlign = "start",
    flexGrow = 1,
    tooltip = closed and "Show the card" or "Fold the card",
    onClick = function() toggleFold(key) end,
  }) }
  if extra and not closed then
    table.insert(top, extra)
  end
  local rows = { ui.row({ gap = 4, align = "center" }, top) }
  if not closed then
    for _, c in ipairs(children) do
      table.insert(rows, c)
    end
  elseif whenClosed then
    for _, c in ipairs(whenClosed) do
      table.insert(rows, c)
    end
  end
  return ui.column({ key = key, fill = "surface_variant", radius = 10, padding = 10, gap = 2, border = "primary", borderWidth = 1 }, rows)
end

local function placeRows()
  local std, marks = {}, {}
  for i, p in ipairs(places) do
    local list = p.std and std or marks
    if p.path and p.ok then
      local tag = p.std and "s" or "b"
      local head = dirRow(p.path, p.name, p.glyph, 0, tag)
      if expanded[p.path] then
        -- The frame is its own node with its own key: retained widgets would keep the border after a fold.
        local group = { head }
        if newIn == p.path and newTag == tag then
          table.insert(group, newFolderRow(p.path, 1, tag))
        end
        childRows(p.path, 1, group, tag)
        table.insert(list, ui.column({ key = "frame" .. tag .. p.path, gap = 2, padding = 4, radius = 8, border = "primary", borderWidth = 1 }, group))
      else
        table.insert(list, head)
      end
    elseif p.open == "trash:///" then
      table.insert(list, ui.row({ key = "trash", gap = 2, align = "center" }, {
        ui.button({
          key = "p" .. i,
          glyph = p.glyph,
          text = trashCount > 0 and (p.name .. "  (" .. trashCount .. ")") or p.name,
          variant = "ghost",
          contentAlign = "start",
          flexGrow = 1,
          tooltip = p.open .. "\nClick: open",
          onClick = function() openFolder(p) end,
        }),
        ui.button({ key = "trashempty", glyph = "trash-x", variant = "ghost", controlSize = "sm", enabled = trashCount > 0, onClick = function()
          trashAsk, trashAt = true, os.time() + 5
          if panel then panel.setWantsSecondTicks(true) end
          render()
        end }),
      }))
      if trashAsk then
        table.insert(list, ui.row({ key = "trashask", gap = 8, align = "center" }, {
          ui.label({ text = "Empty every trash for good? " .. trashCount .. " items on this disk", color = "error", flexGrow = 1 }),
          ui.button({ key = "trashyes", glyph = "trash-x", text = "Empty", variant = "destructive", controlSize = "sm", onClick = emptyTrash }),
          ui.button({ key = "trashno", text = "Cancel", variant = "outline", controlSize = "sm", onClick = function() trashAsk = false; render() end }),
        }))
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
      mounted and ui.button({ key = "dx" .. i, glyph = expanded[d.mount] and "chevron-down" or "chevron-right", variant = "ghost", controlSize = "sm", tooltip = "Show or hide the folders of this drive", onClick = function() toggleDir(d.mount) end }) or ui.box({ key = "dx" .. i, width = 0, height = 0 }),
      ui.button({
        key = "db" .. i,
        selected = hitKey == "d" .. i,
        glyph = d.hot and "device-floppy" or "database",
        text = d.name .. "  " .. d.size,
        variant = "ghost",
        contentAlign = "start",
        flexGrow = 1,
        tooltip = mounted and (d.mount .. "\nClick or right click: open") or (d.dev .. "\nClick or right click: mount and open"),
        onClick = function() openDrive(d) end,
        onRightClick = function() openDrive(d) end,
      }),
      mounted and ui.button({ key = "ej" .. i, glyph = "player-eject", variant = "ghost", controlSize = "sm", tooltip = "Unmount", onClick = function() unmountDrive(d) end }) or ui.box({ key = "ej" .. i, height = 0 }),
    }))
    if mounted and expanded[d.mount] then
      childRows(d.mount, 1, rows, "d")
    end
  end
  return card("drives", rows)
end

local function quickCard()
  loadQProfiles()
  local rows = {}
  if #qProfiles > 0 then
    local chips = {}
    for _, name in ipairs(qProfiles) do
      local on = qActive == name
      table.insert(chips, ui.button({ key = "qp" .. name .. (on and "-on" or ""), text = name, glyph = on and "check" or nil, variant = on and "primary" or "outline", controlSize = "sm",
        onClick = function() toggleQProfile(name) end,
        onRightClick = function()
          qDel, qDelAt = name, os.time() + 5
          if panel then panel.setWantsSecondTicks(true) end
          render()
        end }))
    end
    for i = 1, #chips, 3 do
      table.insert(rows, ui.row({ key = "qpr" .. i, gap = 4 }, { table.unpack(chips, i, math.min(i + 2, #chips)) }))
    end
  end
  if qDel then
    table.insert(rows, ui.row({ key = "qdel", gap = 8, align = "center" }, {
      ui.label({ text = "Delete project " .. qDel .. "?", color = "error", flexGrow = 1 }),
      ui.button({ key = "qdelyes", glyph = "trash", text = "Delete", variant = "destructive", controlSize = "sm", onClick = deleteQProfile }),
      ui.button({ key = "qdelno", text = "Cancel", variant = "outline", controlSize = "sm", onClick = function() qDel = nil; render() end }),
    }))
  end
  if qActive then
    table.insert(rows, ui.label({ text = "Project: " .. qActive, color = "primary", fontSize = 11 }))
  end
  local items = {}
  for i, q in ipairs(quick) do
    local name = string.match(q.path, "([^/]+)/*$") or q.path
    local tag = "q"
    if q.kind == "d" then
      local head = dirRow(q.path, name, "folder", 0, tag)
      if expanded[q.path] then
        local group = { head }
        if newIn == q.path and newTag == tag then
          table.insert(group, newFolderRow(q.path, 1, tag))
        end
        childRows(q.path, 1, group, tag)
        table.insert(items, ui.column({ key = "frame" .. tag .. q.path, gap = 2, padding = 4, radius = 8, border = "primary", borderWidth = 1 }, group))
      else
        table.insert(items, head)
      end
    else
      table.insert(items, ui.row({ key = "f" .. tag .. q.path, gap = 2, align = "center" }, {
        ui.button({
          glyph = "file",
          text = name,
          variant = "ghost",
          contentAlign = "start",
          flexGrow = 1,
          tooltip = q.path .. "\nClick: open, right click: open the folder",
          onClick = function() openFile({ path = q.path }) end,
          onRightClick = function() openFileDir(q.path) end,
        }),
        starButton("f", q.path, tag),
      }))
    end
  end
  if #quick == 0 and qActive then
    table.insert(items, ui.label({ text = "Click the star on a folder or file to keep it here", color = "on_surface_variant", fontSize = 11 }))
  end
  for _, it in ipairs(items) do
    table.insert(rows, it)
  end
  table.insert(rows, ui.row({ gap = 4, align = "center" }, {
    ui.input({ key = "qn" .. qNonce, value = qName, placeholder = "new project name", controlSize = "sm", frameVisible = true, flexGrow = 1,
      onChange = function(t) qName = t end, onSubmit = saveQProfile }),
    ui.button({ key = "qsave", glyph = "device-floppy", text = "New", variant = "outline", controlSize = "sm", onClick = saveQProfile }),
    ui.button({ key = "qclear", glyph = "x", variant = "ghost", controlSize = "sm", enabled = #quick > 0, onClick = function() reloadQuick(); quick = {}; saveQuick(); render() end }),
  }))
  -- Folded, only the active project stays in view: its button and its list.
  local name = qActive
  local whenFolded = nil
  if name then
    whenFolded = { ui.row({ key = "qfold", gap = 4 }, {
      ui.button({ key = "qpf" .. name, text = name, glyph = "check", variant = "primary", controlSize = "sm", onClick = function() toggleQProfile(name) end }),
    }) }
    for _, it in ipairs(items) do
      table.insert(whenFolded, it)
    end
  end
  return card("quick", rows, nil, whenFolded)
end

local function recentCard()
  local sizes = {}
  for _, n in ipairs(SIZES) do
    table.insert(sizes, ui.button({ key = "sz" .. n, text = tostring(n), variant = n == size and "primary" or "ghost", controlSize = "sm", tooltip = "Show " .. n .. " recent files", onClick = function() setSize(n) end }))
  end
  local rows = {}
  for i, f in ipairs(recent) do
    if i > size then
      break
    end
    table.insert(rows, ui.row({ key = "rr" .. i, gap = 2, align = "center" }, {
      ui.button({
        key = "r" .. i,
        glyph = "file",
        text = f.name,
        variant = "ghost",
        contentAlign = "start",
        flexGrow = 1,
        tooltip = f.dir .. "\nClick: open, right click: open the folder",
        onClick = function() openFile(f) end,
        onRightClick = function() openFileDir(f.path or (f.dir .. "/" .. f.name)) end,
      }),
      starButton("f", f.path or (f.dir .. "/" .. f.name), "rc"),
    }))
  end
  if #rows == 0 then
    table.insert(rows, ui.label({ text = "No recent files", color = "on_surface_variant" }))
  end
  return card("recent", rows, ui.row({ gap = 4, align = "center" }, sizes))
end

-- Tree search: every folder below the places is indexed once (python, breadth first, hidden folders left out);
-- a match opens the folders above it and scrolls to its row.
local INDEX = [[import os, sys, time
out = open(sys.argv[1], "w")
t0 = time.monotonic()
seen = set()
queue = []
for r in sys.argv[2:]:
    r = os.path.abspath(r)
    if r not in seen:
        seen.add(r)
        queue.append((r, 0))
n = 0
i = 0
while i < len(queue) and n < 60000 and time.monotonic() - t0 < 8:
    path, d = queue[i]
    i += 1
    out.write(path + "\n")
    n += 1
    if d >= 6:
        continue
    try:
        with os.scandir(path) as it:
            for e in it:
                if e.name.startswith(".") or "\n" in e.name:
                    continue
                c = path + "/" + e.name
                if c not in seen and e.is_dir(follow_symlinks=False):
                    seen.add(c)
                    queue.append((c, d + 1))
    except OSError:
        pass
out.close()]]

-- A script callback gets 25 ms of CPU, so the list never reaches Lua: python writes it to a file and answers each
-- query with at most 300 paths, shallow ones first.
local QUERY = [[import sys
q = sys.argv[2].casefold()
out = []
try:
    with open(sys.argv[1], errors="replace") as f:
        for line in f:
            p = line.rstrip("\n")
            if q in p.rsplit("/", 1)[-1].casefold():
                out.append((p.count("/"), p))
except OSError:
    pass
out.sort()
for _, p in out[:300]:
    print(p)]]

local indexing = false
local jump
local queryGen = 0

local function indexPath()
  return noctalia.pluginDataDir() .. "/dirindex"
end

local function loadIndex()
  indexGen += 1
  local gen = indexGen
  indexing = true
  noctalia.mkdirAll(noctalia.pluginDataDir())
  local args = { "python3", "-I", "-c", INDEX, indexPath() }
  for _, p in ipairs(places) do
    if p.path and p.ok and driveMode ~= 2 then
      table.insert(args, p.path)
    end
  end
  if driveMode > 0 then
    for _, d in ipairs(drives) do
      if d.mount ~= "" then
        table.insert(args, d.mount)
      end
    end
  end
  noctalia.runAsync(args, function()
    if gen ~= indexGen then
      return
    end
    indexing = false
    indexReady = true
    jump()
  end)
end

-- First place row, in screen order, whose folder is the match or lies above it.
local function rowFor(path)
  for _, id in ipairs(order) do
    if id == "drives" and driveMode > 0 and not hidden[id] then
      for i, d in ipairs(drives) do
        if d.mount ~= "" and (path == d.mount or string.sub(path, 1, #d.mount + 1) == d.mount .. "/") then
          return { path = d.mount, key = "d" .. i }, "d", id
        end
      end
    elseif (id == "places" or id == "bookmarks") and driveMode ~= 2 and not hidden[id] then
      for _, p in ipairs(places) do
        if (id == "places") == (p.std == true) and p.path and p.ok and (path == p.path or string.sub(path, 1, #p.path + 1) == p.path .. "/") then
          return p, p.std and "s" or "b", id
        end
      end
    end
  end
end

-- Finds the matches for the typed text, opens the folders above the chosen one and marks its row.
jump = function()
  hitKey, hitCount = nil, 0
  hitList = {}
  forceOpen = {}
  for path in pairs(autoOpened) do
    expanded[path] = nil
  end
  autoOpened = {}
  local q = noctalia.string.trim(treeQuery)
  if q == "" then
    hitPath = nil
    render()
    return
  end
  if not indexReady then
    loadIndex()
    render()
    return
  end
  queryGen += 1
  local gen = queryGen
  noctalia.runAsync({ "python3", "-I", "-c", QUERY, indexPath(), q }, function(r)
    if gen ~= queryGen then
      return
    end
    local hits = {}
    for l in string.gmatch(r.stdout or "", "[^\n]+") do
      if rowFor(l) then
        table.insert(hits, l)
      end
    end
    hitMore = math.max(0, #hits - HIT_ROWS)
    for i = #hits, HIT_ROWS + 1, -1 do
      hits[i] = nil
    end
    hitCount = #hits
    hitList = hits
    hitPath = nil
    if hitCount > 0 then
      local path = hits[((treeIdx - 1) % hitCount) + 1]
      local p, tag, cardId = rowFor(path)
      forceOpen[cardId] = true
      local at = p.path
      while at and at ~= path do
        if not expanded[at] then
          autoOpened[at] = true
        end
        expanded[at] = true
        if not listing[at] then
          listDir(at)
        end
        local nextPart = string.match(string.sub(path, #at + 2), "^([^/]+)")
        at = at .. "/" .. nextPart
      end
      hitPath = path
      hitKey = (tag == "d" and path == p.path) and p.key or ("r" .. tag .. path)
    end
    render()
  end)
end

local function treeSearchRow()
  return ui.row({ gap = 6, align = "center" }, {
    ui.input({
      key = "treeq" .. treeNonce,
      value = treeQuery,
      placeholder = "Jump to a folder in the tree",
      controlSize = "sm",
      flexGrow = 1,
      onChange = function(text)
        treeQuery = text
        treeIdx = 1
        jump()
      end,
      onSubmit = function()
        treeIdx += 1
        jump()
      end,
    }),
    ui.button({ key = "tclear", glyph = "backspace", variant = "ghost", controlSize = "sm", enabled = treeQuery ~= "", onClick = function()
      treeQuery = ""
      treeIdx = 1
      treeNonce += 1
      jump()
    end }),
    ui.button({ key = "tdrv", glyph = DRIVE_MODES[driveMode + 1].glyph, text = pinned and DRIVE_MODES[driveMode + 1].text or nil, variant = driveMode == 0 and "ghost" or "primary", controlSize = "sm", tooltip = DRIVE_MODES[driveMode + 1].tooltip, onClick = function()
      driveMode = (driveMode + 1) % 3
      indexReady = false
      jump()
    end }),
    ui.row({ key = "tcount", tooltip = (treeQuery ~= "" and hitCount > 0) and ("Folder " .. (((treeIdx - 1) % hitCount) + 1) .. " of " .. hitCount .. " found. Enter: next one.") or (indexing and "Reading the folders..." or "Number of folders found. Enter: next one."), align = "center" }, {
      ui.label({ text = (treeQuery ~= "" and indexing) and "..." or (treeQuery ~= "" and hitCount > 0) and (((treeIdx - 1) % hitCount) + 1 .. (pinned and " of " or "/") .. hitCount) or (treeQuery ~= "" and "0" or ""), fontSize = 11, color = "on_surface_variant" }),
    }),
  })
end

-- Every folder the tree search found, under the search field: click one to jump to it in the tree, star it, copy its path.
local function pathLine()
  if #hitList == 0 then
    return nil
  end
  local home = noctalia.getenv("HOME")
  local rows = {}
  for i, path in ipairs(hitList) do
    local shown = path
    if home and string.sub(shown, 1, #home + 1) == home .. "/" then
      shown = "~" .. string.sub(shown, #home + 1)
    end
    table.insert(rows, ui.row({ key = "hit" .. path, gap = 2, align = "center" }, {
      ui.button({
        key = "hitgo" .. path,
        selected = path == hitPath,
        glyph = "folder",
        text = shown,
        variant = "ghost",
        controlSize = "sm",
        contentAlign = "start",
        flexGrow = 1,
        onClick = function()
          treeIdx = i
          jump()
        end,
        onRightClick = function() openFolder({ open = path }) end,
      }),
      starButton("d", path, "h"),
      ui.button({ key = "hitcopy" .. path, glyph = "copy", variant = "ghost", controlSize = "sm", onClick = function() copyPath({ path = path }) end }),
    }))
  end
  if hitMore > 0 then
    table.insert(rows, ui.label({ text = "and " .. hitMore .. " more: type a bit more", fontSize = 11, color = "on_surface_variant" }))
  end
  -- A fixed box around the scroll: the list is long, and the box keeps it from pushing the cards out of the window.
  return ui.column({ key = "hitbox", height = math.min(#rows, 7) * 34 + 4 }, {
    ui.scroll({ key = "hitlist", gap = 2, flexGrow = 1 }, rows),
  })
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
    newIn = nil
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
        pinSide.panelButton("places", "main"),
        ui.button({ glyph = "arrows-left-right", variant = "ghost", controlSize = "sm", tooltip = "Move to the other side", onClick = function() pinSide.swap("places", pinned) end }),
        ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "Close", onClick = function() pinSide.close("places", pinned) end }),
      }),
      searchRow(),
      treeSearchRow(),
      pathLine(),
    }
  else
    head = {
      ui.row({ gap = 8, align = "center" }, {
        logo(),
        ui.label({ text = "Places" }),
        ui.label({ text = hotkey("mabox/places:main"), color = "outline_variant", flexGrow = 1 }),
      }),
      searchRow(),
      treeSearchRow(),
      pathLine(),
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
  reloadQuick()
  local byId = placeRows()
  byId.drives = driveCard()
  byId.recent = recentCard()
  byId.quick = quickCard()
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
  table.insert(head, ui.scroll({ gap = 8, flexGrow = 1, key = "list", revealKey = hitKey }, cards))
  pinSide.render(pinned, ui.column({ gap = 8, padding = 10, flexGrow = 1, height = (not pinned) and 712 or nil }, head))
end

local function open()
  newIn = nil
  editing = false
  treeQuery, treeIdx, hitKey, hitPath, indexReady, forceOpen, autoOpened = "", 1, nil, nil, false, {}, {}
  hitList, hitCount, hitMore = {}, 0, 0
  expanded = {}
  listing = {}
  loadLayout()
  loadSize()
  qDel = nil
  reload()
end

local function tick()
  if qDel and os.time() >= qDelAt then
    qDel = nil
    render()
  end
  if trashAsk and os.time() >= trashAt then
    trashAsk = false
    render()
  end
end

local function close() end

local function key(chord)
  if chord == "escape" then
    panel.close()
  end
end

return open, tick, close, key
end
