--!nonstrict
-- Add a track to the mb-music CSV: URL from the clipboard, title from yt-dlp, category kept between uses.

local csv = require("./lib/csv.luau")

local DIR = noctalia.getenv("HOME") .. "/.config/mabox/mb-music"
local LAST = DIR .. "/last_category"
local NEW = "+ New category"

local cats, catIndex = {}, 1
local url, artist, title, newName, status = "", "", "", "", ""
local nonce, busy, validated = 0, false, nil
local saving, loaded = false, false
local INVALID = "Not a valid stream URL, try again"

local function trim(s)
  return noctalia.string.trim(s or "")
end

local function saveLast(name)
  noctalia.mkdirAll(DIR)
  noctalia.writeFile(LAST, name .. "\n")
end

local render

-- Fills Artist and Title from "Artist - Title"; a new nonce re-seeds the inputs.
-- yt-dlp is the validity check: it fails for a page that is not a playable stream. onValid runs after a good check.
local function fetchTitle(force, onValid)
  if busy then
    return
  end
  if not string.match(url, "^https?://%S+$") then
    status = INVALID
    render()
    return
  end
  busy = true
  status = "Checking the URL..."
  render()
  local checked = url
  noctalia.runAsync({ "yt-dlp", "--no-playlist", "--no-warnings", "--print", "title", url }, function(result)
    busy = false
    if url ~= checked then
      status = ""
      render()
      return
    end
    local t = trim(string.match(result.stdout or "", "[^\r\n]+") or "")
    if result.exitCode ~= 0 or t == "" then
      validated = nil
      status = INVALID
      render()
      return
    end
    validated = checked
    status = ""
    if force == true or (trim(artist) == "" and trim(title) == "") then
      local a, b = string.match(t, "^(.-) %- (.+)$")
      artist, title = a or "", b or t
    end
    nonce = nonce + 1
    render()
    if onValid then
      onValid()
    end
  end)
end

local function add()
  if saving or not loaded then
    return
  end
  local cat = cats[catIndex]
  local name = cat and cat.name or trim(newName)
  if cat == nil then
    for _, c in cats do
      if string.lower(c.name) == string.lower(name) then
        cat, name = c, c.name
      end
    end
  end
  if validated ~= url then
    fetchTitle(false, add)
    return
  elseif trim(title) == "" then
    status = "Title is required"
  elseif name == "" then
    status = "Enter a name for the new category"
  elseif cat and cat.urls[(string.gsub(url, ",", "%%2C"))] then
    status = "Already in " .. name
  else
    local t = string.gsub(trim(title), ",", " ")
    local a = string.gsub(trim(artist), ",", " ")
    local entry = (a ~= "" and a .. " - " or "") .. t .. "," .. (string.gsub(url, ",", "%%2C"))
    saving = true
    csv.add(cat and cat.header or "", name, entry, function(ok, code)
      saving = false
      if ok then
        saveLast(name)
        noctalia.notify("Music", "Added " .. t .. " to " .. name)
        panel.close()
        return
      end
      status = code == 1 and "Category not found, reopen the panel" or "Could not write the playlist"
      render()
    end)
    return
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
  cats, catIndex, saving, loaded = {}, 1, false, false
  local clip = trim(noctalia.clipboardText() or "")
  url = string.match(clip, "^https?://%S+$") and clip or ""
  artist, title, newName, status, validated = "", "", "", "", nil
  nonce = nonce + 1
  render()
  csv.list(function(list)
    if not list then
      status = "Could not read the playlist"
      render()
      return
    end
    cats, loaded = list, true
    local last = trim(noctalia.readFile(LAST) or "")
    catIndex = 1
    for i, c in cats do
      if c.name == last then
        catIndex = i
      end
    end
    render()
  end)
  if url ~= "" then
    fetchTitle()
  end
end
