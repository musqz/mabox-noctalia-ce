--!nonstrict
-- Open tasks due today or earlier from every ~/.todo list (read only).

local DIR = noctalia.getenv("HOME") .. "/.todo"
local DATE = "%d%d%d%d%-%d%d%-%d%d"

local function parse(raw)
  local rest = raw
  if string.match(rest, "^x ") then
    return nil
  end
  local pri = string.match(rest, "^%((%u)%) ")
  if pri then
    rest = string.sub(rest, 5)
  end
  local date = string.match(rest, "^(" .. DATE .. ") ")
  if date then
    rest = string.sub(rest, #date + 2)
  end
  local due = string.match(rest, "%f[%S]due:(" .. DATE .. ")%f[%s%z]")
  if not due then
    return nil
  end
  rest = string.gsub(rest, "%f[%S]due:" .. DATE .. "%f[%s%z]", "")
  rest = string.gsub(rest, "%f[%S]color:%a+%f[%s%z]", "")
  rest = string.gsub(rest, "%f[%S]note:%S+", "")
  rest = string.gsub(rest, "%f[%S]pin:1%f[%s%z]", "")
  rest = string.gsub(rest, "%f[%S][+@]%S+", "")
  return { text = noctalia.string.trim(rest), pri = pri, due = due }
end

local function byPriority(a, b)
  local pa, pb = a.pri or "~", b.pri or "~"
  if pa ~= pb then
    return pa < pb
  end
  if a.due ~= b.due then
    return a.due < b.due
  end
  return a.text < b.text
end

local function load()
  local lists = {}
  for _, name in ipairs(noctalia.listDir(DIR) or {}) do
    local base = string.match(name, "^(.+)%.txt$")
    if base and not string.match(base, "^done_") and not string.match(base, "^report_") and base ~= "done" and base ~= "report" then
      table.insert(lists, base)
    end
  end
  table.sort(lists)
  local day = os.date("%Y-%m-%d")
  local overdue, now = {}, {}
  for _, name in ipairs(lists) do
    for l in string.gmatch(noctalia.readFile(DIR .. "/" .. name .. ".txt") or "", "[^\n]+") do
      local t = parse(l)
      if t and t.due <= day then
        t.list = name
        table.insert(t.due < day and overdue or now, t)
      end
    end
  end
  table.sort(overdue, byPriority)
  table.sort(now, byPriority)
  return { overdue = overdue, today = now, lists = #lists }
end

return { load = load }
