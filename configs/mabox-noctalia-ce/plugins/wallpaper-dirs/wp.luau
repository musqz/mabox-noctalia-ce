--!nonstrict
-- /wp: pick a saved wallpaper folder; Enter makes it the wallpaper directory.
-- /wp add opens the folder chooser; /wp list shows the saved folders.

local dirs = require("./lib/dirs.luau")

local ADD = "wp:add"

function onQuery(text)
  local q = noctalia.string.trim(text or "")
  local rows = {}
  if q == "add" then
    launcher.setResults(text, { { id = ADD, title = "Add folder", subtitle = "Choose a wallpaper folder", glyph = "folder-plus", score = 1 } })
    return
  end
  if q == "list" then
    q = ""
  end
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
    rows[1] = { id = "", title = q == "" and "No saved folders (type add to add one)" or ("Nothing matches '" .. q .. "'"), glyph = "mood-empty" }
  end
  launcher.setResults(text, rows)
end

function onActivate(id)
  if id == ADD then
    dirs.current(function(p)
      dirs.browse(p ~= "" and p or noctalia.getenv("HOME"))
    end)
  elseif id ~= nil and id ~= "" then
    dirs.apply(id)
  end
end
