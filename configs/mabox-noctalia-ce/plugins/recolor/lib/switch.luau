--!nonstrict
-- Recolor and Wallgen are two panels of one plugin; this header switch moves between them.
local PANELS = { { "main", "Recolor", "wand" }, { "wallgen", "Wallgen", "sparkles" } }

return function(current)
  local buttons = {}
  for _, p in ipairs(PANELS) do
    local on = p[1] == current
    table.insert(buttons, ui.button({
      key = "switch-" .. p[1],
      glyph = p[3],
      text = p[2],
      variant = on and "primary" or "outline",
      controlSize = "sm",
      tooltip = (not on) and ("Open " .. p[2]) or nil,
      onClick = function()
        if not on then
          noctalia.runAsync({ "setsid", "-f", "sh", "-c", "noctalia msg panel-close; sleep 0.2; noctalia msg panel-open mabox/recolor:" .. p[1] })
        end
      end,
    }))
  end
  return ui.row({ gap = 4 }, buttons)
end
