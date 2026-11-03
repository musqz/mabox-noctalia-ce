--!nonstrict
-- /keys: search the hotkeys; Enter runs the bind's command (labwc actions like Close are listed only).

local binds = nil

local function parse(text)
  local out = {}
  for line in string.gmatch(text, "[^\n]+") do
    local f = {}
    for part in string.gmatch(line .. "\t", "(.-)\t") do
      table.insert(f, part)
    end
    if #f >= 8 then
      local keys = f[2] ~= "" and string.gsub(f[2], "%+", " + ") .. " + " .. f[3] or f[3]
      table.insert(out, { spec = f[1], keys = keys, group = f[4], basic = f[5] == "1", desc = f[6], command = f[7], run = f[8] == "1" })
    end
  end
  return out
end

-- The list is read again each time the launcher opens with an empty query.
local function withBinds(refresh, done)
  if binds and not refresh then
    done()
    return
  end
  noctalia.runAsync({ "mb-keys", "list", "--tsv" }, function(result)
    if result.exitCode == 0 then
      binds = parse(result.stdout or "")
    end
    done()
  end)
end

local function render(text, q)
  local rows = {}
  for i, b in ipairs(binds or {}) do
    local score
    if q == "" then
      score = b.basic and 1000 - i or nil
    else
      local best = nil
      for _, hay in ipairs({ b.desc, b.keys, b.run and b.command or "" }) do
        local s = noctalia.fuzzyScore(q, hay)
        if s ~= nil and (best == nil or s > best) then
          best = s
        end
      end
      score = best
    end
    if score ~= nil then
      table.insert(rows, { id = b.run and ("run:" .. b.spec) or "", title = b.desc, subtitle = b.keys .. (b.run and "  -  Enter to run" or ""), glyph = "keyboard", score = score })
    end
  end
  if #rows == 0 then
    rows[1] = { id = "", title = binds and ("Nothing matches '" .. q .. "'") or "Could not read the keybinds", glyph = "mood-empty" }
  end
  launcher.setResults(text, rows)
end

function onQuery(text)
  local q = noctalia.string.trim(text or "")
  withBinds(q == "", function()
    render(text, q)
  end)
end

-- The short sleep lets the launcher close first, as in the tools plugin.
function onActivate(id)
  local spec = string.match(id or "", "^run:(.+)$")
  for _, b in ipairs(binds or {}) do
    if b.spec == spec then
      noctalia.runAsync({ "sh", "-c", 'sleep 0.2; exec setsid sh -c "$1"', "sh", b.command })
      return
    end
  end
end
