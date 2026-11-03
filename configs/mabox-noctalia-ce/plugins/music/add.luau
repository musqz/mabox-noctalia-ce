--!nonstrict
-- Add a track to the mb-music CSV: URL from the clipboard, title from yt-dlp, category kept between uses.

local DIR = noctalia.getenv("HOME") .. "/.config/mabox/mb-music"
local CSV = DIR .. "/yt_music_list.csv"
local LAST = DIR .. "/last_category"
local NEW = "+ New category"

local cats, catIndex = {}, 1
local url, artist, title, newName, status = "", "", "", "", ""
local nonce, busy = 0, false

local function trim(s)
  return noctalia.string.trim(s or "")
end

local function loadCategories()
  cats = {}
  local cur
  for line in string.gmatch(noctalia.readFile(CSV) or "", "[^\r\n]+") do
    local name, u = string.match(line, "^(.*),([^,]*)$")
    if name then
      u = trim(u)
      if u == "-" then
        name = trim((string.gsub(name, "^[^%w]+", "")))
        if string.upper(name) == "END" then
          cur = nil
        else
          cur = { name = name, header = line, urls = {} }
          table.insert(cats, cur)
        end
      elseif cur then
        cur.urls[u] = true
      end
    end
  end
end

local function csvLines()
  local lines = {}
  for l in string.gmatch((noctalia.readFile(CSV) or "") .. "\n", "(.-)\n") do
    table.insert(lines, l)
  end
  if lines[#lines] == "" then
    table.remove(lines)
  end
  return lines
end

-- Entry goes after the last track of the category; a new category is appended at the end.
local function insert(cat, name, entry)
  local lines = csvLines()
  if cat == nil then
    table.insert(lines, "\u{F0EA2} " .. name .. ",-")
    table.insert(lines, entry)
  else
    local first, stop = nil, #lines + 1
    for i, l in lines do
      if first == nil then
        if l == cat.header then
          first = i
        end
      elseif string.sub(l, -2) == ",-" then
        stop = i
        break
      end
    end
    if first == nil then
      return false
    end
    local at = stop
    while at - 1 > first and lines[at - 1] == "" do
      at = at - 1
    end
    table.insert(lines, at, entry)
  end
  noctalia.mkdirAll(DIR)
  noctalia.writeFile(CSV, table.concat(lines, "\n") .. "\n")
  return true
end

local function saveLast(name)
  noctalia.mkdirAll(DIR)
  noctalia.writeFile(LAST, name .. "\n")
end

local render

-- Fills Artist and Title from "Artist - Title"; a new nonce re-seeds the inputs.
local function fetchTitle(force)
  if not string.match(url, "^https?://%S+$") or busy then
    return
  end
  busy = true
  status = "Fetching title..."
  render()
  noctalia.runAsync({ "yt-dlp", "--no-playlist", "--no-warnings", "--print", "title", url }, function(result)
    busy = false
    status = ""
    local t = trim(string.match(result.stdout or "", "[^\r\n]+") or "")
    if t ~= "" and (force == true or (trim(artist) == "" and trim(title) == "")) then
      local a, b = string.match(t, "^(.-) %- (.+)$")
      artist, title = a or "", b or t
    end
    nonce = nonce + 1
    render()
  end)
end

local function add()
  local cat = cats[catIndex]
  local name = cat and cat.name or trim(newName)
  if cat == nil then
    for _, c in cats do
      if string.lower(c.name) == string.lower(name) then
        cat, name = c, c.name
      end
    end
  end
  if not string.match(url, "^https?://%S+$") then
    status = "Enter an http(s) URL"
  elseif trim(title) == "" then
    status = "Title is required"
  elseif name == "" then
    status = "Enter a name for the new category"
  elseif cat and cat.urls[string.gsub(url, ",", "%%2C")] then
    status = "Already in " .. name
  else
    local t = string.gsub(trim(title), ",", " ")
    local a = string.gsub(trim(artist), ",", " ")
    if insert(cat, name, (a ~= "" and a .. " - " or "") .. t .. "," .. string.gsub(url, ",", "%%2C")) then
      saveLast(name)
      noctalia.notify("Music", "Added " .. t .. " to " .. name)
      panel.close()
      return
    end
    status = "Could not write the playlist"
  end
  render()
end

local function field(key, value, placeholder, onChange, focus)
  return ui.input({
    key = key .. nonce,
    value = value,
    placeholder = placeholder,
    focus = focus,
    submitOnEnter = true,
    onChange = onChange,
    onSubmit = function(text)
      onChange(text)
      add()
    end,
  })
end

render = function()
  local names = {}
  for _, c in cats do
    table.insert(names, c.name)
  end
  table.insert(names, NEW)
  local body = {
    ui.label({ text = "Add track", fontSize = 16 }),
    ui.row({ gap = 6, align = "center" }, {
      ui.input({
        key = "url" .. nonce,
        value = url,
        placeholder = "URL",
        focus = url == "",
        flexGrow = 1,
        onChange = function(text)
          url = trim(text)
        end,
        onSubmit = function(text)
          url = trim(text)
          fetchTitle(true)
        end,
      }),
      ui.button({ glyph = "refresh", variant = "ghost", tooltip = "Fetch title and artist", onClick = function() fetchTitle(true) end }),
    }),
    field("artist", artist, "Artist", function(text) artist = text end, false),
    field("title", title, "Title", function(text) title = text end, url ~= ""),
    ui.select({
      key = "cat",
      options = names,
      selectedIndex = catIndex - 1,
      onChange = function(idx)
        catIndex = tonumber(idx) + 1
        if cats[catIndex] then
          saveLast(cats[catIndex].name)
        end
        render()
      end,
    }),
  }
  if cats[catIndex] == nil then
    table.insert(body, field("newcat", newName, "New category name", function(text) newName = text end, true))
  end
  if status ~= "" then
    table.insert(body, ui.label({ text = status, color = "error" }))
  end
  table.insert(body, ui.row({ gap = 6 }, {
    ui.spacer({ flexGrow = 1 }),
    ui.button({ text = "Cancel", variant = "ghost", onClick = function() panel.close() end }),
    ui.button({ text = "Add", variant = "primary", glyph = "plus", onClick = add }),
  }))
  panel.render(ui.column({ gap = 8, padding = 12 }, body))
end

function onOpen()
  loadCategories()
  local last = trim(noctalia.readFile(LAST) or "")
  catIndex = #cats + 1
  for i, c in cats do
    if c.name == last then
      catIndex = i
    end
  end
  if #cats > 0 and catIndex > #cats then
    catIndex = 1
  end
  local clip = trim(noctalia.clipboardText() or "")
  url = string.match(clip, "^https?://%S+$") and clip or ""
  artist, title, newName, status = "", "", "", ""
  nonce = nonce + 1
  render()
  fetchTitle()
end
