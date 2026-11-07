--!nonstrict
-- /mb: open the Mabox panels. Pinned entries go through mb-pinned, which picks the saved side.

local TOOLS = {
  { id = "colors", title = "Colors", glyph = "palette", cmd = { "noctalia", "msg", "panel-toggle", "mabox/colors:picker" }, pinned = "colors" },
  { id = "notes", title = "Notes", glyph = "notes", cmd = { "noctalia", "msg", "panel-toggle", "mabox/notes:main" }, pinned = "notes" },
  { id = "status", title = "Status", glyph = "activity", cmd = { "noctalia", "msg", "panel-toggle", "mabox/status:main" }, pinned = "status" },
  { id = "configs", title = "Config files", glyph = "file-settings", cmd = { "noctalia", "msg", "panel-toggle", "mabox/configs:main" }, pinned = "configs" },
  { id = "wallpaper", title = "Wallpaper folders", glyph = "photo", cmd = { "noctalia", "msg", "panel-toggle", "mabox/wallpaper-dirs:dirs" } },
  { id = "system", title = "System info", glyph = "device-desktop-analytics", cmd = { "noctalia", "msg", "panel-toggle", "mabox/system:system" } },
  { id = "cava", title = "Cava", glyph = "chart-bar", cmd = { "mb-cava", "toggle" } },
  { id = "cava-settings", title = "Cava settings", glyph = "adjustments", cmd = { "noctalia", "msg", "panel-toggle", "mabox/cava:main" } },
  { id = "snapshot", title = "Snapshot", glyph = "disc", cmd = { "noctalia", "msg", "panel-open", "mabox/snapshot:main" } },
  { id = "reset", title = "Reset configs", glyph = "restore", cmd = { "noctalia", "msg", "panel-toggle", "mabox/reset:main" } },
}

local ENTRIES = {}
for _, t in ipairs(TOOLS) do
  table.insert(ENTRIES, { id = t.id, title = t.title, glyph = t.glyph, cmd = t.cmd })
  if t.pinned then
    table.insert(ENTRIES, { id = t.id .. ":pinned", title = t.title .. " pinned", glyph = "pin", cmd = { "mb-pinned", t.pinned } })
  end
end

function onQuery(text)
  local q = noctalia.string.trim(text or "")
  local rows = {}
  for i, e in ipairs(ENTRIES) do
    local score = 1000 - i
    if q ~= "" then
      score = noctalia.fuzzyScore(q, e.title)
    end
    if score ~= nil then
      table.insert(rows, { id = e.id, title = e.title, subtitle = "Mabox", glyph = e.glyph, score = score })
    end
  end
  if #rows == 0 then
    rows[1] = { id = "", title = "Nothing matches '" .. q .. "'", glyph = "mood-empty" }
  end
  launcher.setResults(text, rows)
end

-- The short sleep lets the launcher close first; it holds the one normal panel slot.
function onActivate(id)
  for _, e in ipairs(ENTRIES) do
    if e.id == id then
      local argv = { "sh", "-c", 'sleep 0.2; exec "$@"', "sh" }
      for _, a in ipairs(e.cmd) do
        table.insert(argv, a)
      end
      noctalia.runAsync(argv)
      return
    end
  end
end
