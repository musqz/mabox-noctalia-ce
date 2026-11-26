--!nonstrict
-- /bars: one row that opens the Bars panel.

function onQuery(text)
  launcher.setResults(text, { { id = "open", title = "Bars", subtitle = "Bar profiles", glyph = "layout-navbar" } })
end

-- The short sleep lets the launcher close first.
function onActivate(id)
  noctalia.runAsync({ "sh", "-c", "sleep 0.2; exec noctalia msg panel-open mabox/bars:main" })
end
