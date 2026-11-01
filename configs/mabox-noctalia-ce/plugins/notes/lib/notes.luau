--!nonstrict
-- Notes and favorites. One .md file per note and one .fav file per favorite entry, so a synced folder rarely conflicts.
-- A favorite is a starred note or an entry (title + one-line value: URL, path or text).
-- Folder: <plugin data dir>/notes, or the path written in <plugin data dir>/path.

return function(pinned)
local TABS = { "Notes", "Favorites" }

local tab = "Notes"
local query = ""
local searchNonce = 0
local formNonce = 0
local newTitle = ""
local newValue = ""
local notes = {}
local favorites = {}
local current = nil
local expanded = {}
local selecting = false
local selected = {}
local confirming = false
local armedDelete = nil
local armedFresh = false
local NOTES = nil
local render

local function root()
  local dir = noctalia.pluginDataDir()
  if not dir then
    return nil
  end
  local raw = noctalia.readFile(dir .. "/path")
  raw = raw and noctalia.string.trim(raw) or ""
  if raw ~= "" then
    return (string.gsub(raw, "/+$", ""))
  end
  return dir .. "/notes"
end

local function uniqueName(dir, ext)
  while true do
    local name = noctalia.formatTime("%Y%m%d-%H%M%S") .. "-" .. math.random(1000, 9999) .. ext
    if not noctalia.fileExists(dir .. "/" .. name) then
      return name
    end
  end
end

local function prettyDate(name)
  local y, mo, d, h, mi = string.match(name, "^(%d%d%d%d)(%d%d)(%d%d)%-(%d%d)(%d%d)")
  return y and `{y}-{mo}-{d} {h}:{mi}` or ""
end

-- Monotonic in time and small enough for repeated midpoints; notes without "order:" sort by it.
local function stampKey(name)
  local y, mo, d, h, mi, sec = string.match(name, "^(%d%d%d%d)(%d%d)(%d%d)%-(%d%d)(%d%d)(%d%d)")
  if not y then
    return 0
  end
  return ((tonumber(y) - 2000) * 372 + (tonumber(mo) - 1) * 31 + tonumber(d) - 1) * 86400 + tonumber(h) * 3600 + tonumber(mi) * 60 + tonumber(sec)
end

local function matches(hay, q)
  hay = string.lower(hay)
  for term in string.gmatch(string.lower(q), "%S+") do
    if not string.find(hay, term, 1, true) then
      return false
    end
  end
  return true
end

local function hashtags(tags)
  local out = {}
  for w in string.gmatch(tags, "[^%s#]+") do
    table.insert(out, "#" .. w)
  end
  return table.concat(out, " ")
end

local function noteHay(n)
  return n.body .. " " .. hashtags(n.tags) .. " " .. prettyDate(n.id)
end

