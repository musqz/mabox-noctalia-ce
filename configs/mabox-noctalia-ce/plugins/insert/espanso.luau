--!nonstrict
-- /es: search Espanso matches; Enter types the replacement text into the previous window.
-- Matches with variables ({{...}}) need the Espanso daemon and are listed only.

local PY = [[
import json, sys
for m in json.load(sys.stdin):
    r = m.get("replace")
    if not isinstance(r, str):
        continue
    r = r.replace("\\", "\\\\").replace("\t", "\\t").replace("\n", "\\n").replace("\r", "")
    for t in m.get("triggers") or []:
        t = t.replace("\t", " ").replace("\n", " ")
        print(t + "\t" + r)
]]

local matches = nil

local function unescape(s)
  return (string.gsub(s, "\\(.)", function(c)
    if c == "n" then
      return "\n"
    elseif c == "t" then
      return "\t"
    end
    return c
  end))
end

local function parse(text)
  local out = {}
  for line in string.gmatch(text, "[^\n]+") do
    local trigger, raw = string.match(line, "^([^\t]*)\t(.*)$")
    if trigger then
      local replace = unescape(raw)
      table.insert(out, { trigger = trigger, replace = replace, first = noctalia.string.trim(string.match(replace, "[^\n]*")), dynamic = string.find(replace, "{{", 1, true) ~= nil })
    end
  end
  return out
end

local function withMatches(refresh, done)
  if matches and not refresh then
    done()
    return
  end
  noctalia.runAsync({ "sh", "-c", 'espanso match list -j | python3 -c "$1"', "sh", PY }, function(result)
    if result.exitCode == 0 then
      matches = parse(result.stdout or "")
    end
    done()
  end)
end

local function render(text, q)
  local rows = {}
  for i, m in ipairs(matches or {}) do
    local score
    if q == "" then
      score = 1000 - i
    else
      local a = noctalia.fuzzyScore(q, m.trigger)
      local b = noctalia.fuzzyScore(q, m.replace)
      score = a
      if b ~= nil and (score == nil or b > score) then
        score = b
      end
    end
    if score ~= nil then
      table.insert(rows, {
        id = m.dynamic and "" or ("m" .. i),
        title = m.trigger,
        subtitle = m.dynamic and ("needs Espanso  -  " .. m.first) or m.first,
        glyph = "text-plus",
        score = score,
      })
    end
  end
  if #rows == 0 then
    local empty = matches == nil or #matches == 0
    rows[1] = { id = "", title = empty and "No Espanso matches" or ("Nothing matches '" .. q .. "'"), glyph = "mood-empty" }
  end
  launcher.setResults(text, rows)
end

function onQuery(text)
  local q = noctalia.string.trim(text or "")
  withMatches(q == "", function()
    render(text, q)
  end)
end

-- The sleep lets the launcher close and focus return to the previous window.
function onActivate(id)
  local m = (matches or {})[tonumber(string.match(id or "", "^m(%d+)$")) or 0]
  if m and not m.dynamic then
    noctalia.runAsync({ "sh", "-c", 'sleep 0.25; printf "%s" "$1" | exec wtype -', "sh", m.replace })
  end
end
