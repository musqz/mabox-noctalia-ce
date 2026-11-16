--!nonstrict
-- Recolor and Wallgen are panels of one plugin; this header switch moves between them.
-- Wallgen opens in its compact layout on a small screen (the narrowest output is under 1900 px wide) or when you came from it.
local OPEN = [[noctalia msg panel-close
sleep 0.2
t=$1
if [ "$t" = wallgen ]; then
  w=$(wlr-randr 2>/dev/null | awk '/current/ { split($1, a, "x"); if (min == "" || a[1] + 0 < min) min = a[1] + 0 } END { print min }')
  [ "${w:-9999}" -lt 1900 ] && t=wallgen-compact
fi
noctalia msg panel-open "mabox/recolor:$t"]]

local PANELS = { { "main", "Recolor", "wand" }, { "wallgen", "Wallgen", "sparkles" } }

return function(current)
  local buttons = {}
  for _, p in ipairs(PANELS) do
    local on = p[1] == current or (p[1] == "wallgen" and current == "wallgen-compact")
    table.insert(buttons, ui.button({
      key = "switch-" .. p[1],
      glyph = p[3],
      text = p[2],
      variant = on and "primary" or "outline",
      controlSize = "sm",
      tooltip = (not on) and ("Open " .. p[2]) or nil,
      onClick = function()
        if not on then
          noctalia.runAsync({ "setsid", "-f", "sh", "-c", OPEN, "sh", p[1] })
        end
      end,
    }))
  end
  return ui.row({ gap = 4 }, buttons)
end