-- Header lines "tags:", "favorite:" and "order:" end at the first other line; a blank line there is the separator.
local function parseNote(raw)
  raw = string.gsub(raw, "\r\n", "\n")
  local note = { tags = "", favorite = false }
  local pos = 1
  while pos <= #raw do
    local nl = string.find(raw, "\n", pos, true)
    local line = string.sub(raw, pos, (nl or #raw + 1) - 1)
    local key, value = string.match(line, "^(%a+):%s*(.*)$")
    if key == "tags" then
      note.tags = value
    elseif key == "order" then
      note.order = tonumber(value)
    elseif key == "favorite" then
      note.favorite = value == "yes"
    else
      if line == "" and nl then
        pos = nl + 1
      end
      break
    end
    pos = (nl or #raw) + 1
  end
  note.body = string.sub(raw, pos)
  return note
end

local function titleOf(body)
  for line in string.gmatch(body, "[^\r\n]+") do
    local t = noctalia.string.trim((string.gsub(line, "^[#%s]+", "")))
    if t ~= "" then
      return t
    end
  end
  return "(empty)"
end

local function saveNote(n)
  local head = "tags: " .. string.gsub(n.tags, "[\r\n]", " ") .. "\nfavorite: " .. (n.favorite and "yes" or "no") .. "\n"
  if n.order then
    head = head .. string.format("order: %.6f\n", n.order)
  end
  head = head .. "\n"
  noctalia.mkdirAll(NOTES)
  noctalia.writeFile(NOTES .. "/" .. n.id, head .. n.body)
end

local function loadNotes()
  notes = {}
  local entries = noctalia.listDir(NOTES)
  for _, name in ipairs(entries or {}) do
    if string.match(name, "%.md$") then
      local raw = noctalia.readFile(NOTES .. "/" .. name)
      if raw then
        local n = parseNote(raw)
        n.id = name
        n.key = n.order or stampKey(name)
        n.title = titleOf(n.body)
        table.insert(notes, n)
      end
    end
  end
  table.sort(notes, function(a, b)
    if a.key ~= b.key then
      return a.key > b.key
    end
    return a.id > b.id
  end)
end

local function favoriteDir()
  return NOTES .. "/favorites"
end

local function loadFavorites()
  favorites = {}
  local entries = noctalia.listDir(favoriteDir())
  for _, name in ipairs(entries or {}) do
    if string.match(name, "%.fav$") then
      local raw = noctalia.readFile(favoriteDir() .. "/" .. name)
      if raw then
        local f = { id = name, title = "", value = "" }
        for line in string.gmatch(raw, "[^\r\n]+") do
          local key, value = string.match(line, "^(%a+):%s*(.*)$")
          if key == "title" or key == "value" then
            f[key] = value
          end
        end
        if f.value ~= "" then
          if f.title == "" then
            f.title = f.value
          end
          table.insert(favorites, f)
        end
      end
    end
  end
  table.sort(favorites, function(a, b) return a.id > b.id end)
end

local function reload()
  loadNotes()
  loadFavorites()
  render()
end

local function createNote()
  noctalia.mkdirAll(NOTES)
  current = { id = uniqueName(NOTES, ".md"), tags = "", favorite = false, body = "", fresh = true }
  saveNote(current)
  render()
end

-- Leaves the editor; an untouched new note is not kept.
local function finishEdit()
  if current and current.fresh and noctalia.string.trim(current.body) == "" and noctalia.string.trim(current.tags) == "" then
    noctalia.removeFile(NOTES .. "/" .. current.id)
  end
  current = nil
  loadNotes()
end

local function removeNote(id)
  noctalia.removeFile(NOTES .. "/" .. id)
  expanded[id] = nil
  selected[id] = nil
end

local function deleteNote()
  removeNote(current.id)
  current = nil
  loadNotes()
  render()
end

local function copyNote(n)
  noctalia.copyToClipboard(n.body, "text/plain")
  noctalia.notify("Note copied", n.title)
end

-- Only http(s) URLs are launched; anything else is copied.
local function openEntry(f)
  if string.match(f.value, "^https?://%S+$") then
    noctalia.runAsync({ "xdg-open", f.value })
  else
    noctalia.copyToClipboard(f.value, "text/plain")
    noctalia.notify("Copied", f.title)
  end
end

local function addEntry(value, title)
  value = noctalia.string.trim((string.gsub(value, "[\r\n]+", " ")))
  if value == "" then
    noctalia.notify("Notes", "Enter a value")
    return
  end
  title = noctalia.string.trim((string.gsub(title, "[\r\n]", " ")))
  if title == "" then
    title = string.match(value, "^%a[%w+.-]*://([^/]+)") or value
  end
  noctalia.mkdirAll(favoriteDir())
  noctalia.writeFile(favoriteDir() .. "/" .. uniqueName(favoriteDir(), ".fav"), `title: {title}\nvalue: {value}\n`)
  newTitle = ""
  newValue = ""
  formNonce += 1
  loadFavorites()
  render()
end

local function addFromClipboard()
  local text = noctalia.clipboardText()
  text = text and noctalia.string.trim(text) or ""
  if text == "" or string.find(text, "[\r\n]") then
    noctalia.notify("Notes", "Clipboard needs one line of text")
    return
  end
  addEntry(text, newTitle)
end

local function deleteEntry(f)
  noctalia.removeFile(favoriteDir() .. "/" .. f.id)
  loadFavorites()
  render()
end

local function setTab(name)
  finishEdit()
  selecting = false
  selected = {}
  confirming = false
  tab = name
  query = ""
  searchNonce += 1
  render()
end

-- Persistent panels cannot host ui.select, so the pinned window cycles with < > buttons.
local function tabChooser()
  local index = tab == "Notes" and 1 or 2
  local function step()
    setTab(TABS[index % #TABS + 1])
  end
  return ui.row({ key = "tabs", gap = 4, align = "center" }, {
    ui.button({ glyph = "chevron-left", variant = "ghost", controlSize = "sm", onClick = step }),
    ui.label({ text = tab, flexGrow = 1, textAlign = "center" }),
    ui.button({ glyph = "chevron-right", variant = "ghost", controlSize = "sm", onClick = step }),
  })
end

local function listRow(key, glyph, title, detail, onClick, actions)
  local cells = {
    ui.glyph({ name = glyph, size = 18, color = "on_surface_variant" }),
    ui.column({ gap = 1, flexGrow = 1 }, {
      ui.label({ text = title, maxLines = 1 }),
      ui.label({ text = detail, fontSize = 11, color = "on_surface_variant", maxLines = 1 }),
    }),
  }
  for _, a in ipairs(actions or {}) do
    table.insert(cells, a)
  end
  return ui.row({ key = key, gap = 8, padding = 8, radius = 6, fill = "surface_container", align = "center", onClick = onClick }, cells)
end

local function indexOf(list, id)
  for i, n in ipairs(list) do
    if n.id == id then
      return i
    end
  end
end

-- Moves the note to the slot before list[pos]; only that note's file changes.
local function placeNote(list, id, pos)
  local from = indexOf(list, id)
  if not from or pos == from or pos == from + 1 then
    return
  end
  local n = table.remove(list, from)
  if pos > from then
    pos -= 1
  end
  local above, below = list[pos - 1], list[pos]
  local key
  if above and below then
    key = (above.key + below.key) / 2
  elseif below then
    key = below.key + 1
  elseif above then
    key = above.key - 1
  end
  if key then
    n.order = key
    n.key = key
    saveNote(n)
  end
  table.insert(list, pos, n)
end

-- dir: "up", "down", "top" or "bottom"; every note in ids moves as a block.
local function moveNotes(ids, dir)
  local list = notes
  local order = {}
  for _, n in ipairs(list) do
    if ids[n.id] then
      table.insert(order, n.id)
    end
  end
  if dir == "up" then
    for _, id in ipairs(order) do
      local i = indexOf(list, id)
      if i > 1 and not ids[list[i - 1].id] then
        placeNote(list, id, i - 1)
      end
    end
  elseif dir == "down" then
    for k = #order, 1, -1 do
      local i = indexOf(list, order[k])
      if i < #list and not ids[list[i + 1].id] then
        placeNote(list, order[k], i + 2)
      end
    end
  elseif dir == "top" then
    for k = #order, 1, -1 do
      placeNote(list, order[k], 1)
    end
  else
    for _, id in ipairs(order) do
      placeNote(list, id, #list + 1)
    end
  end
  loadNotes()
  render()
end

-- Click the title to show or hide the full text; right click or the copy button copies it.
local function noteItem(key, n, detail)
  local open = expanded[n.id]
  local head = {}
  if selecting then
    table.insert(head, ui.button({ key = "s" .. key, glyph = selected[n.id] and "square-check" or "square", variant = "ghost", controlSize = "sm", tooltip = "Select", onClick = function()
      selected[n.id] = not selected[n.id] or nil
      confirming = false
      render()
    end }))
  end
  local buttons = {
    ui.button({
      key = "m" .. key,
      glyph = open and "chevron-down" or (n.favorite and "bookmark" or "note"),
      text = n.title,
      variant = "ghost",
      contentAlign = "start",
      flexGrow = 1,
      tooltip = "Click: show text, right click: copy",
      onClick = function()
        expanded[n.id] = not open or nil
        render()
      end,
      onRightClick = function() copyNote(n) end,
    }),
    ui.button({ glyph = "copy", variant = "ghost", controlSize = "sm", tooltip = "Copy", onClick = function() copyNote(n) end }),
  }
  for _, b in ipairs(buttons) do
    table.insert(head, b)
  end
  if not selecting and query == "" then
    table.insert(head, ui.button({ glyph = "arrow-up", variant = "ghost", controlSize = "sm", tooltip = "Move up", onClick = function() moveNotes({ [n.id] = true }, "up") end }))
    table.insert(head, ui.button({ glyph = "arrow-down", variant = "ghost", controlSize = "sm", tooltip = "Move down", onClick = function() moveNotes({ [n.id] = true }, "down") end }))
  end
  local items = {
    ui.row({ gap = 4, align = "center" }, head),
    ui.label({ text = detail, fontSize = 11, color = "on_surface_variant", maxLines = 1 }),
  }
  if open then
    -- One text area that scrolls itself; the row estimate only sizes it, wrapping is the host's.
    local cols = pinned and 30 or 80
    local rows = 0
    for line in string.gmatch(n.body .. "\n", "([^\n]*)\n") do
      rows += math.max(1, math.ceil(#line / cols))
    end
    local height = math.min(pinned and 420 or 260, math.max(80, rows * 20 + 16))
    table.insert(items, ui.column({ fill = "surface", radius = 4, padding = 6 }, {
      ui.input({ key = "x" .. n.id, value = n.body, multiline = true, frameVisible = false, height = height, onChange = function(text)
        if not pinned then
          n.body = text
          saveNote(n)
        end
      end }),
    }))
    if not pinned and not selecting then
      local armed = armedDelete == n.id
      table.insert(items, ui.row({ gap = 6, align = "center" }, {
        ui.spacer({ flexGrow = 1 }),
        ui.button({ glyph = "pencil", text = "Edit", variant = "ghost", controlSize = "sm", onClick = function()
          current = n
          render()
        end }),
        ui.button({ glyph = "trash", text = armed and "Click again to delete" or "Delete", variant = armed and "destructive" or "ghost", controlSize = "sm", onClick = function()
          if armed then
            removeNote(n.id)
            loadNotes()
          else
            armedDelete = n.id
            armedFresh = true
          end
          render()
        end }),
      }))
    end
  end
  return ui.column({ key = key, gap = 4, padding = 8, radius = 6, fill = "surface_container" }, items)
end

local function noteRows()
  local rows = {}
  local list = {}
  for _, n in ipairs(notes) do
    if matches(noteHay(n), query) then
      table.insert(list, n)
    end
  end
  for _, n in ipairs(list) do
    local detail = prettyDate(n.id)
    if n.tags ~= "" then
      detail = detail .. "  " .. hashtags(n.tags)
    end
    table.insert(rows, noteItem("n" .. n.id, n, detail))
    table.insert(rows, ui.spacer({ height = 6 }))
  end
  if #list == 0 then
    table.insert(rows, ui.label({ text = "No notes", color = "on_surface_variant" }))
  end
  return rows
end

local function favoriteRows()
  local rows = {}
  local list = {}
  for _, n in ipairs(notes) do
    if n.favorite and matches(noteHay(n), query) then
      table.insert(list, n)
    end
  end
  for _, n in ipairs(list) do
    table.insert(rows, noteItem("fn" .. n.id, n, prettyDate(n.id)))
    table.insert(rows, ui.spacer({ height = 6 }))
  end
  for _, f in ipairs(favorites) do
    if matches(f.title .. " " .. f.value .. " " .. prettyDate(f.id), query) then
      local actions = nil
      if not pinned then
        actions = { ui.button({ glyph = "trash", variant = "ghost", controlSize = "sm", tooltip = "Remove", onClick = function() deleteEntry(f) end }) }
      end
      table.insert(rows, listRow("f" .. f.id, "star", f.title, f.value, function() openEntry(f) end, actions))
      table.insert(rows, ui.spacer({ height = 6 }))
    end
  end
  if #rows == 0 then
    table.insert(rows, ui.label({ text = "No favorites", color = "on_surface_variant" }))
  end
  return rows
end

local function searchBox()
  return ui.input({
    key = "search" .. tab .. searchNonce,
    value = query,
    placeholder = "search words, #tag or date",
    controlSize = "sm",
    onChange = function(text)
      query = text
      selected = {}
      confirming = false
      render()
    end,
  })
end

local function editor()
  local n = current
  return ui.column({ gap = 8, flexGrow = 1 }, {
    ui.row({ gap = 6, align = "center" }, {
      ui.button({ glyph = "arrow-left", text = "Back", variant = "ghost", controlSize = "sm", onClick = function()
        finishEdit()
        render()
      end }),
      ui.label({ text = prettyDate(n.id), color = "on_surface_variant" }),
      ui.spacer({ flexGrow = 1 }),
      ui.button({ glyph = "bookmark", text = n.favorite and "Unfavorite" or "Favorite", variant = n.favorite and "primary" or "ghost", controlSize = "sm", onClick = function()
        n.favorite = not n.favorite
        saveNote(n)
        render()
      end }),
      ui.button({ glyph = "copy", text = "Copy", variant = "ghost", controlSize = "sm", onClick = function() copyNote({ body = n.body, title = titleOf(n.body) }) end }),
      ui.button({ glyph = "trash", text = "Delete", variant = "ghost", controlSize = "sm", onClick = deleteNote }),
    }),
    ui.input({ key = "tags" .. n.id, value = n.tags, placeholder = "tags, space separated", controlSize = "sm", onChange = function(text)
      n.tags = text
      saveNote(n)
    end }),
    ui.input({ key = "body" .. n.id, value = n.body, placeholder = "Write a note", multiline = true, focus = true, flexGrow = 1, onChange = function(text)
      n.body = text
      saveNote(n)
    end }),
  })
end

local function favoriteForm()
  return ui.row({ gap = 6, align = "center" }, {
    ui.input({ key = "favtitle" .. formNonce, value = newTitle, placeholder = "title (optional)", controlSize = "sm", width = 180, onChange = function(text) newTitle = text end }),
    ui.input({ key = "favvalue" .. formNonce, value = newValue, placeholder = "URL, path or text", controlSize = "sm", flexGrow = 1, onChange = function(text) newValue = text end, onSubmit = function() addEntry(newValue, newTitle) end }),
    ui.button({ glyph = "plus", text = "Add", variant = "primary", controlSize = "sm", onClick = function() addEntry(newValue, newTitle) end }),
    ui.button({ glyph = "clipboard", text = "Clipboard", variant = "ghost", controlSize = "sm", tooltip = "Add the clipboard text", onClick = addFromClipboard }),
  })
end

local function countSelected()
  local count = 0
  for _ in pairs(selected) do
    count += 1
  end
  return count
end

local function deleteSelected()
  for id in pairs(selected) do
    removeNote(id)
  end
  selected = {}
  confirming = false
  selecting = false
  loadNotes()
  render()
end

local function selectBar()
  local count = countSelected()
  return ui.row({ gap = 6, align = "center" }, {
    ui.button({ text = "All", variant = "ghost", controlSize = "sm", onClick = function()
      for _, n in ipairs(notes) do
        if matches(noteHay(n), query) then
          selected[n.id] = true
        end
      end
      confirming = false
      render()
    end }),
    ui.button({ text = "None", variant = "ghost", controlSize = "sm", onClick = function()
      selected = {}
      confirming = false
      render()
    end }),
    ui.spacer({ flexGrow = 1 }),
    ui.button({ glyph = "arrow-bar-up", variant = "ghost", controlSize = "sm", tooltip = "Move to top", enabled = count > 0 and query == "", onClick = function() moveNotes(selected, "top") end }),
    ui.button({ glyph = "arrow-up", variant = "ghost", controlSize = "sm", tooltip = "Move up", enabled = count > 0 and query == "", onClick = function() moveNotes(selected, "up") end }),
    ui.button({ glyph = "arrow-down", variant = "ghost", controlSize = "sm", tooltip = "Move down", enabled = count > 0 and query == "", onClick = function() moveNotes(selected, "down") end }),
    ui.button({ glyph = "arrow-bar-down", variant = "ghost", controlSize = "sm", tooltip = "Move to bottom", enabled = count > 0 and query == "", onClick = function() moveNotes(selected, "bottom") end }),
    ui.button({
      glyph = "trash",
      text = confirming and `Confirm delete ({count})` or `Delete ({count})`,
      variant = "destructive",
      controlSize = "sm",
      enabled = count > 0,
      onClick = function()
        if confirming then
          deleteSelected()
        else
          confirming = true
          render()
        end
      end,
    }),
  })
end

local function openMain(context)
  noctalia.runAsync({ "noctalia", "msg", "panel-open", "musqz/notes:main", context or "list" })
end

-- Changes made in the dropdown reach the pinned window by polling file times.
local function signature()
  local parts = {}
  for _, dir in ipairs({ NOTES, favoriteDir() }) do
    for _, name in ipairs(noctalia.listDir(dir) or {}) do
      local info = noctalia.fileInfo(dir .. "/" .. name)
      table.insert(parts, name .. (info and info.mtime or 0))
    end
  end
  return table.concat(parts, "|")
end

render = function()
  if armedFresh then
    armedFresh = false
  else
    armedDelete = nil
  end
  if pinned then
    local rows = tab == "Notes" and noteRows() or favoriteRows()
    panel.render(ui.column({ gap = 8, padding = 10, flexGrow = 1 }, {
      ui.row({ gap = 6, align = "center" }, {
        ui.button({ glyph = "plus", text = "New", variant = "primary", controlSize = "sm", tooltip = "New note in the notes window", onClick = function() openMain("new") end }),
        ui.button({ glyph = "notes", variant = "ghost", controlSize = "sm", tooltip = "Open the notes window", onClick = function() openMain() end }),
        ui.button({ glyph = "refresh", variant = "ghost", controlSize = "sm", tooltip = "Reload", onClick = reload }),
        ui.spacer({ flexGrow = 1 }),
        ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = "Close", onClick = function() panel.close() end }),
      }),
      tabChooser(),
      ui.scroll({ gap = 0, flexGrow = 1, key = "list" .. tab }, rows),
    }))
    return
  end

  local side = {}
  for _, name in ipairs(TABS) do
    table.insert(side, ui.button({
      key = "t" .. name,
      text = name,
      variant = name == tab and "primary" or "ghost",
      contentAlign = "start",
      onClick = function() setTab(name) end,
    }))
  end
  if tab == "Notes" then
    table.insert(side, ui.separator({ spacing = 4 }))
    table.insert(side, ui.button({ text = "New note", glyph = "plus", variant = "ghost", contentAlign = "start", onClick = createNote }))
    table.insert(side, ui.button({ text = "Select", glyph = "square-check", variant = selecting and "primary" or "ghost", contentAlign = "start", onClick = function()
      selecting = not selecting
      selected = {}
      confirming = false
      render()
    end }))
  end
  table.insert(side, ui.spacer({ flexGrow = 1 }))
  table.insert(side, ui.button({ text = "Pin window", glyph = "pin", variant = "ghost", contentAlign = "start", onClick = function()
    finishEdit()
    panel.close()
    noctalia.runAsync({ "noctalia", "msg", "panel-toggle", "musqz/notes:pinned" })
  end }))

  local right
  if current then
    right = { editor() }
  elseif tab == "Notes" then
    right = { searchBox() }
    if selecting then
      table.insert(right, selectBar())
    end
    table.insert(right, ui.scroll({ gap = 0, flexGrow = 1, key = "list" .. tab }, noteRows()))
  else
    right = { searchBox(), ui.scroll({ gap = 0, flexGrow = 1, key = "list" .. tab }, favoriteRows()), favoriteForm() }
  end

  panel.render(ui.column({ gap = 10, padding = 12, height = 520 }, {
    ui.row({ gap = 12, flexGrow = 1 }, {
      ui.column({ gap = 4, width = 160 }, side),
      ui.column({ gap = 8, flexGrow = 1 }, right),
    }),
  }))
end

local lastSignature = ""
local ticks = 0

local function open(context)
  NOTES = root()
  if not NOTES then
    noctalia.notify("Notes", "No plugin data directory")
    return
  end
  tab = "Notes"
  query = ""
  searchNonce += 1
  current = nil
  selecting = false
  selected = {}
  confirming = false
  armedDelete = nil
  armedFresh = false
  reload()
  lastSignature = signature()
  if context == "new" and not pinned then
    createNote()
  end
end

local function tick()
  ticks += 1
  if NOTES and ticks % 2 == 0 then
    local sig = signature()
    if sig ~= lastSignature then
      lastSignature = sig
      reload()
    end
  end
end

return open, tick, finishEdit
end
