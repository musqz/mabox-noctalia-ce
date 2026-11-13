--!nonstrict
-- Places: standard folders, file manager bookmarks and recent files; opens folders in pcmanfm.

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
}

local places = {}
local recent = {}
local size = 10
local query = ""
local render

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

local function loadPlaces()
  places = {}
  for _, f in ipairs(FOLDERS) do
    table.insert(places, { name = f.name, glyph = f.glyph, path = f.path, open = f.path, ok = noctalia.fileExists(f.path) })
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
      table.insert(places, { name = label, glyph = "folder", path = path, open = path or uri, ok = path == nil or noctalia.fileExists(path) })
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

local function reload()
  loadPlaces()
  render()
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

local function card(key, children)
  return ui.column({ key = key, fill = "surface_variant", radius = 10, padding = 10, gap = 2, border = "primary", borderWidth = 1 }, children)
end

local function placeRows()
  local rows = {}
  for i, p in ipairs(places) do
    table.insert(rows, ui.button({
      key = "p" .. i,
      glyph = p.glyph,
      text = p.name,
      variant = "ghost",
      contentAlign = "start",
      enabled = p.ok,
      tooltip = p.ok and (p.open .. "\nClick: open, right click: copy the path") or (p.open .. " is not available"),
      onClick = function() openFolder(p) end,
      onRightClick = function() copyPath({ path = p.open }) end,
    }))
  end
  return card("places", rows)
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
      key = "search",
      focus = not pinned,
      value = query,
      placeholder = "FSearch",
      controlSize = "sm",
      flexGrow = 1,
      onChange = function(text) query = text end,
      onSubmit = function() fsearch(query) end,
    }),
    ui.button({ glyph = "search", variant = "ghost", controlSize = "sm", tooltip = "Open FSearch (Enter: search for the typed text)", onClick = function() fsearch(query) end }),
  })
end

render = function()
  local head
  if pinned then
    head = {
      ui.row({ gap = 8, align = "center" }, {
        logo(),
        ui.label({ text = "Places" }),
        ui.label({ text = hotkey("mb-pinned places"), color = "outline_variant", flexGrow = 1 }),
      }),
      ui.row({ gap = 6, align = "center" }, {
        ui.button({ glyph = "refresh", variant = "ghost", controlSize = "sm", tooltip = "Reload", onClick = reload }),
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
      ui.spacer({ flexGrow = 1 }),
      ui.button({ glyph = "refresh", variant = "ghost", controlSize = "sm", tooltip = "Reload", onClick = reload }),
      ui.button({ glyph = "pin", variant = "ghost", controlSize = "sm", tooltip = "Pin window", onClick = function()
        panel.close()
        pinSide.toggle("places")
      end }),
      ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "Close", onClick = function() panel.close() end }),
    }))
  end
  table.insert(head, ui.scroll({ gap = 8, flexGrow = 1, key = "list" }, { placeRows(), recentCard() }))
  pinSide.render(pinned, ui.column({ gap = 8, padding = 10, flexGrow = 1, height = (not pinned) and 632 or nil }, head))
end

local function open()
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
