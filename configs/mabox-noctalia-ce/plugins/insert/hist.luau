--!nonstrict
-- /hist: search ~/.bash_history; Enter types the line into the previous window (no Enter key).

local HIST = noctalia.getenv("HOME") .. "/.bash_history"
local MAX_LEN = 300
local SEARCH_LIMIT = 2000

-- Newest first, one entry per line. Read again each time the launcher opens with an empty query.
local entries = {}

local function load()
  local raw = noctalia.readFile(HIST) or ""
  local lines = {}
  for line in string.gmatch(raw, "[^\n]+") do
    table.insert(lines, line)
  end
  local seen = {}
  local out = {}
  for i = #lines, 1, -1 do
    local l = lines[i]
    if #l <= MAX_LEN and string.match(l, "%S") and not string.match(l, "^#%d+$") and not seen[l] then
      seen[l] = true
      table.insert(out, l)
    end
  end
  entries = out
end

function onQuery(text)
  local q = noctalia.string.trim(text or "")
  if q == "" or #entries == 0 then
    load()
  end
  local rows = {}
  if q == "" then
    for i = 1, math.min(30, #entries) do
      table.insert(rows, { id = entries[i], title = entries[i], glyph = "history", score = 1000 - i })
    end
  else
    for i = 1, math.min(SEARCH_LIMIT, #entries) do
      local score = noctalia.fuzzyScore(q, entries[i])
      if score ~= nil then
        table.insert(rows, { id = entries[i], title = entries[i], glyph = "history", score = score })
      end
    end
    table.sort(rows, function(a, b)
      return a.score > b.score
    end)
    for i = #rows, 51, -1 do
      rows[i] = nil
    end
  end
  if #rows == 0 then
    rows[1] = { id = "", title = q == "" and "No shell history" or ("Nothing matches '" .. q .. "'"), glyph = "mood-empty" }
  end
  launcher.setResults(text, rows)
end

-- The sleep lets the launcher close and focus return to the previous window.
function onActivate(id)
  if id == nil or id == "" then
    return
  end
  noctalia.runAsync({ "sh", "-c", 'sleep 0.25; exec wtype -- "$1"', "sh", id })
end
