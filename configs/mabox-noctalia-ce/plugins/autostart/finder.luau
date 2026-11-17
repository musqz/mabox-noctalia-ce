--!nonstrict
-- /autostart: one row that opens the Autostart panel.

function onQuery(text)
  launcher.setResults(text, { { id = "open", title = "Autostart", subtitle = "Startup programs of the session", glyph = "rocket" } })
end

-- The short sleep lets the launcher close first.
function onActivate(id)
  noctalia.runAsync({ "sh", "-c", "sleep 0.2; exec noctalia msg panel-open mabox/autostart:main" })
end
