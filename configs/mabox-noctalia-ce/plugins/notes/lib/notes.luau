--!nonstrict
-- Notes: one .md file per note, so a synced folder rarely conflicts.
-- Folder: <plugin data dir>/notes, or the path written in <plugin data dir>/path.

return function(pinned)
local COLORS = {
  { name = "red", hex = "#e5534b" },
  { name = "orange", hex = "#f0883e" },
  { name = "yellow", hex = "#d4a72c" },
  { name = "green", hex = "#57ab5a" },
  { name = "teal", hex = "#2ea89a" },
  { name = "cyan", hex = "#39b5c7" },
  { name = "blue", hex = "#539bf5" },
  { name = "purple", hex = "#986ee2" },
  { name = "pink", hex = "#e275ad" },
}
local COLOR_HEX = {}
for _, c in ipairs(COLORS) do
  COLOR_HEX[c.name] = c.hex
end

local query = ""
local searchNonce = 0
local notes = {}
local colorFilter = {}
local cursorId = nil
local dotCursor = 0
local zone = "list"
local focusSearch = false
local editField = "body"
local editNonce = 0
local editHead = 1
local topCursor = 1
local sideCursor = 1
local current = nil
local expanded = {}
local selecting = false
local selected = {}
local confirming = false
local armedDelete = nil
local lastSnapshot = {}
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

local function isFiltered()
  return query ~= "" or next(colorFilter) ~= nil
end

-- Ticked colors narrow the list to those colors; none ticked shows every note.
local function visible(n)
  if next(colorFilter) ~= nil and not (n.color and colorFilter[n.color]) then
    return false
  end
  return matches(noteHay(n), query)
end

-- Header lines "tags:", "color:" and "order:" (a legacy "favorite:" line is skipped) end at the first other line; a blank line there is the separator.
local function parseNote(raw)
  raw = string.gsub(raw, "\r\n", "\n")
  local note = { tags = "" }
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
      -- legacy line, dropped on the next save
    elseif key == "color" then
      note.color = COLOR_HEX[value] and value or nil
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
  local head = "tags: " .. string.gsub(n.tags, "[\r\n]", " ") .. "\n"
  if n.color then
    head = head .. "color: " .. n.color .. "\n"
  end
  if n.order then
    head = head .. string.format("order: %.6f\n", n.order)
  end
  head = head .. "\n"
  noctalia.mkdirAll(NOTES)
  noctalia.writeFile(NOTES .. "/" .. n.id, head .. n.body)
  local info = noctalia.fileInfo(NOTES .. "/" .. n.id)
  if info then
    lastSnapshot[NOTES .. "/" .. n.id] = info.mtime
  end
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

local function reload()
  loadNotes()
  render()
end

local function createNote()
  -- A new note has no color, so an active filter or search would hide it again.
  colorFilter = {}
  query = ""
  searchNonce += 1
  noctalia.mkdirAll(NOTES)
  current = { id = uniqueName(NOTES, ".md"), tags = "", body = "", fresh = true }
  saveNote(current)
  render()
end

-- Leaves the editor; an untouched new note is not kept.
local function finishEdit()
  if current and current.fresh and noctalia.string.trim(current.body) == "" and noctalia.string.trim(current.tags) == "" then
    noctalia.removeFile(NOTES .. "/" .. current.id)
    lastSnapshot[NOTES .. "/" .. current.id] = nil
  end
  current = nil
  editField = "body"
  editHead = 1
  focusSearch = false
  loadNotes()
end

local function removeNote(id)
  noctalia.removeFile(NOTES .. "/" .. id)
  lastSnapshot[NOTES .. "/" .. id] = nil
  expanded[id] = nil
  selected[id] = nil
end

local function deleteNote()
  removeNote(current.id)
  current = nil
  editField = "body"
  editHead = 1
  focusSearch = false
  loadNotes()
  render()
end

