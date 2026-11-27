--!nonstrict
-- /sessions: one row that opens the Sessions panel.

function onQuery(text)
  launcher.setResults(text, { { id = "open", title = "Sessions", subtitle = "Workspaces with their apps", glyph = "layout-grid" } })
end

-- The short sleep lets the launcher close first.
function onActivate(id)
  noctalia.runAsync({ "sh", "-c", "sleep 0.2; exec noctalia msg panel-open mabox/sessions:main" })
end
