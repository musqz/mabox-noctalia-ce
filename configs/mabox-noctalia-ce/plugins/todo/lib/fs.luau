--!nonstrict
-- Font sizes of a desktop widget: the widget's own "Text size" setting (percent), divided by Noctalia's global
-- accessibility.ui_scale so the global Text size card does not shrink widgets. Keep this file identical in every widget plugin's lib/.
local scale, checked = 1.0, 0

local function uiScale()
  if os.time() - checked < 5 then
    return scale
  end
  checked = os.time()
  local base = noctalia.getenv("XDG_STATE_HOME")
  if not base or base == "" then
    base = (noctalia.getenv("HOME") or "") .. "/.local/state"
  end
  local inside, v = false, nil
  for line in string.gmatch(noctalia.readFile(base .. "/noctalia/settings.toml") or "", "[^\n]+") do
    local h = string.match(line, "^%s*%[([^%]]+)%]%s*$")
    if h then
      inside = h == "accessibility"
    elseif inside then
      v = tonumber(string.match(line, "^%s*ui_scale%s*=%s*([%d%.]+)")) or v
    end
  end
  scale = math.max(0.5, math.min(2.0, v or 1.0))
  return scale
end

return function(base)
  local pct = math.max(50, math.min(200, tonumber(noctalia.getConfig("size")) or 100))
  return math.max(6, math.floor(base * pct / 100 / uiScale() + 0.5))
end
