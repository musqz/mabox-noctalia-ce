--!nonstrict
-- Todo: todo.txt lists in ~/.todo; done tasks stay struck through in the list until moved to done_<list>.txt.

return function()
local DIR = noctalia.getenv("HOME") .. "/.todo"

local lists = {}
local list = "todo"
local hideDone = false
local sortMode = "date"
local sortDesc = false
local addOpen = true
local archiveView = false
local tasks = {}
local doneTasks = {}
local addText = ""
local addPri = nil
local addDue = nil
local filterText = ""
local filterTag = nil
local naming = false
local newName = ""
local renaming = false
local renameText = ""
local confirming = nil
local editing = nil
local editText, editPri, editDue = "", nil, ""
local addGroup = ""
local editGroup = ""
local addNote = ""
local editNote = ""
local savedGroups = {}
local newGroup = ""
local nonce = 0
local noteOpen = {}
local calFor = nil
local calYear, calMonth = 0, 0
local render

local function statePath()
  return noctalia.pluginDataDir() .. "/state"
end

local function loadState()
  local raw = "\n" .. (noctalia.readFile(statePath()) or "")
  list = string.match(raw, "\nlist=([%w_%-%.]+)") or "todo"
  hideDone = string.match(raw, "\nhide_done=1") ~= nil
  sortMode = string.match(raw, "\nsort=(%a+)") or "date"
  sortDesc = string.match(raw, "\ndesc=1") ~= nil
  addOpen = string.match(raw, "\nadd_open=0") == nil
  savedGroups = {}
  for g in string.gmatch(string.match(raw, "\ngroups=([^\n]*)") or "", "[^,]+") do
    table.insert(savedGroups, g)
  end
end

local function saveState()
  noctalia.mkdirAll(noctalia.pluginDataDir())
  noctalia.writeFile(statePath(), "list=" .. list .. "\nhide_done=" .. (hideDone and "1" or "0") .. "\nsort=" .. sortMode .. "\ngroups=" .. table.concat(savedGroups, ",") .. "\ndesc=" .. (sortDesc and "1" or "0") .. "\nadd_open=" .. (addOpen and "1" or "0") .. "\n")
end

-- Groups are +tags; a group made without a task is kept in the state file so it can be picked later.
local function createGroup(name)
  local g = string.gsub(noctalia.string.trim(name or ""), "[^%w_%-]", "_")
  if g == "" then
    return ""
  end
  for _, x in ipairs(savedGroups) do
    if x == g then
      return g
    end
  end
  table.insert(savedGroups, g)
  table.sort(savedGroups)
  saveState()
  return g
end

local function removeSavedGroup(name)
  for i, x in ipairs(savedGroups) do
    if x == name then
      table.remove(savedGroups, i)
    end
  end
  saveState()
end

local function listPath(name)
  return DIR .. "/" .. name .. ".txt"
end

local function donePath(name)
  return DIR .. "/done_" .. name .. ".txt"
end

local function readLines(path)
  local out = {}
  for l in string.gmatch(noctalia.readFile(path) or "", "[^\n]+") do
    if string.match(l, "%S") then
      table.insert(out, l)
    end
  end
  return out
end

