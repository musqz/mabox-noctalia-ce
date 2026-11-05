--!nonstrict
-- /wp: pick a saved wallpaper folder; Enter makes it the wallpaper directory.

local dirs = require("./lib/dirs.luau")

function onQuery(text)
  local q = noctalia.string.trim(text or "")
  local rows = {}
  for i, p in ipairs(dirs.load()) do
    local name = dirs.name(p)
    local score = q == "" and 1000 - i or noctalia.fuzzyScore(q, name)
    if score ~= nil then
      table.insert(rows, { id = p, title = name, subtitle = p, glyph = "photo", score = score })
    end
  end
  table.sort(rows, function(a, b)
    return a.score > b.score
  end)
  if #rows == 0 then
    rows[1] = { id = "", title = q == "" and "No saved folders (add them in the panel)" or ("Nothing matches '" .. q .. "'"), glyph = "mood-empty" }
  end
  launcher.setResults(text, rows)
end

function onActivate(id)
  if id ~= nil and id ~= "" then
    dirs.apply(id)
  end
end
