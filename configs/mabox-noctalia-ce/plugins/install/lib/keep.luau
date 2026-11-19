--!nonstrict
-- Header switch of a top panel: reopens it as the persistent copy (stays open when another panel opens) or as the normal one.
-- Keep this file identical in every plugin's lib/.
return function(plugin, normalId, keepId, stay)
  return ui.row({ key = "keep-switch", gap = 4, align = "center" }, {
    ui.toggle({ key = "keep" .. (stay and "1" or "0"), checked = stay, tooltip = "Keep this panel open when another panel opens", onChange = function()
      noctalia.runAsync({ "setsid", "-f", "sh", "-c", "sleep 0.3; noctalia msg panel-open mabox/" .. plugin .. ":" .. (stay and normalId or keepId) })
      panel.close()
    end }),
    ui.label({ text = "Keep open", color = "on_surface_variant", fontSize = 11 }),
  })
end