local function writeLines(path, lines)
  noctalia.mkdirAll(DIR)
  noctalia.writeFile(path, table.concat(lines, "\n") .. (#lines > 0 and "\n" or ""))
end

local DUE_HEX = { overdue = "#e5534b", today = "#f0883e", tomorrow = "#539bf5", week = "#57ab5a", later = "#986ee2", nodate = "#888888" }
local PRI_NAME = { A = "High", B = "Medium", C = "Low" }
local DATE = "%d%d%d%d%-%d%d%-%d%d"

-- The explanation lives on the same line as note:..., spaces and other characters percent-encoded.
local function encodeNote(text)
  return (string.gsub(text, "[^%w_%.,%-]", function(c) return string.format("%%%02X", string.byte(c)) end))
end

local function decodeNote(text)
  return (string.gsub(text, "%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function parse(raw)
  local t = { raw = raw }
  local rest = raw
  local isDone = string.match(rest, "^x ")
  if isDone then
    rest = string.sub(rest, 3)
  end
  t.pri = string.match(rest, "^%((%u)%) ")
  if t.pri then
    rest = string.sub(rest, 5)
  end
  local date = string.match(rest, "^(" .. DATE .. ") ")
  if date then
    rest = string.sub(rest, #date + 2)
    if isDone then
      t.doneDate = date
      t.created = string.match(rest, "^(" .. DATE .. ") ")
      if t.created then
        rest = string.sub(rest, #t.created + 2)
      end
    else
      t.created = date
    end
  end
  t.due = string.match(rest, "%f[%S]due:(" .. DATE .. ")%f[%s%z]")
  rest = string.gsub(rest, "%f[%S]due:" .. DATE .. "%f[%s%z]", "")
  t.color = string.match(rest, "%f[%S]color:(%a+)%f[%s%z]")
  rest = string.gsub(rest, "%f[%S]color:%a+%f[%s%z]", "")
  local note = string.match(rest, "%f[%S]note:(%S+)")
  t.note = note and decodeNote(note) or nil
  rest = string.gsub(rest, "%f[%S]note:%S+", "")
  t.pinned = string.match(rest, "%f[%S]pin:1%f[%s%z]") ~= nil
  rest = string.gsub(rest, "%f[%S]pin:1%f[%s%z]", "")
  t.tags = {}
  for tag in string.gmatch(rest, "%f[%S][+@]%S+") do
    table.insert(t.tags, tag)
  end
  t.text = noctalia.string.trim((string.gsub(rest, "%f[%S][+@]%S+", "")))
  t.done = isDone ~= nil
  return t
end

local function build(t)
  local parts = {}
  if t.pri then
    table.insert(parts, "(" .. t.pri .. ")")
  end
  if t.created then
    table.insert(parts, t.created)
  end
  table.insert(parts, t.text)
  for _, tag in ipairs(t.tags or {}) do
    table.insert(parts, tag)
  end
  if t.pinned then
    table.insert(parts, "pin:1")
  end
  if t.note and t.note ~= "" then
    table.insert(parts, "note:" .. encodeNote(t.note))
  end
  if t.color then
    table.insert(parts, "color:" .. t.color)
  end
  if t.due then
    table.insert(parts, "due:" .. t.due)
  end
  return table.concat(parts, " ")
end

local function addDays(n)
  return os.date("%Y-%m-%d", os.time() + n * 86400)
end

local function load()
  lists = {}
  for _, name in ipairs(noctalia.listDir(DIR) or {}) do
    local base = string.match(name, "^(.+)%.txt$")
    if base and not string.match(base, "^done_") and not string.match(base, "^report_") and base ~= "done" and base ~= "report" then
      table.insert(lists, base)
    end
  end
  table.sort(lists)
  local found = false
  for _, n in ipairs(lists) do
    found = found or n == list
  end
  if not found then
    list = lists[1] or "todo"
    if #lists == 0 then
      lists = { list }
    end
  end
  tasks, doneTasks = {}, {}
  for _, l in ipairs(readLines(listPath(list))) do
    local t = parse(l)
    t.path = listPath(list)
    -- "x ..." lines stay in the list, struck through, until archived or deleted
    table.insert(tasks, t)
  end
  for _, l in ipairs(readLines(donePath(list))) do
    local t = parse(l)
    t.path = donePath(list)
    table.insert(doneTasks, t)
  end
  for i, t in ipairs(tasks) do
    t.order = i
  end
end

local function reload()
  load()
  render()
end

-- Re-reads the file so edits made elsewhere (todo.sh) are kept; the task is found by its text.
local function mutate(path, raw, fn)
  local lines = readLines(path)
  for i, l in ipairs(lines) do
    if l == raw then
      fn(lines, i)
      writeLines(path, lines)
      return true
    end
  end
  return false
end

local function today()
  return os.date("%Y-%m-%d")
end

-- Dates are stored as YYYY-MM-DD; the panel shows and accepts them in the order of the user's locale
-- (`locale d_fmt`: dd-mm-yyyy, mm/dd/yyyy, ...). The ISO form is always accepted too.
local dateOrder, dateSep = { "y", "m", "d" }, "-"
local dateFormatLoaded = false

local function setDateFormat(fmt)
  local order = {}
  for c in string.gmatch(fmt or "", "%%([YymdeE])") do
    table.insert(order, (string.lower(c) == "e") and "d" or string.lower(c))
  end
  local sep = string.match(fmt or "", "%%%a(%p)%%")
  if #order == 3 and sep and sep ~= "%" then
    dateOrder, dateSep = order, sep
  end
end

local function fmtDate(iso)
  local y, m, d = string.match(iso or "", "^(%d+)%-(%d+)%-(%d+)$")
  if not y then
    return iso or ""
  end
  local v = { y = y, m = m, d = d }
  return table.concat({ v[dateOrder[1]], v[dateOrder[2]], v[dateOrder[3]] }, dateSep)
end

local function datePlaceholder()
  local name = { y = "YYYY", m = "MM", d = "DD" }
  return table.concat({ name[dateOrder[1]], name[dateOrder[2]], name[dateOrder[3]] }, dateSep)
end

-- Accepts the ISO form (2026-11-5 too) and the locale order (5-11-2026); rejects days that do not exist.
local function normDate(s)
  local text = noctalia.string.trim(s or "")
  local y, m, d = string.match(text, "^(%d%d%d%d)%-(%d%d?)%-(%d%d?)$")
  if not y then
    local a, b, c = string.match(text, "^(%d%d?%d?%d?)[%-/%.](%d%d?)[%-/%.](%d%d?%d?%d?)$")
    if not a then
      return nil
    end
    if #a == 4 then
      y, m, d = a, b, c
    else
      local v = {}
      v[dateOrder[1]], v[dateOrder[2]], v[dateOrder[3]] = a, b, c
      y, m, d = v.y, v.m, v.d
    end
    if #y ~= 4 then
      return nil
    end
  end
  local out = string.format("%04d-%02d-%02d", tonumber(y), tonumber(m), tonumber(d))
  local check = os.date("%Y-%m-%d", os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }))
  return check == out and out or nil
end

local function shownDate(raw)
  local iso = normDate(raw)
  return iso and fmtDate(iso) or raw or ""
end

local function dueNote(s)
  if noctalia.string.trim(s or "") == "" then
    return nil, false
  end
  local date = normDate(s)
  if not date then
    return "use " .. datePlaceholder(), true
  end
  local function noon(x)
    local y, m, d = string.match(x, "^(%d+)%-(%d+)%-(%d+)$")
    return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
  end
  local n = math.floor((noon(date) - noon(today())) / 86400 + 0.5)
  if n < 0 then
    return "Overdue, " .. (-n) .. (n == -1 and " day ago" or " days ago"), false
  elseif n == 0 then
    return "Today", false
  elseif n == 1 then
    return "Tomorrow", false
  end
  return "in " .. n .. " days", false
end

local function addTask(text, pri, due, note)
  text = noctalia.string.trim(text)
  if text == "" then
    return
  end
  local t = parse(text)
  t.pri = pri or t.pri
  t.due = normDate(due) or t.due
  note = noctalia.string.trim(note or "")
  t.note = note ~= "" and note or nil
  t.created = today()
  local lines = readLines(listPath(list))
  table.insert(lines, build(t))
  writeLines(listPath(list), lines)
end

local function complete(t)
  mutate(listPath(list), t.raw, function(lines, i)
    local copy = parse(lines[i])
    copy.pri = nil
    lines[i] = "x " .. today() .. " " .. build(copy)
  end)
  reload()
end

local function reopen(t)
  if t.path == listPath(list) then
    mutate(t.path, t.raw, function(lines, i)
      lines[i] = string.gsub(string.gsub(lines[i], "^x " .. DATE .. " ", "", 1), "^x ", "", 1)
    end)
  else
    local found = mutate(t.path, t.raw, function(lines, i)
      table.remove(lines, i)
    end)
    if found then
      local open = readLines(listPath(list))
      table.insert(open, (string.gsub(string.gsub(t.raw, "^x " .. DATE .. " ", "", 1), "^x ", "", 1)))
      writeLines(listPath(list), open)
    end
  end
  reload()
end

local function archiveDone()
  local kept, moved = {}, {}
  for _, l in ipairs(readLines(listPath(list))) do
    table.insert(parse(l).done and moved or kept, l)
  end
  if #moved > 0 then
    local archive = readLines(donePath(list))
    for _, l in ipairs(moved) do
      table.insert(archive, l)
    end
    writeLines(donePath(list), archive)
    writeLines(listPath(list), kept)
  end
  reload()
end

local function togglePin(t)
  mutate(listPath(list), t.raw, function(lines, i)
    local p = parse(lines[i])
    p.pinned = not p.pinned
    lines[i] = build(p)
  end)
  reload()
end

local function cyclePriority(t)
  local nextPri = t.pri == nil and "A" or ({ A = "B", B = "C" })[t.pri]
  mutate(listPath(list), t.raw, function(lines, i)
    local p = parse(lines[i])
    p.pri = nextPri
    lines[i] = build(p)
  end)
  reload()
end

local function saveEdit(t)
  local p = parse(noctalia.string.trim(editText))
  if p.text == "" and #p.tags == 0 then
    return
  end
  if noctalia.string.trim(editDue) ~= "" and not normDate(editDue) then
    render()
    return
  end
  p.pri = editPri
  p.created = t.created
  p.pinned = t.pinned
  p.due = normDate(editDue)
  p.note = noctalia.string.trim(editNote) ~= "" and noctalia.string.trim(editNote) or nil
  mutate(listPath(list), t.raw, function(lines, i)
    lines[i] = build(p)
  end)
  editing = nil
  reload()
end

local function deleteTask(t)
  mutate(t.path, t.raw, function(lines, i)
    table.remove(lines, i)
  end)
  reload()
end

local function clearDone()
  local kept = {}
  for _, l in ipairs(readLines(listPath(list))) do
    if not parse(l).done then
      table.insert(kept, l)
    end
  end
  writeLines(listPath(list), kept)
  noctalia.removeFile(donePath(list))
  reload()
end

local function newList(name)
  name = string.gsub(noctalia.string.trim(name), "[^%w_%-%.]", "_")
  if name == "" or name == "done" or name == "report" or string.match(name, "^done_") or string.match(name, "^report_") then
    return
  end
  if not noctalia.fileExists(listPath(name)) then
    writeLines(listPath(name), {})
  end
  list = name
  saveState()
end

local function renameList(name)
  name = string.gsub(noctalia.string.trim(name), "[^%w_%-%.]", "_")
  if name == "" or name == list or name == "done" or name == "report" or string.match(name, "^done_") or string.match(name, "^report_") or noctalia.fileExists(listPath(name)) or noctalia.fileExists(donePath(name)) then
    return false
  end
  writeLines(listPath(name), readLines(listPath(list)))
  noctalia.removeFile(listPath(list))
  if noctalia.fileExists(donePath(list)) then
    writeLines(donePath(name), readLines(donePath(list)))
    noctalia.removeFile(donePath(list))
  end
  list = name
  saveState()
  return true
end

local function removeList()
  noctalia.removeFile(listPath(list))
  noctalia.removeFile(donePath(list))
  list = "todo"
  saveState()
  reload()
end

local function matches(t)
  if filterTag then
    local has = false
    for _, tag in ipairs(t.tags) do
      has = has or tag == filterTag
    end
    if not has then
      return false
    end
  end
  local q = string.lower(noctalia.string.trim(filterText))
  if q == "" then
    return true
  end
  local hay = string.lower(t.raw)
  for word in string.gmatch(q, "%S+") do
    if not string.find(hay, word, 1, true) then
      return false
    end
  end
  return true
end

local function groupOf(t)
  for _, tag in ipairs(t.tags) do
    if string.sub(tag, 1, 1) == "+" then
      return string.sub(tag, 2)
    end
  end
  return nil
end

local function projectNames()
  local seen, names = {}, {}
  for _, t in ipairs(tasks) do
    local g = not t.done and groupOf(t) or nil
    if g and not seen[g] then
      seen[g] = true
      table.insert(names, g)
    end
  end
  for _, g in ipairs(savedGroups) do
    if not seen[g] then
      seen[g] = true
      table.insert(names, g)
    end
  end
  table.sort(names)
  return names
end

local function dueKind(due)
  local day = today()
  if not due then
    return nil
  elseif due < day then
    return "overdue"
  elseif due == day then
    return "today"
  elseif due == addDays(1) then
    return "tomorrow"
  end
  if due <= addDays(7) then
    return "week"
  end
  return "later"
end

local function dot(color)
  return ui.box({ width = 10, height = 10, radius = 5, fill = color })
end

local function colorChip(color, ch)
  return ui.row({ gap = 3, align = "center" }, { dot(color), ch })
end

local function chip(key, text, on, tooltip, fn)
  return ui.button({ key = key, text = text, variant = on and "primary" or "outline", controlSize = "sm", tooltip = tooltip, onClick = fn })
end

local function iconButton(glyph, tooltip, fn, on)
  return ui.button({ glyph = glyph, variant = on and "primary" or "ghost", controlSize = "sm", tooltip = tooltip, onClick = fn })
end

local function startEdit(t)
  calFor = nil
  if editing == t.raw then
    editing = nil
  else
    editing = t.raw
    editText = t.text
    for _, tag in ipairs(t.tags) do
      editText = editText .. " " .. tag
    end
    editPri = t.pri
    editDue = t.due or ""
    editNote = t.note or ""
    editGroup = ""
  end
  confirming = nil
  render()
end

local MONTHS = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" }

local function openCalendar(who, current)
  if calFor == who then
    calFor = nil
  else
    calFor = who
    local y, m = string.match(normDate(current) or today(), "^(%d+)%-(%d+)")
    calYear, calMonth = tonumber(y), tonumber(m)
  end
  render()
end

local function shiftMonth(d)
  local idx = calYear * 12 + (calMonth - 1) + d
  calYear, calMonth = idx // 12, idx % 12 + 1
  render()
end

local function calendarGrid(selected, onPick)
  local first = os.date("*t", os.time({ year = calYear, month = calMonth, day = 1, hour = 12 }))
  local offset = (first.wday + 5) % 7
  local days = os.date("*t", os.time({ year = calYear, month = calMonth + 1, day = 0, hour = 12 })).day
  local day = today()
  local rows = {
    ui.row({ gap = 4, align = "center" }, {
      iconButton("chevrons-left", "Previous year", function() shiftMonth(-12) end),
      iconButton("chevron-left", "Previous month", function() shiftMonth(-1) end),
      ui.label({ text = MONTHS[calMonth] .. " " .. calYear, color = "on_surface", flexGrow = 1 }),
      iconButton("chevron-right", "Next month", function() shiftMonth(1) end),
      iconButton("chevrons-right", "Next year", function() shiftMonth(12) end),
    }),
  }
  local head = {}
  for _, d in ipairs({ "Mo", "Tu", "We", "Th", "Fr", "Sa", "Su" }) do
    table.insert(head, ui.label({ text = d, color = "on_surface_variant", flexGrow = 1 }))
  end
  table.insert(rows, ui.row({ gap = 4 }, head))
  local n = 1 - offset
  for w = 1, 6 do
    if n > days then
      break
    end
    local cells = {}
    for c = 1, 7 do
      if n < 1 or n > days then
        table.insert(cells, ui.spacer({ flexGrow = 1 }))
      else
        local date = string.format("%04d-%02d-%02d", calYear, calMonth, n)
        table.insert(cells, ui.button({
          key = "c" .. date,
          text = tostring(n),
          variant = date == selected and "primary" or "ghost",
          controlSize = "sm",
          flexGrow = 1,
          tooltip = date == day and "Today" or date,
          onClick = function() onPick(date) end,
        }))
      end
      n = n + 1
    end
    table.insert(rows, ui.row({ gap = 4 }, cells))
  end
  return ui.column({ gap = 4, padding = 8, fill = "surface", radius = 8 }, rows)
end

local function editRow(t, key)
  local pris = {}
  for _, p in ipairs({ "A", "B", "C" }) do
    table.insert(pris, chip("ep" .. p, PRI_NAME[p], editPri == p, "Priority " .. p, function()
      editPri = p
      render()
    end))
  end
  table.insert(pris, chip("ep-", "None", editPri == nil, "No priority", function()
    editPri = nil
    render()
  end))
  local dues = {}
  for _, d in ipairs({ { "Today", 0 }, { "Tomorrow", 1 }, { "Next week", 7 } }) do
    table.insert(dues, colorChip(DUE_HEX[dueKind(addDays(d[2]))], chip("ed" .. d[1], d[1], editDue == addDays(d[2]), "Due " .. fmtDate(addDays(d[2])), function()
      editDue = addDays(d[2])
      render()
    end)))
  end
  table.insert(dues, ui.button({ key = "edcal", glyph = "calendar", text = "Pick date", variant = calFor == "edit" and "primary" or "ghost", controlSize = "sm", tooltip = "Choose a day in a calendar", onClick = function() openCalendar("edit", editDue) end }))
  table.insert(dues, chip("edclear", "Clear", false, "Remove the due date", function()
    editDue = ""
    render()
  end))
  local groupsRow = { ui.label({ text = "Group", color = "on_surface_variant" }) }
  for _, g in ipairs(projectNames()) do
    local on = string.find(" " .. editText .. " ", " +" .. g .. " ", 1, true) ~= nil
    table.insert(groupsRow, chip("eg" .. g, g, on, on and "Remove from " .. g or "Add to " .. g, function()
      if on then
        editText = noctalia.string.trim((string.gsub(" " .. editText .. " ", " %+" .. g:gsub("%p", "%%%0") .. " ", " ")))
      else
        editText = editText .. " +" .. g
      end
      render()
    end))
  end
  local function addEditGroup()
    local g = string.gsub(noctalia.string.trim(editGroup), "[^%w_%-]", "_")
    editGroup = ""
    nonce = nonce + 1
    createGroup(g)
    if g ~= "" and not string.find(" " .. editText .. " ", " +" .. g .. " ", 1, true) then
      editText = editText .. " +" .. g
    end
    render()
  end
  table.insert(groupsRow, ui.input({ key = "egnew" .. nonce, value = editGroup, placeholder = "new group, Enter", controlSize = "sm", width = 150, onChange = function(v) editGroup = v end, onSubmit = addEditGroup }))
  table.insert(groupsRow, ui.button({ text = "Add group", variant = "outline", controlSize = "sm", tooltip = "Add +name to this task", onClick = addEditGroup }))
  local grid = calFor == "edit" and calendarGrid(editDue, function(d)
    editDue = d
    calFor = nil
    render()
  end) or nil
  return ui.column({ key = key, gap = 6, padding = 8, fill = "surface_variant", radius = 8 }, {
    ui.input({
      key = "etext",
      focus = true,
      value = editText,
      controlSize = "sm",
      placeholder = "Task text, +project @context",
      onChange = function(s) editText = s end,
      onSubmit = function() saveEdit(t) end,
    }),
    ui.input({ key = "enote", value = editNote, controlSize = "sm", placeholder = "More explanation (optional)", onChange = function(v) editNote = v end, onSubmit = function() saveEdit(t) end }),
    ui.row({ gap = 4, align = "center" }, { ui.label({ text = "Priority", color = "on_surface_variant" }), table.unpack(pris) }),
    ui.row({ gap = 4, align = "center" }, {
      ui.label({ text = "Due", color = "on_surface_variant" }),
      table.unpack(dues),
    }),
    grid or ui.spacer({ height = 0 }),
    ui.row({ gap = 4, align = "center" }, groupsRow),
    ui.row({ gap = 4, align = "center" }, {
      ui.input({
        key = "edue" .. editDue,
        value = shownDate(editDue),
        controlSize = "sm",
        placeholder = datePlaceholder(),
        flexGrow = 1,
        onChange = function(s) editDue = s end,
        onSubmit = function() saveEdit(t) end,
      }),
      (function()
        local note, bad = dueNote(editDue)
        return ui.label({ text = note or "no due date", color = bad and "error" or "on_surface_variant" })
      end)(),
      ui.button({ text = "Save", variant = "primary", controlSize = "sm", onClick = function() saveEdit(t) end }),
      ui.button({ text = "Cancel", variant = "ghost", controlSize = "sm", onClick = function()
        editing = nil
        render()
      end }),
    }),
  })
end

local function strike(text)
  return (string.gsub(text, utf8.charpattern, "%0\u{336}"))
end

local function cell(width, child)
  return ui.column({ width = width }, { child or ui.spacer({ height = 1 }) })
end

local function taskRow(t, key, overdue, copy, zebra, hideGroup)
  if editing == t.raw and not t.done and not copy then
    return editRow(t, key)
  end
  local children = {
    ui.button({
      glyph = t.done and "square-check" or "square",
      variant = "ghost",
      controlSize = "sm",
      tooltip = t.done and "Reopen" or "Complete",
      onClick = function()
        if t.done then
          reopen(t)
        else
          complete(t)
        end
      end,
    }),
  }
  local pri = nil
  if not t.done and t.pri then
    pri = ui.button({
      text = PRI_NAME[t.pri] or t.pri,
      variant = "ghost",
      controlSize = "sm",
      tooltip = "Priority: click to cycle High, Medium, Low, none",
      onClick = function() cyclePriority(t) end,
    })
  end
  table.insert(children, cell(90, pri))
  table.insert(children, ui.label({
    text = t.done and strike(t.text) or t.text,
    color = t.done and "on_surface_variant" or "on_surface",
    flexGrow = 1,
    maxLines = 1,
    tooltip = t.text,
  }))
  table.insert(children, cell(125, (t.due and not t.done) and colorChip(DUE_HEX[dueKind(t.due)], ui.label({ text = fmtDate(t.due), color = "on_surface" })) or nil))
  local shown = {}
  for _, tag in ipairs(t.tags) do
    if not (hideGroup and string.sub(tag, 1, 1) == "+" and string.sub(tag, 2) == groupOf(t)) then
      table.insert(shown, tag)
    end
  end
  table.insert(children, cell(150, #shown > 0 and ui.label({ text = table.concat(shown, " "), color = "on_surface_variant", maxLines = 1, tooltip = table.concat(t.tags, " ") }) or nil))
  table.insert(children, t.note and iconButton(noteOpen[t.raw] and "chevron-up" or "chevron-down", noteOpen[t.raw] and "Hide the explanation" or "Show the explanation", function()
    noteOpen[t.raw] = not noteOpen[t.raw] or nil
    render()
  end, noteOpen[t.raw]) or cell(34, nil))
  if not t.done then
    table.insert(children, iconButton("pin", t.pinned and "Unpin" or "Pin to the top", function() togglePin(t) end, t.pinned))
    table.insert(children, iconButton("pencil", "Edit", function() startEdit(t) end))
  else
    table.insert(children, cell(64, nil))
  end
  local sure = confirming == t.raw
  table.insert(children, ui.button({
    glyph = "trash",
    variant = sure and "primary" or "ghost",
    controlSize = "sm",
    tooltip = sure and "Click again to delete" or "Delete",
    onClick = function()
      if sure then
        confirming = nil
        deleteTask(t)
      else
        confirming = t.raw
        render()
      end
    end,
  }))
  if t.note and noteOpen[t.raw] then
    return ui.column({ key = key, gap = 0, padding = 3, radius = 6, fill = zebra and "surface" or nil }, {
      ui.row({ gap = 6, align = "center" }, children),
      ui.row({ gap = 6, align = "start" }, {
        cell(44, nil),
        ui.label({ text = t.note, color = "tertiary", flexGrow = 1, maxLines = 3 }),
      }),
    })
  end
  return ui.row({ key = key, gap = 6, align = "center", padding = 3, radius = 6, fill = zebra and "surface" or nil }, children)
end

local function tie(a, b)
  local pa, pb = a.pri or "~", b.pri or "~"
  if pa ~= pb then
    return pa < pb
  end
  return a.order < b.order
end

local function byDue(a, b)
  if a.due ~= b.due then
    if not a.due or not b.due then
      return a.due ~= nil
    end
    return a.due < b.due
  end
  return tie(a, b)
end

local function byName(a, b)
  local x, y = string.lower(a.text), string.lower(b.text)
  if x ~= y then
    return x < y
  end
  return tie(a, b)
end

local function byPriority(a, b)
  local pa, pb = a.pri or "~", b.pri or "~"
  if pa ~= pb then
    return pa < pb
  end
  return byDue(a, b)
end

local function section(key, title, count, rows, extra, color)
  local head = { ui.label({ text = title .. "  " .. count, color = "primary", flexGrow = 1 }) }
  if extra then
    table.insert(head, extra)
  end
  local children = { ui.row({ gap = 4, align = "center" }, head) }
  for _, r in ipairs(rows) do
    table.insert(children, r)
  end
  return ui.column({ key = key, fill = "surface_variant", radius = 10, padding = 10, gap = 2, border = color or "primary", borderWidth = 2 }, children)
end

local function groups()
  if archiveView then
    return {}
  end
  local day = today()
  local out = {}
  local function add(key, title, items, cmp, isOverdue, copy, color)
    if #items == 0 then
      return
    end
    table.sort(items, function(a, b)
      if a.done ~= b.done then
        return not a.done
      end
      if sortDesc then
        -- undated and unprioritised tasks stay last when the order is reversed
        if cmp == byDue and (a.due == nil) ~= (b.due == nil) then
          return a.due ~= nil
        elseif cmp == byPriority and (a.pri == nil) ~= (b.pri == nil) then
          return a.pri ~= nil
        end
        return cmp(b, a)
      end
      return cmp(a, b)
    end)
    local rows = {}
    local byGroup, order = {}, {}
    for _, t in ipairs(items) do
      local g = groupOf(t) or ""
      if not byGroup[g] then
        byGroup[g] = {}
        table.insert(order, g)
      end
      table.insert(byGroup[g], t)
    end
    table.sort(order, function(a, b)
      if (a == "") ~= (b == "") then
        return b == ""
      end
      local x, y = string.lower(a), string.lower(b)
      if sortDesc then
        return x > y
      end
      return x < y
    end)
    local headers = not copy and (#order > 1 or order[1] ~= "")
    local i = 0
    for _, g in ipairs(order) do
      if headers then
        table.insert(rows, ui.row({ key = key .. "h" .. g, align = "center" }, {
          ui.row({ padding = 6, radius = 8, fill = "surface", border = "outline", borderWidth = 1 }, {
            ui.label({ text = (g ~= "" and g or "No group") .. "  " .. #byGroup[g], color = "on_surface" }),
          }),
          ui.spacer({ flexGrow = 1 }),
        }))
      end
      for _, t in ipairs(byGroup[g]) do
        i = i + 1
        table.insert(rows, taskRow(t, key .. i, isOverdue, copy, i % 2 == 0, headers))
      end
    end
    local open = 0
    for _, t in ipairs(items) do
      open = open + (t.done and 0 or 1)
    end
    table.insert(out, section(key, title, open, rows, nil, color))
  end
  local cmp = sortMode == "az" and byName or sortMode == "priority" and byPriority or byDue
  local pinned, rest = {}, {}
  for _, t in ipairs(tasks) do
    if matches(t) then
      table.insert(rest, t)
      if t.pinned then
        table.insert(pinned, t)
      end
    end
  end
  local only = { later = "Later than 7 days", nodate = "No date", overdue = "Overdue", today = "Today", tomorrow = "Tomorrow", week = "Next 7 days" }
  if only[sortMode] then
    local list7 = addDays(7)
    local hits = {}
    for _, t in ipairs(rest) do
      local k = dueKind(t.due)
      if (sortMode == "later" and t.due and t.due > list7) or (sortMode == "nodate" and not t.due) or (sortMode == "overdue" and k == "overdue") or (sortMode == "today" and k == "today") or (sortMode == "tomorrow" and k == "tomorrow") or (sortMode == "week" and t.due and t.due >= day and t.due <= list7) then
        table.insert(hits, t)
      end
    end
    add("only", only[sortMode], hits, byDue, false, false, DUE_HEX[sortMode])
    return out
  end
  add("pinned", "Pinned", pinned, cmp, false, sortMode ~= "pinned")
  if sortMode == "pinned" then
    return out
  end
  if sortMode == "az" then
    add("all", "A to Z", rest, byName)
  elseif sortMode == "priority" then
    add("all", "By priority", rest, byPriority)
  else
    local overdue, now, morrow, upcoming, none = {}, {}, {}, {}, {}
    for _, t in ipairs(rest) do
      local k = dueKind(t.due)
      if not k then
        table.insert(none, t)
      elseif k == "overdue" then
        table.insert(overdue, t)
      elseif k == "today" then
        table.insert(now, t)
      elseif k == "tomorrow" then
        table.insert(morrow, t)
      else
        table.insert(upcoming, t)
      end
    end
    local base = #out
    add("overdue", "Overdue", overdue, byDue, true, false, DUE_HEX.overdue)
    add("today", "Today", now, byDue, false, false, DUE_HEX.today)
    add("tomorrow", "Tomorrow", morrow, byDue, false, false, DUE_HEX.tomorrow)
    add("upcoming", "Upcoming", upcoming, byDue, false, false, DUE_HEX.week)
    if sortDesc then
      local lo, hi = base + 1, #out
      while lo < hi do
        out[lo], out[hi] = out[hi], out[lo]
        lo, hi = lo + 1, hi - 1
      end
    end
    add("nodate", "No date", none, byDue)
  end
  return out
end

local function doneSection(force)
  local items = {}
  for _, t in ipairs(doneTasks) do
    if matches(t) then
      table.insert(items, t)
    end
  end
  if #doneTasks == 0 then
    return nil
  end
  table.sort(items, function(a, b)
    if sortDesc then
      return (a.doneDate or "") < (b.doneDate or "")
    end
    return (a.doneDate or "") > (b.doneDate or "")
  end)
  local rows = {}
  if force or not hideDone then
    for i, t in ipairs(items) do
      table.insert(rows, taskRow(t, "done" .. i))
    end
  end
  local extra = not force and iconButton(hideDone and "chevron-down" or "chevron-up", hideDone and "Show the archive" or "Hide the archive", function()
    hideDone = not hideDone
    saveState()
    render()
  end) or nil
  return section("done", "Archive", #items, rows, extra)
end

local function sideTitle(text)
  return ui.label({ text = text, color = "primary" })
end

local function doneBlock()
  local n = 0
  for _, t in ipairs(tasks) do
    if t.done then
      n = n + 1
    end
  end
  if n == 0 and #doneTasks == 0 and not archiveView then
    return {}
  end
  local sure = confirming == "cleardone"
  return {
    sideTitle("Done tasks (" .. n .. ")"),
    ui.button({ key = "viewarchive", glyph = "archive", text = "View archive (" .. #doneTasks .. ")", variant = archiveView and "primary" or "outline", controlSize = "sm", contentAlign = "start", enabled = #doneTasks > 0 or archiveView, tooltip = "Show the archived tasks; click again to go back", onClick = function()
      archiveView = not archiveView
      render()
    end }),
    ui.button({ key = "archive", glyph = "archive", text = "Move to archive", variant = "ghost", controlSize = "sm", contentAlign = "start", enabled = n > 0, tooltip = "Hide struck-through tasks in the Archive section", onClick = archiveDone }),
    ui.button({
      key = "cleardone",
      glyph = "trash",
      text = sure and "Click to confirm" or "Delete all done",
      variant = sure and "primary" or "ghost",
      controlSize = "sm",
      contentAlign = "start",
      tooltip = "Deletes struck-through tasks and the archive of this list",
      onClick = function()
        if sure then
          confirming = nil
          clearDone()
        else
          confirming = "cleardone"
          render()
        end
      end,
    }),
  }
end

local function listPanel()
  local items = { sideTitle("Lists") }
  for _, name in ipairs(lists) do
    table.insert(items, ui.button({
      key = "l" .. name,
      text = name,
      glyph = "list",
      variant = name == list and "primary" or "ghost",
      controlSize = "sm",
      contentAlign = "start",
      tooltip = "Open list " .. name,
      onClick = function()
        confirming = nil
        editing = nil
        filterTag = nil
        list = name
        saveState()
        reload()
      end,
    }))
  end
  if naming then
    local function create()
      local n = newName
      newName = ""
      naming = false
      newList(n)
      reload()
    end
    table.insert(items, ui.input({ key = "newname", focus = true, value = newName, placeholder = "List name, Enter", controlSize = "sm", onChange = function(s) newName = s end, onSubmit = create }))
  else
    table.insert(items, ui.button({ key = "newlist", glyph = "plus", text = "New list", variant = "ghost", controlSize = "sm", contentAlign = "start", tooltip = "Create a new list", onClick = function()
      naming = true
      render()
    end }))
  end
  if renaming then
    local function apply()
      if renameList(renameText) then
        renaming = false
        renameText = ""
        nonce = nonce + 1
        reload()
      else
        nonce = nonce + 1
        render()
      end
    end
    table.insert(items, ui.input({ key = "rename" .. nonce, focus = true, value = renameText, placeholder = "New name, Enter", controlSize = "sm", onChange = function(s) renameText = s end, onSubmit = apply }))
    table.insert(items, ui.row({ gap = 4, align = "center" }, {
      ui.button({ text = "Rename", variant = "primary", controlSize = "sm", onClick = apply }),
      ui.button({ text = "Cancel", variant = "ghost", controlSize = "sm", onClick = function()
        renaming = false
        render()
      end }),
    }))
  elseif not naming then
    table.insert(items, ui.button({ key = "renamelist", glyph = "pencil", text = "Rename list", variant = "ghost", controlSize = "sm", contentAlign = "start", tooltip = "Rename " .. list, onClick = function()
      renaming = true
      renameText = list
      nonce = nonce + 1
      render()
    end }))
  end
  if #lists > 1 and not naming and not renaming then
    local sure = confirming == "list"
    table.insert(items, ui.button({
      glyph = "trash",
      text = sure and "Click to confirm" or "Delete this list",
      variant = sure and "primary" or "ghost",
      controlSize = "sm",
      contentAlign = "start",
      tooltip = "Deletes the list and its done tasks",
      onClick = function()
        if sure then
          confirming = nil
          removeList()
        else
          confirming = "list"
          render()
        end
      end,
    }))
  end
  return items
end

local function tagPanel()
  local counts, names = {}, {}
  for _, t in ipairs(tasks) do
    for _, tag in ipairs(not t.done and t.tags or {}) do
      if not counts[tag] then
        counts[tag] = 0
        table.insert(names, tag)
      end
      counts[tag] = counts[tag] + 1
    end
  end
  for _, g in ipairs(savedGroups) do
    if not counts["+" .. g] then
      counts["+" .. g] = 0
      table.insert(names, "+" .. g)
    end
  end
  table.sort(names)
  local function create()
    createGroup(newGroup)
    newGroup = ""
    nonce = nonce + 1
    reload()
  end
  local items = {
    sideTitle("Groups (+) and contexts (@)"),
    ui.row({ gap = 4, align = "center" }, {
      ui.input({ key = "newgroup" .. nonce, value = newGroup, placeholder = "New group, Enter", controlSize = "sm", flexGrow = 1, onChange = function(v) newGroup = v end, onSubmit = create }),
      ui.button({ glyph = "plus", variant = "outline", controlSize = "sm", tooltip = "Create a group without a task", onClick = create }),
    }),
  }
  for _, tag in ipairs(names) do
    local btn = ui.button({
      key = "f" .. tag,
      text = tag .. "  (" .. counts[tag] .. ")",
      variant = filterTag == tag and "primary" or "ghost",
      controlSize = "sm",
      contentAlign = "start",
      flexGrow = 1,
      tooltip = "Show only " .. tag .. "; click again to show all",
      onClick = function()
        filterTag = filterTag ~= tag and tag or nil
        render()
      end,
    })
    if counts[tag] == 0 then
      table.insert(items, ui.row({ gap = 2, align = "center" }, { btn, iconButton("x", "Remove the empty group", function()
        removeSavedGroup(string.sub(tag, 2))
        render()
      end) }))
    else
      table.insert(items, btn)
    end
  end
  return items
end

local function addCard()
  if not addOpen then
    return ui.row({ key = "addbar", align = "center" }, {
      ui.button({ glyph = "plus", text = "New task", variant = "outline", controlSize = "sm", tooltip = "Show the new task part", onClick = function()
        addOpen = true
        saveState()
        render()
      end }),
      ui.spacer({ flexGrow = 1 }),
    })
  end
  local function submit()
    local text, pri, due, note = addText, addPri, addDue, addNote
    if noctalia.string.trim(due or "") ~= "" and not normDate(due) then
      render()
      return
    end
    local g = string.gsub(noctalia.string.trim(addGroup), "[^%w_%-]", "_")
    if g ~= "" and not string.find(" " .. text .. " ", " +" .. g .. " ", 1, true) then
      text = text .. " +" .. g
    end
    addText, addPri, addDue, addGroup, addNote = "", nil, nil, "", ""
    nonce = nonce + 1
    addTask(text, pri, due, note)
    reload()
  end
  local pri = { ui.label({ text = "Priority:", color = "on_surface_variant" }) }
  for _, p in ipairs({ { "A", "High" }, { "B", "Medium" }, { "C", "Low" } }) do
    table.insert(pri, chip("ap" .. p[1], p[2], addPri == p[1], "Priority " .. p[1] .. "; click again to clear", function()
      addPri = addPri ~= p[1] and p[1] or nil
      render()
    end))
  end
  local due = { ui.label({ text = "Due:", color = "on_surface_variant" }) }
  for _, d in ipairs({ { "Today", 0 }, { "Tomorrow", 1 }, { "In 1 week", 7 } }) do
    local date = addDays(d[2])
    table.insert(due, colorChip(DUE_HEX[dueKind(addDays(d[2]))], chip("ad" .. d[1], d[1], addDue == date, "Due " .. fmtDate(date) .. "; click again to clear", function()
      addDue = addDue ~= date and date or nil
      render()
    end)))
  end
  table.insert(due, ui.button({ key = "acal", glyph = "calendar", text = "Pick date", variant = calFor == "add" and "primary" or "ghost", controlSize = "sm", tooltip = "Choose a day in a calendar", onClick = function() openCalendar("add", addDue) end }))
  table.insert(due, ui.input({ key = "adue" .. (addDue or ""), value = shownDate(addDue), placeholder = datePlaceholder(), controlSize = "sm", width = 130, onChange = function(v) addDue = v ~= "" and v or nil end, onSubmit = submit }))
  local note, bad = dueNote(addDue)
  table.insert(due, ui.label({ text = note or "no due date", color = bad and "error" or "on_surface_variant" }))
  local grp = { ui.label({ text = "Group:", color = "on_surface_variant" }) }
  for _, g in ipairs(projectNames()) do
    table.insert(grp, chip("ag" .. g, g, addGroup == g, "Add to group " .. g .. "; click again to clear", function()
      addGroup = addGroup ~= g and g or ""
      render()
    end))
  end
  table.insert(grp, ui.input({ key = "agnew" .. nonce .. addGroup, value = addGroup, placeholder = "new group, e.g. work", controlSize = "sm", width = 170, onChange = function(v) addGroup = v end, onSubmit = function()
    addGroup = createGroup(addGroup)
    nonce = nonce + 1
    reload()
  end }))
  return ui.column({ key = "addcard", fill = "surface_variant", radius = 10, padding = 10, gap = 6, border = "primary", borderWidth = 1 }, {
    ui.row({ gap = 4, align = "center" }, {
      ui.input({ key = "add" .. nonce, focus = not editing and not naming, value = addText, placeholder = "New task, e.g. call Anna +home @phone", flexGrow = 1, onChange = function(s) addText = s end, onSubmit = submit }),
      ui.button({ glyph = "plus", text = "Add task", variant = "primary", tooltip = "Add the task (or press Enter)", onClick = submit }),
      iconButton("chevron-up", "Hide this part", function()
        addOpen = false
        calFor = nil
        saveState()
        render()
      end),
    }),
    ui.input({ key = "addnote" .. nonce, value = addNote, placeholder = "More explanation (optional)", controlSize = "sm", onChange = function(s) addNote = s end, onSubmit = submit }),
    ui.row({ gap = 4, align = "center" }, pri),
    ui.row({ gap = 4, align = "center" }, due),
    ui.row({ gap = 4, align = "center" }, grp),
    calFor == "add" and calendarGrid(addDue, function(d)
      addDue = d
      calFor = nil
      render()
    end) or ui.spacer({ height = 0 }),
    ui.label({ text = "Pick priority and due date (or type " .. datePlaceholder() .. "), then add. +word = project, @word = context.", color = "on_surface_variant" }),
  })
end

render = function()
  local body = groups()
  local done = doneSection(archiveView)
  if done then
    table.insert(body, done)
  end
  if archiveView and #body == 0 then
    table.insert(body, ui.label({ text = "The archive is empty", color = "on_surface_variant" }))
  elseif #tasks == 0 then
    table.insert(body, 1, ui.label({ text = addOpen and "Nothing to do. Type a task above and press Enter." or "Nothing to do. Click New task to add one.", color = "on_surface_variant" }))
  elseif #body == 0 then
    table.insert(body, ui.label({ text = "No tasks match the current filter or sort", color = "on_surface_variant" }))
  end
  local function card(key, items)
    return ui.column({ key = key, fill = "surface_variant", radius = 10, padding = 10, gap = 4, border = "primary", borderWidth = 1 }, items)
  end
  local sortItems = { sideTitle("Sort tasks"), ui.button({
    key = "sortdir",
    glyph = "arrows-up-down",
    text = sortDesc and "Order: descending" or "Order: ascending",
    variant = "outline",
    controlSize = "sm",
    contentAlign = "start",
    flexGrow = 1,
    tooltip = "Reverse the order of sections, groups and tasks",
    onClick = function()
      sortDesc = not sortDesc
      saveState()
      render()
    end,
  }) }
  for _, m in ipairs({ { "date", "By date", "calendar" }, { "az", "A to Z", "sort-ascending" }, { "priority", "By priority", "flag" }, { "pinned", "Pinned only", "pin" }, { "overdue", "Overdue only", "dot", "overdue" }, { "today", "Today only", "dot", "today" }, { "tomorrow", "Tomorrow only", "dot", "tomorrow" }, { "week", "Next 7 days", "dot", "week" }, { "later", "Later than 7 days", "dot", "later" }, { "nodate", "No date", "dot", "nodate" } }) do
    local btn = ui.button({ key = "s" .. m[1], glyph = m[4] == nil and m[3] or nil, text = m[2], variant = sortMode == m[1] and not archiveView and "primary" or "outline", controlSize = "sm", contentAlign = "start", flexGrow = 1, onClick = function()
      sortMode = m[1]
      archiveView = false
      saveState()
      render()
    end })
    table.insert(sortItems, m[4] and ui.row({ gap = 4, align = "center" }, { dot(DUE_HEX[m[4]]), btn }) or btn)
  end
  local side = { card("lists", listPanel()), card("sort", sortItems) }
  local tagItems = tagPanel()
  if #tagItems > 0 then
    table.insert(side, card("tags", tagItems))
  end
  local doneItems = doneBlock()
  if #doneItems > 0 then
    table.insert(side, card("donecard", doneItems))
  end
  local visible = 0
  if not archiveView then
    for _, t in ipairs(tasks) do
      visible = visible + (matches(t) and 1 or 0)
    end
  end
  for _, t in ipairs((hideDone and not archiveView) and {} or doneTasks) do
    visible = visible + (matches(t) and 1 or 0)
  end
  table.insert(body, ui.spacer({ height = 16 }))
  local content = (visible > (addOpen and 6 or 9) or editing) and ui.column({ height = addOpen and 380 or 620 }, { ui.scroll({ flexGrow = 1, key = "list" }, { ui.column({ gap = 8, padding = 4 }, body) }) }) or ui.column({ gap = 8 }, body)
  local banner = ui.spacer({ height = 0 })
  if filterTag or noctalia.string.trim(filterText) ~= "" then
    local what = {}
    if filterTag then
      table.insert(what, "group " .. filterTag)
    end
    if noctalia.string.trim(filterText) ~= "" then
      table.insert(what, "search \"" .. noctalia.string.trim(filterText) .. "\"")
    end
    banner = ui.row({ gap = 6, align = "center" }, {
      ui.label({ text = "Filter active: " .. table.concat(what, ", "), color = "primary", flexGrow = 1 }),
      ui.button({ text = "Clear filter", variant = "outline", controlSize = "sm", onClick = function()
        filterTag = nil
        filterText = ""
        nonce = nonce + 1
        render()
      end }),
    })
  end
  local notesBar = ui.spacer({ height = 0 })
  local noteCount = 0
  for _, t in ipairs(tasks) do
    noteCount = noteCount + (t.note and 1 or 0)
  end
  if noteCount > 0 then
    local function setAll(v)
      noteOpen = {}
      if v then
        for _, t in ipairs(tasks) do
          if t.note then
            noteOpen[t.raw] = true
          end
        end
      end
      render()
    end
    notesBar = ui.row({ gap = 6, align = "center" }, {
      ui.label({ text = "Explanations (" .. noteCount .. ")", color = "tertiary", flexGrow = 1 }),
      ui.button({ glyph = "chevron-down", text = "Show all", variant = "outline", controlSize = "sm", onClick = function() setAll(true) end }),
      ui.button({ glyph = "chevron-up", text = "Hide all", variant = "outline", controlSize = "sm", onClick = function() setAll(false) end }),
    })
  end
  local search = ui.input({ key = "filter" .. nonce, value = filterText, placeholder = "Search tasks (text, +project, @context)", controlSize = "sm", onChange = function(v)
    filterText = v
    render()
  end })
  panel.render(ui.row({ gap = 12, padding = 12, align = "start" }, {
    ui.column({ width = 240, height = 620 }, { ui.scroll({ flexGrow = 1, key = "side" }, { ui.column({ gap = 8, padding = 4 }, side) }) }),
    ui.column({ gap = 8, flexGrow = 1 }, { addCard(), search, banner, notesBar, content }),
  }))
end

local function open()
  if not dateFormatLoaded then
    dateFormatLoaded = true
    noctalia.runAsync({ "locale", "d_fmt" }, function(r)
      local before = table.concat(dateOrder) .. dateSep
      setDateFormat(string.gsub(r.stdout or "", "%s+$", ""))
      if table.concat(dateOrder) .. dateSep ~= before then
        render()
      end
    end)
  end
  loadState()
  naming = false
  renaming = false
  confirming = nil
  editing = nil
  calFor = nil
  archiveView = false
  addText, addPri, addDue, addGroup, addNote, filterText, filterTag = "", nil, nil, "", "", "", nil
  reload()
end

local function key(chord)
  if chord == "escape" then
    if editing or calFor then
      editing = nil
      calFor = nil
      render()
    else
      panel.close()
    end
  end
end

return open, key
end