local function copyNote(n)
  noctalia.copyToClipboard(n.body, "text/plain")
  noctalia.notify("Note copied", n.title)
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
  if n.color then
    table.insert(head, ui.box({ width = 5, height = 22, radius = 2, fill = COLOR_HEX[n.color], tooltip = n.color }))
  end
  local buttons = {
    ui.button({
      key = "m" .. key,
      glyph = open and "chevron-down" or "note",
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
  if not selecting and not isFiltered() then
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
      local cells = {}
      for _, c in ipairs(COLORS) do
        local on = n.color == c.name
        local dot = { key = "c" .. key .. c.name, width = 18, height = 18, radius = 9, fill = c.hex, border = "on_surface", borderWidth = on and 2 or 0, tooltip = on and ("Clear " .. c.name) or c.name, onClick = function()
          n.color = (not on) and c.name or nil
          saveNote(n)
          render()
        end }
        table.insert(cells, ui.box(dot))
      end
      table.insert(cells, ui.spacer({ flexGrow = 1 }))
      table.insert(cells, ui.button({ glyph = "pencil", text = "Edit", variant = "ghost", controlSize = "sm", onClick = function()
        current = n
        render()
      end }))
      table.insert(cells, ui.button({ glyph = "trash", text = armed and "Click again to delete" or "Delete", variant = armed and "destructive" or "ghost", controlSize = "sm", onClick = function()
        if armed then
          removeNote(n.id)
          loadNotes()
        else
          armedDelete = n.id
          armedFresh = true
        end
        render()
      end }))
      table.insert(items, ui.row({ gap = 6, align = "center" }, cells))
    end
  end
  local onCursor = zone == "list" and cursorId == n.id
  return ui.column({ key = key, gap = 4, padding = 8, radius = 6, fill = "surface_container", border = "primary", borderWidth = onCursor and 2 or 0 }, items)
end

local function noteRows()
  local rows = {}
  local list = {}
  for _, n in ipairs(notes) do
    if visible(n) then
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

-- Only colors in use (or ticked, so they can be unticked) get a dot.
local function dotColors()
  local used = {}
  for _, n in ipairs(notes) do
    if n.color then
      used[n.color] = true
    end
  end
  local out = {}
  for _, c in ipairs(COLORS) do
    if used[c.name] or colorFilter[c.name] then
      table.insert(out, c)
    end
  end
  return out
end

local function toggleColor(name)
  colorFilter[name] = not colorFilter[name] or nil
  selected = {}
  confirming = false
  render()
end

local function colorBar()
  local dots = dotColors()
  if #dots == 0 then
    return nil
  end
  local any = next(colorFilter) ~= nil
  local cells = {}
  for i, c in ipairs(dots) do
    local on = colorFilter[c.name]
    local ring = zone == "dots" and i == dotCursor
    local size = ring and 24 or 18
    local dot = { key = "cf" .. c.name, width = size, height = size, radius = size // 2, fill = c.hex, border = "on_surface", borderWidth = ring and 3 or (on and 2 or 0), opacity = (on or not any) and 1 or 0.4, tooltip = on and ("Untick " .. c.name) or ("Show only " .. c.name), onClick = function() toggleColor(c.name) end }
    table.insert(cells, ui.column({ gap = 3, align = "center" }, {
      ui.box(dot),
      ui.box({ key = "cu" .. c.name, width = 14, height = 2, radius = 1, fill = "on_surface", opacity = on and 1 or 0 }),
    }))
  end
  return ui.row({ gap = 8, align = "center" }, cells)
end

local function searchBox()
  return ui.input({
    key = "search" .. searchNonce,
    focus = focusSearch,
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
      ui.button({ glyph = "arrow-left", text = "Back", variant = "ghost", controlSize = "sm", selected = editField == "head" and editHead == 1, onClick = function()
        finishEdit()
        render()
      end }),
      ui.label({ text = prettyDate(n.id), color = "on_surface_variant" }),
      ui.spacer({ flexGrow = 1 }),
      ui.button({ glyph = "copy", text = "Copy", variant = "ghost", controlSize = "sm", selected = editField == "head" and editHead == 2, onClick = function() copyNote({ body = n.body, title = titleOf(n.body) }) end }),
      ui.button({ glyph = "trash", text = "Delete", variant = "ghost", controlSize = "sm", selected = editField == "head" and editHead == 3, onClick = deleteNote }),
    }),
    ui.input({ key = "tags" .. n.id .. editNonce, focus = editField == "tags", value = n.tags, placeholder = "tags, space separated", controlSize = "sm", onChange = function(text)
      n.tags = text
      saveNote(n)
    end }),
    ui.input({ key = "body" .. n.id .. editNonce, value = n.body, placeholder = "Write a note", multiline = true, focus = editField == "body", flexGrow = 1, onChange = function(text)
      n.body = text
      saveNote(n)
    end }),
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
        if visible(n) then
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
    ui.button({ glyph = "arrow-bar-up", variant = "ghost", controlSize = "sm", tooltip = "Move to top", enabled = count > 0 and not isFiltered(), onClick = function() moveNotes(selected, "top") end }),
    ui.button({ glyph = "arrow-up", variant = "ghost", controlSize = "sm", tooltip = "Move up", enabled = count > 0 and not isFiltered(), onClick = function() moveNotes(selected, "up") end }),
    ui.button({ glyph = "arrow-down", variant = "ghost", controlSize = "sm", tooltip = "Move down", enabled = count > 0 and not isFiltered(), onClick = function() moveNotes(selected, "down") end }),
    ui.button({ glyph = "arrow-bar-down", variant = "ghost", controlSize = "sm", tooltip = "Move to bottom", enabled = count > 0 and not isFiltered(), onClick = function() moveNotes(selected, "bottom") end }),
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
  noctalia.runAsync({ "noctalia", "msg", "panel-open", "mabox/notes:main", context or "list" })
end

-- File times of all notes; the two windows notice each other's writes by comparing them.
local function snapshot()
  local map = {}
  for _, name in ipairs(noctalia.listDir(NOTES) or {}) do
    local info = noctalia.fileInfo(NOTES .. "/" .. name)
    map[NOTES .. "/" .. name] = info and info.mtime or 0
  end
  return map
end

local function sameSnapshot(a, b)
  for k, v in pairs(a) do
    if b[k] ~= v then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end

local function toggleSelect()
  selecting = not selecting
  selected = {}
  confirming = false
  render()
end

local function pinWindow()
  finishEdit()
  panel.close()
  noctalia.runAsync({ "noctalia", "msg", "panel-toggle", "mabox/notes:pinned" })
end

render = function()
  if armedFresh then
    armedFresh = false
  else
    armedDelete = nil
  end
  if pinned then
    local children = {
      ui.row({ gap = 6, align = "center" }, {
        ui.button({ glyph = "plus", text = "New", variant = "ghost", controlSize = "sm", selected = zone == "top" and topCursor == 1, tooltip = "New note in the notes window", onClick = function() openMain("new") end }),
        ui.button({ glyph = "notes", variant = "ghost", controlSize = "sm", selected = zone == "top" and topCursor == 2, tooltip = "Open the notes window", onClick = function() openMain() end }),
        ui.button({ glyph = "refresh", variant = "ghost", controlSize = "sm", selected = zone == "top" and topCursor == 3, tooltip = "Reload", onClick = reload }),
        ui.spacer({ flexGrow = 1 }),
        ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", selected = zone == "top" and topCursor == 4, tooltip = "Close", onClick = function() panel.close() end }),
      }),
    }
    local bar = colorBar()
    if bar then
      table.insert(children, bar)
    end
    table.insert(children, ui.scroll({ gap = 0, flexGrow = 1, key = "list", revealKey = cursorId and ("n" .. cursorId) or nil }, noteRows()))
    panel.render(ui.column({ gap = 8, padding = 10, flexGrow = 1 }, children))
    return
  end

  local function onSide(i) return zone == "side" and sideCursor == i end
  local side = {}
  table.insert(side, ui.button({ text = "New note", glyph = "plus", variant = "ghost", contentAlign = "start", selected = onSide(1), onClick = createNote }))
  table.insert(side, ui.button({ text = "Select", glyph = "square-check", variant = selecting and "primary" or "ghost", contentAlign = "start", selected = onSide(2), onClick = toggleSelect }))
  table.insert(side, ui.spacer({ flexGrow = 1 }))
  table.insert(side, ui.button({ text = "Reload", glyph = "refresh", variant = "ghost", contentAlign = "start", selected = onSide(3), tooltip = "Re-read notes from disk", onClick = reload }))
  table.insert(side, ui.button({ text = "Pin window", glyph = "pin", variant = "ghost", contentAlign = "start", selected = onSide(4), onClick = pinWindow }))

  local right
  if current then
    right = { editor() }
  else
    right = { searchBox() }
    local bar = colorBar()
    if bar then
      table.insert(right, bar)
    end
    if selecting then
      table.insert(right, selectBar())
    end
    table.insert(right, ui.scroll({ gap = 0, flexGrow = 1, key = "list", revealKey = cursorId and ("n" .. cursorId) or nil }, noteRows()))
  end

  panel.render(ui.column({ gap = 10, padding = 12, height = 520 }, {
    ui.row({ gap = 12, flexGrow = 1 }, {
      ui.column({ gap = 4, width = 160 }, side),
      ui.column({ gap = 8, flexGrow = 1 }, right),
    }),
  }))
end

local ticks = 0

local function open(context)
  NOTES = root()
  if not NOTES then
    noctalia.notify("Notes", "No plugin data directory")
    return
  end
  query = ""
  searchNonce += 1
  focusSearch = false
  current = nil
  selecting = false
  selected = {}
  confirming = false
  colorFilter = {}
  cursorId = nil
  dotCursor = 0
  zone = "list"
  armedDelete = nil
  armedFresh = false
  reload()
  lastSnapshot = snapshot()
  if context == "new" and not pinned then
    createNote()
  end
end

local function tick()
  ticks += 1
  -- An open editor is not redrawn under the user; Back reloads the list.
  if NOTES and not current and ticks % 2 == 0 then
    local snap = snapshot()
    if not sameSnapshot(snap, lastSnapshot) then
      lastSnapshot = snap
      reload()
    end
  end
end

-- Alt chords only: plain arrows and letters belong to the text boxes.
local function onKey(chord)
  if current then
    local rows = { "head", "tags", "body" }
    local at = 3
    for i, r in ipairs(rows) do
      if r == editField then
        at = i
      end
    end
    if chord == "alt+s" then
      editField = editField == "body" and "tags" or "body"
      editNonce += 1
    elseif chord == "alt+up" or chord == "alt+down" then
      local to = rows[math.max(1, math.min(3, at + (chord == "alt+down" and 1 or -1)))]
      if to == editField then
        return
      end
      editField = to
      if to ~= "head" then
        editNonce += 1
      end
    elseif (chord == "alt+left" or chord == "alt+right") and editField == "head" then
      editHead = (editHead - 1 + (chord == "alt+right" and 1 or -1)) % 3 + 1
    elseif chord == "alt+enter" and editField == "head" then
      if editHead == 1 then
        finishEdit()
      elseif editHead == 2 then
        copyNote({ body = current.body, title = titleOf(current.body) })
        return
      else
        deleteNote()
        return
      end
    else
      return
    end
    render()
    return
  end
  local list = {}
  for _, n in ipairs(notes) do
    if visible(n) then
      table.insert(list, n)
    end
  end
  local dots = #dotColors()
  local step = (chord == "alt+down" or chord == "alt+right") and 1 or -1
  if chord == "alt+up" or chord == "alt+down" then
    local idx = 0
    for i, n in ipairs(list) do
      if n.id == cursorId then
        idx = i
      end
    end
    if zone == "side" then
      sideCursor = math.max(1, math.min(4, sideCursor + step))
    elseif zone == "list" and (step == 1 or idx > 1) then
      idx = idx == 0 and (step == 1 and 1 or #list) or math.max(1, math.min(#list, idx + step))
      cursorId = list[idx] and list[idx].id or nil
    elseif step == -1 then
      if zone == "list" and dots > 0 then
        zone = "dots"
        dotCursor = math.max(1, math.min(dots, dotCursor))
      elseif pinned then
        zone = "top"
      end
    elseif zone == "top" then
      zone = dots > 0 and "dots" or "list"
      if zone == "list" then
        cursorId = cursorId or (list[1] and list[1].id)
      end
    elseif zone == "dots" then
      zone = "list"
      cursorId = cursorId or (list[1] and list[1].id)
    end
  elseif chord == "alt+left" or chord == "alt+right" then
    if zone == "top" then
      topCursor = (topCursor - 1 + step) % 4 + 1
    elseif zone == "side" then
      if step == -1 then
        return
      end
      zone = "list"
      cursorId = cursorId or (list[1] and list[1].id)
    elseif not pinned and (zone == "list" or (zone == "dots" and step == -1 and dotCursor <= 1)) then
      if step == 1 then
        return
      end
      zone = "side"
    elseif dots > 0 then
      zone = "dots"
      if dotCursor < 1 or dotCursor > dots then
        dotCursor = step == 1 and 1 or dots
      else
        dotCursor = (dotCursor - 1 + step) % dots + 1
      end
    else
      return
    end
  elseif chord == "alt+s" then
    if pinned then
      return
    end
    searchNonce += 1
    focusSearch = true
  elseif chord == "alt+enter" then
    if zone == "top" then
      local actions = { function() openMain("new") end, function() openMain() end, reload, function() panel.close() end }
      actions[topCursor]()
      return
    elseif zone == "side" then
      local actions = { createNote, toggleSelect, reload, pinWindow }
      actions[sideCursor]()
      return
    elseif zone == "dots" then
      local c = dotColors()[dotCursor]
      if c then
        toggleColor(c.name)
      end
      return
    end
    if cursorId then
      expanded[cursorId] = not expanded[cursorId] or nil
    end
  elseif chord == "alt+c" or chord == "alt+e" then
    for _, n in ipairs(list) do
      if zone == "list" and n.id == cursorId then
        if chord == "alt+c" then
          copyNote(n)
        elseif not pinned then
          current = n
        end
      end
    end
  else
    return
  end
  render()
end

return open, tick, finishEdit, onKey
end
